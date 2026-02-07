import { useRef, useMemo, useEffect, useCallback, useState } from 'react'
import { Canvas, useFrame, useThree } from '@react-three/fiber'
import * as THREE from 'three'
import { EffectComposer, Bloom, Vignette } from '@react-three/postprocessing'
import { BlendFunction, KernelSize } from 'postprocessing'

import { useOracleStore } from '../hooks/useOracleState'
import { useInteraction } from '../hooks/useInteraction'
import { useGridSize } from '../hooks/useGridSize'
import { COLORS, PERFORMANCE_PRESETS } from '../lib/constants'
import { ControlSliders } from './DensitySlider'
import { InputOverlay } from './InputOverlay'
import { ModeIndicator } from './ModeIndicator'
import digitalSoulsSvg from '../assets/digital-souls.svg'

// ASCII characters by density (sparse to dense)
const ASCII_CHARS = ' .·:+*oO0@'
const NUM_CHARS = ASCII_CHARS.length
const TEXT_CHAR = '0'
const TEXT_CHAR_INDEX = Math.max(0, ASCII_CHARS.indexOf(TEXT_CHAR))

const vertexShader = `
void main() {
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`

const fragmentShader = `
precision highp float;

uniform float uTime;
uniform vec2 uResolution;
uniform vec2 uGridSize;
uniform float uDensity;
uniform float uKnockoutThickness;
uniform float uMonochrome;
uniform sampler2D uCharAtlas;
uniform sampler2D uMaskTexture;
uniform vec3 uColorDim;
uniform vec3 uColorMid;
uniform vec3 uColorBright;
uniform vec3 uColorAccent;

// Simple hash for randomness
float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Simplex noise (simplified)
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
  vec2 uv = (floor(gl_FragCoord.xy) + 0.5) / uResolution;

  // Grid cell coordinates
  vec2 cellCoord = floor(uv * uGridSize);
  vec2 localUv = fract(uv * uGridSize);

  // Sample mask texture per cell (stable character decisions)
  vec2 cellUv = (cellCoord + 0.5) / uGridSize;
  vec4 mask = texture2D(uMaskTexture, cellUv);
  float boostValue = mask.r;    // Digital Souls
  float knockoutValue = mask.g; // We Build

  // Thicken "We Build" with smooth, gradual dilation
  vec2 stepUv = 1.0 / uGridSize;
  float r = clamp(uKnockoutThickness, 0.0, 1.2);
  r = pow(r / 1.2, 0.85) * 2.5;

  float w1 = smoothstep(0.35, 1.0, r);   // distance 1.0
  float wD = smoothstep(0.8, 1.5, r);    // distance 1.414
  float w2 = smoothstep(1.4, 2.1, r);    // distance 2.0
  float wK = smoothstep(1.8, 2.5, r);    // distance 2.236

  float k = knockoutValue;
  vec2 s1 = stepUv;
  vec2 s2 = stepUv * 2.0;

  // 4-neighbors (distance 1)
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s1.x, 0.0)).g * w1);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s1.x, 0.0)).g * w1);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(0.0, s1.y)).g * w1);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(0.0, -s1.y)).g * w1);

  // Diagonals (distance sqrt(2))
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s1.x, s1.y)).g * wD);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s1.x, s1.y)).g * wD);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s1.x, -s1.y)).g * wD);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s1.x, -s1.y)).g * wD);

  // 2-step axis (distance 2)
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s2.x, 0.0)).g * w2);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s2.x, 0.0)).g * w2);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(0.0, s2.y)).g * w2);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(0.0, -s2.y)).g * w2);

  // Knight offsets (distance sqrt(5))
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s2.x, s1.y)).g * wK);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s2.x, -s1.y)).g * wK);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s2.x, s1.y)).g * wK);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s2.x, -s1.y)).g * wK);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s1.x, s2.y)).g * wK);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s1.x, s2.y)).g * wK);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(s1.x, -s2.y)).g * wK);
  k = max(k, texture2D(uMaskTexture, cellUv + vec2(-s1.x, -s2.y)).g * wK);

  knockoutValue = k;

  bool isTextArea = boostValue > 0.5;

  // KNOCKOUT: "We Build" = complete black
  if (knockoutValue > 0.3) {
    gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  // Calculate base energy from position
  vec2 pos = uv - 0.5;
  float aspect = uResolution.x / uResolution.y;
  pos.x *= aspect;
  float radius = length(pos) * 2.0;

  // Zone-based energy (center = high, edges = low)
  float zoneEnergy = 1.0 - smoothstep(0.0, 1.0, radius);
  zoneEnergy = pow(zoneEnergy, 0.5) * 0.8;

  // Add noise variation (static, so flips feel discrete)
  float n = noise(cellCoord * 0.3) * 0.3;

  // Combine energies
  float baseEnergy = zoneEnergy * uDensity + n * zoneEnergy;
  float energy = baseEnergy;

  // Boost energy for Digital Souls text
  energy += boostValue * 0.8;
  if (isTextArea) {
    energy = 0.9;
  }
  energy = clamp(energy, 0.0, 1.0);

  // Random character selection per cell (discrete flip steps)
  float cellRandom = hash(cellCoord);
  float flipStep = floor(uTime * 0.6 + cellRandom * 8.0);
  float charRandom = hash(cellCoord + flipStep);

  // Character index based on energy
  float charIndex;
  if (isTextArea) {
    charIndex = float(${TEXT_CHAR_INDEX});
  } else {
    float baseIndex = floor(energy * float(${NUM_CHARS - 1}));
    float jitter = floor(charRandom * 3.0) - 1.0;
    charIndex = clamp(baseIndex + jitter, 0.0, float(${NUM_CHARS - 1}));
  }

  // Skip rendering if energy too low (void)
  if (!isTextArea && energy < 0.08) {
    gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  // Sample character from atlas
  float charWidth = 1.0 / float(${NUM_CHARS});
  vec2 atlasUv = vec2(
    charIndex * charWidth + localUv.x * charWidth,
    localUv.y
  );
  float charValue = texture2D(uCharAtlas, atlasUv).r;
  charValue = step(0.5, charValue);

  // Color based on energy
  vec3 color;
  if (energy < 0.3) {
    color = mix(uColorDim, uColorMid, energy / 0.3);
  } else if (energy < 0.6) {
    color = mix(uColorMid, uColorBright, (energy - 0.3) / 0.3);
  } else {
    color = mix(uColorBright, uColorAccent, (energy - 0.6) / 0.4);
  }

  // Invert text color where it collides with the "spirit" field
  if (isTextArea) {
    float spirit = smoothstep(0.25, 0.75, baseEnergy);
    vec3 inverted = vec3(1.0) - color;
    color = mix(color, inverted, spirit);
  }

  if (uMonochrome > 0.5) {
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = vec3(luma);
  }

  // Final output
  vec3 outColor = color * charValue;
  gl_FragColor = vec4(outColor, 1.0);
}
`

