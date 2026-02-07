import { create } from 'zustand'
import { Vector2 } from 'three'
import type { OracleStore, Pulse } from '../types'
import { TIMING } from '../lib/constants'

let pulseIdCounter = 0

export const useOracleStore = create<OracleStore>((set) => ({
  // Interaction mode
  mode: 'ambient',
  setMode: (mode) => set({ mode }),

  // Oracle state
  oracleState: 'idle',
  setOracleState: (oracleState) => set({ oracleState }),

  // Question/Answer
  question: '',
  setQuestion: (question) => set({ question }),
  answer: '',
  setAnswer: (answer) => set({ answer }),
  revealProgress: 0,
  setRevealProgress: (revealProgress) => set({ revealProgress }),

  // Pulses
  pulses: [],
  addPulse: (pulseData) => {
    const id = `pulse-${++pulseIdCounter}`
    const pulse: Pulse = {
      ...pulseData,
      id,
      createdAt: Date.now(),
    }
    set((state) => ({ pulses: [...state.pulses, pulse] }))
  },
  updatePulses: (delta) => {
    set((state) => {
      const updatedPulses = state.pulses
        .map((pulse) => ({
          ...pulse,
          radius: pulse.radius + pulse.speed * delta,
          intensity: pulse.intensity * Math.pow(pulse.decay, delta * 60),
        }))
        .filter((pulse) => pulse.intensity > 0.01)
      return { pulses: updatedPulses }
    })
  },
  clearPulses: () => set({ pulses: [] }),

  // Mouse/Touch interaction
  pointerPosition: null,
  setPointerPosition: (pointerPosition) => set({ pointerPosition }),
  pointerDown: false,
  setPointerDown: (pointerDown) => set({ pointerDown }),

  // Performance
  performancePreset: 'balanced',
  setPerformancePreset: (performancePreset) => set({ performancePreset }),
  reducedMotion: false,
  setReducedMotion: (reducedMotion) => set({ reducedMotion }),

  // Time
  time: 0,
  updateTime: (delta) => set((state) => ({ time: state.time + delta })),
}))

// Selector hooks for performance
export const useMode = () => useOracleStore((s) => s.mode)
export const useOracleState = () => useOracleStore((s) => s.oracleState)
export const usePulses = () => useOracleStore((s) => s.pulses)
export const useTime = () => useOracleStore((s) => s.time)
export const usePointerPosition = () => useOracleStore((s) => s.pointerPosition)
export const usePerformancePreset = () => useOracleStore((s) => s.performancePreset)
export const useReducedMotion = () => useOracleStore((s) => s.reducedMotion)

// Helper to create orbiting pulses
export function createOrbitingPulse(time: number, index: number = 0): Omit<Pulse, 'id' | 'createdAt'> {
  const angle = time * TIMING.pulseOrbitSpeed + (index * Math.PI * 2) / 4
  const x = Math.cos(angle) * TIMING.pulseOrbitRadius
  const y = Math.sin(angle) * TIMING.pulseOrbitRadius

  return {
    position: new Vector2(x, y),
    radius: 0,
    intensity: 1,
    speed: TIMING.rippleSpeed,
    decay: TIMING.rippleDecay,
  }
}

// Helper to create interaction pulse
export function createInteractionPulse(x: number, y: number): Omit<Pulse, 'id' | 'createdAt'> {
  return {
    position: new Vector2(x, y),
    radius: 0,
    intensity: 0.8,
    speed: TIMING.rippleSpeed * 1.5,
    decay: TIMING.rippleDecay * 0.98,
  }
}
