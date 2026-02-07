import * as THREE from 'three'

// ASCII characters ordered by visual density (light to dark)
const ASCII_CHARS = ' .·:;+*oO0@#'

// Create a texture atlas with ASCII characters
export function createCharacterAtlas(): THREE.CanvasTexture {
  const charSize = 64  // Size of each character cell
  const cols = ASCII_CHARS.length
  const canvas = document.createElement('canvas')
  canvas.width = charSize * cols
  canvas.height = charSize
  const ctx = canvas.getContext('2d')!

  // Black background
  ctx.fillStyle = 'black'
  ctx.fillRect(0, 0, canvas.width, canvas.height)

  // Draw each character
  ctx.fillStyle = 'white'
  ctx.font = `bold ${charSize * 0.8}px "Courier New", Courier, monospace`
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'

  for (let i = 0; i < ASCII_CHARS.length; i++) {
    const char = ASCII_CHARS[i]
    const x = i * charSize + charSize / 2
    const y = charSize / 2
    ctx.fillText(char, x, y)
  }

  const texture = new THREE.CanvasTexture(canvas)
  texture.minFilter = THREE.LinearFilter
  texture.magFilter = THREE.LinearFilter
  texture.needsUpdate = true

  return texture
}

// Load SVG as texture for masking
export function loadSvgAsTexture(svgPath: string): Promise<THREE.CanvasTexture> {
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => {
      const canvas = document.createElement('canvas')
      canvas.width = 1024
      canvas.height = 512
      const ctx = canvas.getContext('2d')!

      // Black background
      ctx.fillStyle = 'black'
      ctx.fillRect(0, 0, canvas.width, canvas.height)

      // Draw SVG centered with margins
      const margin = 0.08
      const contentW = canvas.width * (1 - 2 * margin)
      const contentH = canvas.height * (1 - 2 * margin)
      const offsetX = canvas.width * margin
      const offsetY = canvas.height * margin

      const svgAspect = img.width / img.height
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

      ctx.drawImage(img, drawX, drawY, drawW, drawH)

      // Process to separate channels
      const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
      const data = imageData.data

      for (let i = 0; i < data.length; i += 4) {
        const brightness = (data[i] + data[i + 1] + data[i + 2]) / 3

        if (brightness > 200) {
          // Bright = Digital Souls (red channel)
          data[i] = 255
          data[i + 1] = 0
          data[i + 2] = 0
        } else if (brightness > 40) {
          // Dim = We Build (green channel)
          data[i] = 0
          data[i + 1] = 255
          data[i + 2] = 0
        } else {
          data[i] = 0
          data[i + 1] = 0
          data[i + 2] = 0
        }
        data[i + 3] = 255
      }

      ctx.putImageData(imageData, 0, 0)

      const texture = new THREE.CanvasTexture(canvas)
      texture.minFilter = THREE.LinearFilter
      texture.magFilter = THREE.LinearFilter
      texture.needsUpdate = true

      resolve(texture)
    }
    img.src = svgPath
  })
}