// Create character atlas texture
function createCharAtlas(): THREE.CanvasTexture {
  const charSize = 96
  const canvas = document.createElement('canvas')
  canvas.width = charSize * NUM_CHARS
  canvas.height = charSize
  const ctx = canvas.getContext('2d')!

  ctx.fillStyle = 'black'
  ctx.fillRect(0, 0, canvas.width, canvas.height)

  ctx.fillStyle = 'white'
  ctx.font = `bold ${charSize * 0.85}px "Courier New", Courier, monospace`
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'

  for (let i = 0; i < NUM_CHARS; i++) {
    const char = ASCII_CHARS[i]
    ctx.fillText(char, i * charSize + charSize / 2, charSize / 2)
  }

  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
  const data = imageData.data
  for (let i = 0; i < data.length; i += 4) {
    const on = data[i] > 40
    data[i] = on ? 255 : 0
    data[i + 1] = on ? 255 : 0
    data[i + 2] = on ? 255 : 0
    data[i + 3] = 255
  }
  ctx.putImageData(imageData, 0, 0)

  const texture = new THREE.CanvasTexture(canvas)
  texture.minFilter = THREE.NearestFilter
  texture.magFilter = THREE.NearestFilter
  texture.generateMipmaps = false
  texture.wrapS = THREE.ClampToEdgeWrapping
  texture.wrapT = THREE.ClampToEdgeWrapping
  return texture
}

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

