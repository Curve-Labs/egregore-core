import type { Zone, CharacterFamily } from '../types'

// Color palette
export const COLORS = {
  background: '#0a0a0f',
  void: '#1a1a2e',
  dim: '#3a3a5e',
  mid: '#6a6a8e',
  bright: '#9a9abe',
  highlight: '#cacaee',
  accent: '#7c3aed',
  glow: '#a78bfa',
} as const

// Zone definitions (radial from center, normalized 0-1)
export const ZONES: Zone[] = [
  {
    name: 'core',
    minRadius: 0,
    maxRadius: 0.15,
    baseEnergy: 0.9,
    characterBias: ['geometric', 'circles'],
  },
  {
    name: 'inner',
    minRadius: 0.15,
    maxRadius: 0.35,
    baseEnergy: 0.7,
    characterBias: ['circles', 'dots'],
  },
  {
    name: 'middle',
    minRadius: 0.35,
    maxRadius: 0.55,
    baseEnergy: 0.5,
    characterBias: ['dots', 'lines'],
  },
  {
    name: 'outer',
    minRadius: 0.55,
    maxRadius: 0.75,
    baseEnergy: 0.3,
    characterBias: ['lines', 'sparse'],
  },
  {
    name: 'edge',
    minRadius: 0.75,
    maxRadius: 1.0,
    baseEnergy: 0.1,
    characterBias: ['sparse', 'void'],
  },
]

// Character families for Markov transitions
export const CHARACTER_FAMILIES: CharacterFamily[] = [
  {
    name: 'void',
    chars: [' ', ' ', ' ', ' '],
    weight: 0.1,
  },
  {
    name: 'sparse',
    chars: ['.', '·', ':', '∙'],
    weight: 0.15,
  },
  {
    name: 'dots',
    chars: ['•', '◦', '○', '●', '◎', '◉'],
    weight: 0.2,
  },
  {
    name: 'circles',
    chars: ['◯', '⊙', '⊚', '⊛', '◐', '◑', '◒', '◓'],
    weight: 0.2,
  },
  {
    name: 'geometric',
    chars: ['△', '▽', '◇', '◆', '□', '■', '▢', '▣', '⬡', '⬢'],
    weight: 0.15,
  },
  {
    name: 'lines',
    chars: ['│', '─', '┼', '╱', '╲', '╳', '┃', '━'],
    weight: 0.1,
  },
  {
    name: 'special',
    chars: ['✦', '✧', '★', '☆', '✶', '✹', '❋', '❊'],
    weight: 0.05,
  },
  {
    name: 'mystic',
    chars: ['☉', '☽', '☾', '✡', '⚝', '⚛', '⚜', '☀'],
    weight: 0.05,
  },
]

// All characters flattened for shader indexing
export const ALL_CHARACTERS = CHARACTER_FAMILIES.flatMap(f => f.chars)

// Performance presets
export const PERFORMANCE_PRESETS = {
  minimal: {
    gridDensity: 0.5,
    postProcessing: false,
    pulseCount: 2,
    updateRate: 30,
  },
  balanced: {
    gridDensity: 0.75,
    postProcessing: true,
    pulseCount: 4,
    updateRate: 60,
  },
  intense: {
    gridDensity: 1.0,
    postProcessing: true,
    pulseCount: 8,
    updateRate: 60,
  },
} as const

// Animation timing
export const TIMING = {
  pulseOrbitSpeed: 0.0003,
  pulseOrbitRadius: 0.3,
  transitionDuration: 0.5,
  revealSpeed: 0.02,
  rippleSpeed: 0.5,
  rippleDecay: 0.95,
} as const

// Grid sizing
export const GRID = {
  baseCellSize: 16,
  minCols: 40,
  maxCols: 120,
  minRows: 25,
  maxRows: 60,
} as const
