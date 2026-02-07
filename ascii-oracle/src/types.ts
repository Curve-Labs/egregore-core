import type { Vector2 } from 'three'

export type InteractionMode = 'ambient' | 'oracle' | 'interactive'

export type OracleState = 'idle' | 'thinking' | 'revealing' | 'complete'

export interface Pulse {
  id: string
  position: Vector2
  radius: number
  intensity: number
  speed: number
  decay: number
  createdAt: number
}

export interface CharacterFamily {
  name: string
  chars: string[]
  weight: number
}

export interface MarkovTransition {
  from: string
  to: string
  probability: number
}

export interface Zone {
  name: string
  minRadius: number
  maxRadius: number
  baseEnergy: number
  characterBias: string[]
}

export interface OracleStore {
  // Interaction mode
  mode: InteractionMode
  setMode: (mode: InteractionMode) => void

  // Oracle state
  oracleState: OracleState
  setOracleState: (state: OracleState) => void

  // Question/Answer
  question: string
  setQuestion: (q: string) => void
  answer: string
  setAnswer: (a: string) => void
  revealProgress: number
  setRevealProgress: (p: number) => void

  // Pulses
  pulses: Pulse[]
  addPulse: (pulse: Omit<Pulse, 'id' | 'createdAt'>) => void
  updatePulses: (delta: number) => void
  clearPulses: () => void

  // Mouse/Touch interaction
  pointerPosition: Vector2 | null
  setPointerPosition: (pos: Vector2 | null) => void
  pointerDown: boolean
  setPointerDown: (down: boolean) => void

  // Performance
  performancePreset: 'minimal' | 'balanced' | 'intense'
  setPerformancePreset: (preset: 'minimal' | 'balanced' | 'intense') => void
  reducedMotion: boolean
  setReducedMotion: (reduced: boolean) => void

  // Time
  time: number
  updateTime: (delta: number) => void
}

export interface GridConfig {
  cols: number
  rows: number
  cellWidth: number
  cellHeight: number
}