function getDrawParams(img: HTMLImageElement, width: number, height: number, margin: number) {
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

// Create mask texture from SVG (separate layers, no brightness heuristics)
async function createMaskTexture(svgUrl: string): Promise<THREE.CanvasTexture> {
  const svgText = await fetch(svgUrl).then((res) => res.text())

  const [digitalImg, weBuildImg] = await Promise.all([
    loadSvgImage(injectLayerOverrides(svgText, 'cls-1')),
    loadSvgImage(injectLayerOverrides(svgText, 'cls-2')),
  ])

  const width = 1024
  const height = 512
  const margin = 0.06

  const digitalCanvas = document.createElement('canvas')
  digitalCanvas.width = width
  digitalCanvas.height = height
  const digitalCtx = digitalCanvas.getContext('2d')!

  const weBuildCanvas = document.createElement('canvas')
  weBuildCanvas.width = width
  weBuildCanvas.height = height
  const weBuildCtx = weBuildCanvas.getContext('2d')!

  const { drawW, drawH, drawX, drawY } = getDrawParams(digitalImg, width, height, margin)

  digitalCtx.fillStyle = 'black'
  digitalCtx.fillRect(0, 0, width, height)
  digitalCtx.drawImage(digitalImg, drawX, drawY, drawW, drawH)

  weBuildCtx.fillStyle = 'black'
  weBuildCtx.fillRect(0, 0, width, height)
  weBuildCtx.drawImage(weBuildImg, drawX, drawY, drawW, drawH)

  const digitalData = digitalCtx.getImageData(0, 0, width, height).data
  const weBuildData = weBuildCtx.getImageData(0, 0, width, height).data

  const outCanvas = document.createElement('canvas')
  outCanvas.width = width
  outCanvas.height = height
  const outCtx = outCanvas.getContext('2d')!
  const outImage = outCtx.createImageData(width, height)
  const outData = outImage.data

  for (let i = 0; i < outData.length; i += 4) {
    const digitalBright = digitalData[i] > 10
    const weBuildBright = weBuildData[i] > 10

    outData[i] = digitalBright ? 255 : 0
    outData[i + 1] = weBuildBright ? 255 : 0
    outData[i + 2] = 0
    outData[i + 3] = 255
  }

  outCtx.putImageData(outImage, 0, 0)

  const texture = new THREE.CanvasTexture(outCanvas)
  texture.minFilter = THREE.NearestFilter
  texture.magFilter = THREE.NearestFilter
  texture.generateMipmaps = false
  texture.wrapS = THREE.ClampToEdgeWrapping
  texture.wrapT = THREE.ClampToEdgeWrapping
  texture.flipY = true
  texture.needsUpdate = true
  return texture
}

function AsciiScene({ gridCols, gridRows, density, knockoutThickness, monochrome }: { gridCols: number; gridRows: number; density: number; knockoutThickness: number; monochrome: boolean }) {
  const { size } = useThree()
  const meshRef = useRef<THREE.Mesh>(null)
  const materialRef = useRef<THREE.ShaderMaterial>(null)
  const timeRef = useRef(0)

  const reducedMotion = useOracleStore((s) => s.reducedMotion)

  // Create textures
  const [charAtlas] = useState(() => createCharAtlas())
  const [maskTexture, setMaskTexture] = useState<THREE.CanvasTexture | null>(null)

  useEffect(() => {
    createMaskTexture(digitalSoulsSvg).then(setMaskTexture).catch(console.error)
  }, [])

  const geometry = useMemo(() => {
    const geo = new THREE.BufferGeometry()
    const vertices = new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0])
    geo.setAttribute('position', new THREE.BufferAttribute(vertices, 3))
    return geo
  }, [])

  const material = useMemo(() => {
    return new THREE.ShaderMaterial({
      vertexShader,
      fragmentShader,
      uniforms: {
        uTime: { value: 0 },
        uResolution: { value: new THREE.Vector2(size.width, size.height) },
        uGridSize: { value: new THREE.Vector2(gridCols, gridRows) },
        uDensity: { value: density },
        uKnockoutThickness: { value: knockoutThickness },
        uMonochrome: { value: monochrome ? 1.0 : 0.0 },
        uCharAtlas: { value: charAtlas },
        uMaskTexture: { value: maskTexture || new THREE.Texture() },
        uColorDim: { value: new THREE.Color(COLORS.dim) },
        uColorMid: { value: new THREE.Color(COLORS.mid) },
        uColorBright: { value: new THREE.Color(COLORS.bright) },
        uColorAccent: { value: new THREE.Color(COLORS.accent) },
      },
      transparent: false,
      depthTest: false,
      depthWrite: false,
    })
  }, [size.width, size.height, gridCols, gridRows, charAtlas, maskTexture])

  useFrame((_, delta) => {
    if (reducedMotion) delta *= 0.2
    timeRef.current += delta

    if (materialRef.current) {
      materialRef.current.uniforms.uTime.value = timeRef.current
      materialRef.current.uniforms.uResolution.value.set(size.width, size.height)
      materialRef.current.uniforms.uGridSize.value.set(gridCols, gridRows)
      materialRef.current.uniforms.uDensity.value = density
      materialRef.current.uniforms.uKnockoutThickness.value = knockoutThickness
      materialRef.current.uniforms.uMonochrome.value = monochrome ? 1.0 : 0.0
    }
  })

  useEffect(() => {
    if (materialRef.current && maskTexture) {
      materialRef.current.uniforms.uMaskTexture.value = maskTexture
    }
  }, [maskTexture])

  return (
    <mesh ref={meshRef} frustumCulled={false}>
      <primitive object={geometry} attach="geometry" />
      <primitive object={material} attach="material" ref={materialRef} />
    </mesh>
  )
}

