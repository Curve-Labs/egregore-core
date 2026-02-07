/**
 * Clean mask texture generation with CPU-side dilation.
 */

import * as THREE from 'three'
import { dilateMask, thicknessToRadius, combineMasks } from './dilation'

const MASK_WIDTH = 1024
const MASK_HEIGHT = 512
const MASK_MARGIN = 0.06

function loadSvgImage(svgString: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onerror = reject
    const blob = new Blob([svgString], { type: 'image/svg+xml' })
    const url = URL.createObjectURL(blob)
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve(img)
    }
    img.src = url
  })
}

function injectLayerOverrides(svgText: string, showCls: 'cls-1' | 'cls-2'): string {
  const overrides = showCls === 'cls-1'
    ? '\n.cls-1 { fill: #ffffff !important; opacity: 1 !important; }\n.cls-2 { fill: #000000 !important; opacity: 0 !important; }\n'
    : '\n.cls-1 { fill: #000000 !important; opacity: 0 !important; }\n.cls-2 { fill: #ffffff !important; opacity: 1 !important; }\n'

  if (svgText.includes('</style>')) {
    return svgText.replace('</style>', `${overrides}</style>`)
  }

  return svgText.replace(/<svg([^>]*)>/, `<svg$1><style>${overrides}</style>`)
}

function getDrawParams(
  img: HTMLImageElement,
  width: number,
  height: number,
  margin: number
): { drawW: number; drawH: number; drawX: number; drawY: number } {
  const contentW = width * (1 - 2 * margin)
  const contentH = height * (1 - 2 * margin)
  const offsetX = width * margin
  const offsetY = height * margin

  const svgAspect = img.naturalWidth / img.naturalHeight
  const contentAspect = contentW / contentH

  let drawW, drawH, drawX, drawY
  if (svgAspect > contentAspect) {
    drawW = contentW
    drawH = contentW / svgAspect
    drawX = offsetX
    drawY = offsetY + (contentH - drawH) / 2
  } else {
    drawH = contentH
    drawW = contentH * svgAspect
    drawX = offsetX + (contentW - drawW) / 2
    drawY = offsetY
  }

  return { drawW, drawH, drawX, drawY }
}

function renderLayerToMask(
  img: HTMLImageElement,
  width: number,
  height: number,
  margin: number
): Uint8Array {
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')!

  ctx.fillStyle = 'black'
  ctx.fillRect(0, 0, width, height)

  const { drawW, drawH, drawX, drawY } = getDrawParams(img, width, height, margin)
  ctx.drawImage(img, drawX, drawY, drawW, drawH)

  const imageData = ctx.getImageData(0, 0, width, height)
  const mask = new Uint8Array(width * height)

  for (let i = 0; i < mask.length; i++) {
    mask[i] = imageData.data[i * 4] > 10 ? 255 : 0
  }

  return mask
}

export interface MaskTextureOptions {
  svgText: string
  weBuildThickness: number
  gridCellSize: number
}

export async function createMaskTexture(
  options: MaskTextureOptions
): Promise<THREE.DataTexture> {
  const { svgText, weBuildThickness, gridCellSize } = options

  const [digitalImg, weBuildImg] = await Promise.all([
    loadSvgImage(injectLayerOverrides(svgText, 'cls-1')),
    loadSvgImage(injectLayerOverrides(svgText, 'cls-2')),
  ])

  const digitalMask = renderLayerToMask(digitalImg, MASK_WIDTH, MASK_HEIGHT, MASK_MARGIN)
  const weBuildMask = renderLayerToMask(weBuildImg, MASK_WIDTH, MASK_HEIGHT, MASK_MARGIN)

  const dilationRadius = thicknessToRadius(weBuildThickness, gridCellSize)
  const dilatedWeBuild = dilateMask(weBuildMask, MASK_WIDTH, MASK_HEIGHT, dilationRadius)

  const rgbaData = combineMasks(digitalMask, dilatedWeBuild, MASK_WIDTH, MASK_HEIGHT)

  // Flip Y for WebGL
  const flippedData = new Uint8Array(rgbaData.length)
  for (let y = 0; y < MASK_HEIGHT; y++) {
    const srcRow = y * MASK_WIDTH * 4
    const dstRow = (MASK_HEIGHT - 1 - y) * MASK_WIDTH * 4
    flippedData.set(rgbaData.subarray(srcRow, srcRow + MASK_WIDTH * 4), dstRow)
  }

  const texture = new THREE.DataTexture(
    flippedData,
    MASK_WIDTH,
    MASK_HEIGHT,
    THREE.RGBAFormat,
    THREE.UnsignedByteType
  )

  texture.minFilter = THREE.NearestFilter
  texture.magFilter = THREE.NearestFilter
  texture.generateMipmaps = false
  texture.wrapS = THREE.ClampToEdgeWrapping
  texture.wrapT = THREE.ClampToEdgeWrapping
  texture.flipY = false
  texture.needsUpdate = true

  return texture
}

export async function fetchSvgText(url: string): Promise<string> {
  const response = await fetch(url)
  return response.text()
}