function PostProcessing() {
  const performancePreset = useOracleStore((s) => s.performancePreset)
  const preset = PERFORMANCE_PRESETS[performancePreset]
  if (!preset.postProcessing) return null

  return (
    <EffectComposer>
      <Bloom intensity={0.3} luminanceThreshold={0.6} luminanceSmoothing={0.2} kernelSize={KernelSize.MEDIUM} blendFunction={BlendFunction.ADD} />
      <Vignette offset={0.3} darkness={0.5} blendFunction={BlendFunction.NORMAL} />
    </EffectComposer>
  )
}

export function AsciiOracle({ showModeSelector = true, showDensitySlider = true, onOracleQuery }: { showModeSelector?: boolean; showDensitySlider?: boolean; onOracleQuery?: (q: string) => Promise<string> }) {
  const containerRef = useRef<HTMLDivElement>(null)
  const setOracleState = useOracleStore((s) => s.setOracleState)
  const setAnswer = useOracleStore((s) => s.setAnswer)
  const setRevealProgress = useOracleStore((s) => s.setRevealProgress)
  const { cols: baseGridCols, rows: baseGridRows } = useGridSize()
  const [density, setDensity] = useState(0.7)
  const [asciiSize, setAsciiSize] = useState(1.0)
  const [weBuildThickness, setWeBuildThickness] = useState(0.6)
  const [monochrome, setMonochrome] = useState(false)

  const gridCols = Math.floor(baseGridCols / asciiSize)
  const gridRows = Math.floor(baseGridRows / asciiSize)

  useInteraction({ containerRef, enabled: true })

  const handleOracleSubmit = useCallback(async (question: string) => {
    const answer = onOracleQuery
      ? await onOracleQuery(question).catch(() => 'The oracle is silent.')
      : `The oracle contemplates: "${question}"`

    setAnswer(answer)
    setOracleState('revealing')

    const duration = answer.length * 30
    const start = Date.now()
    const animate = () => {
      const progress = Math.min((Date.now() - start) / duration, 1)
      setRevealProgress(progress)
      if (progress < 1) requestAnimationFrame(animate)
      else setOracleState('complete')
    }
    setTimeout(animate, 500)
  }, [onOracleQuery, setAnswer, setOracleState, setRevealProgress])

  return (
    <div ref={containerRef} style={{ width: '100%', height: '100%', background: COLORS.background, position: 'relative' }}>
      <Canvas
        gl={{ antialias: false, alpha: false, powerPreference: 'high-performance' }}
        camera={{ position: [0, 0, 1] }}
        style={{ width: '100%', height: '100%' }}
      >
        <AsciiScene
          gridCols={gridCols}
          gridRows={gridRows}
          density={density}
          knockoutThickness={weBuildThickness}
          monochrome={monochrome}
        />
        <PostProcessing />
      </Canvas>
      <InputOverlay onSubmit={handleOracleSubmit} />
      <ModeIndicator showSelector={showModeSelector} />
      {showDensitySlider && (
        <ControlSliders
          density={density}
          onDensityChange={setDensity}
          size={asciiSize}
          onSizeChange={setAsciiSize}
          weBuildThickness={weBuildThickness}
          onWeBuildThicknessChange={setWeBuildThickness}
          monochrome={monochrome}
          onMonochromeToggle={() => setMonochrome((v) => !v)}
        />
      )}
    </div>
  )
}
