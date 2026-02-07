import { CHARACTER_FAMILIES } from './constants'
import { getRandomFromFamily, getCharFamily } from './characters'

// Markov transition probabilities between families
// Higher probability = more likely to transition to that family
const TRANSITION_MATRIX: Record<string, Record<string, number>> = {
  void: {
    void: 0.7,
    sparse: 0.25,
    dots: 0.05,
    circles: 0,
    geometric: 0,
    lines: 0,
    special: 0,
    mystic: 0,
  },
  sparse: {
    void: 0.2,
    sparse: 0.5,
    dots: 0.25,
    circles: 0.05,
    geometric: 0,
    lines: 0,
    special: 0,
    mystic: 0,
  },
  dots: {
    void: 0.05,
    sparse: 0.2,
    dots: 0.45,
    circles: 0.25,
    geometric: 0.05,
    lines: 0,
    special: 0,
    mystic: 0,
  },
  circles: {
    void: 0,
    sparse: 0.05,
    dots: 0.2,
    circles: 0.45,
    geometric: 0.2,
    lines: 0.05,
    special: 0.04,
    mystic: 0.01,
  },
  geometric: {
    void: 0,
    sparse: 0,
    dots: 0.1,
    circles: 0.2,
    geometric: 0.45,
    lines: 0.15,
    special: 0.08,
    mystic: 0.02,
  },
  lines: {
    void: 0,
    sparse: 0.05,
    dots: 0.1,
    circles: 0.1,
    geometric: 0.2,
    lines: 0.45,
    special: 0.08,
    mystic: 0.02,
  },
  special: {
    void: 0,
    sparse: 0,
    dots: 0.05,
    circles: 0.15,
    geometric: 0.2,
    lines: 0.1,
    special: 0.35,
    mystic: 0.15,
  },
  mystic: {
    void: 0,
    sparse: 0,
    dots: 0,
    circles: 0.1,
    geometric: 0.15,
    lines: 0.05,
    special: 0.2,
    mystic: 0.5,
  },
}

// Get next family based on Markov transition
export function getNextFamily(currentFamily: string): string {
  const transitions = TRANSITION_MATRIX[currentFamily]
  if (!transitions) return currentFamily

  const rand = Math.random()
  let cumulative = 0

  for (const [family, probability] of Object.entries(transitions)) {
    cumulative += probability
    if (rand <= cumulative) {
      return family
    }
  }

  return currentFamily
}

// Get next character using Markov chain
export function getNextChar(currentChar: string): string {
  const currentFamily = getCharFamily(currentChar)
  const nextFamily = getNextFamily(currentFamily)
  return getRandomFromFamily(nextFamily)
}

// Energy-biased Markov transition
// Higher energy biases toward more complex families
export function getNextCharWithEnergy(currentChar: string, energy: number): string {
  const currentFamily = getCharFamily(currentChar)
  const transitions = TRANSITION_MATRIX[currentFamily]
  if (!transitions) return currentChar

  // Bias transitions based on energy
  const biasedTransitions: Record<string, number> = {}
  let total = 0

  const familyComplexity: Record<string, number> = {
    void: 0,
    sparse: 1,
    dots: 2,
    circles: 3,
    geometric: 4,
    lines: 5,
    special: 6,
    mystic: 7,
  }

  const targetComplexity = energy * 7

  for (const [family, probability] of Object.entries(transitions)) {
    const complexity = familyComplexity[family] ?? 0
    const distance = Math.abs(complexity - targetComplexity)
    const bias = Math.exp(-distance * 0.5) // Gaussian-like bias
    biasedTransitions[family] = probability * bias
    total += biasedTransitions[family]
  }

  // Normalize
  for (const family of Object.keys(biasedTransitions)) {
    biasedTransitions[family] /= total
  }

  // Sample
  const rand = Math.random()
  let cumulative = 0

  for (const [family, probability] of Object.entries(biasedTransitions)) {
    cumulative += probability
    if (rand <= cumulative) {
      return getRandomFromFamily(family)
    }
  }

  return currentChar
}

// Batch update for sparse CPU-based updates
export class MarkovGrid {
  private grid: string[][]
  private width: number
  private height: number

  constructor(width: number, height: number) {
    this.width = width
    this.height = height
    this.grid = []

    // Initialize with void
    for (let y = 0; y < height; y++) {
      this.grid[y] = []
      for (let x = 0; x < width; x++) {
        this.grid[y][x] = ' '
      }
    }
  }

  get(x: number, y: number): string {
    if (x < 0 || x >= this.width || y < 0 || y >= this.height) return ' '
    return this.grid[y][x]
  }

  set(x: number, y: number, char: string): void {
    if (x >= 0 && x < this.width && y >= 0 && y < this.height) {
      this.grid[y][x] = char
    }
  }

  // Update a single cell using Markov transition
  updateCell(x: number, y: number, energy: number): void {
    const current = this.get(x, y)
    const next = getNextCharWithEnergy(current, energy)
    this.set(x, y, next)
  }

  // Get flat array for shader uniform
  toIndices(): number[] {
    const indices: number[] = []
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        const char = this.grid[y][x]
        const family = CHARACTER_FAMILIES.find(f => f.chars.includes(char))
        if (family) {
          const familyIndex = CHARACTER_FAMILIES.indexOf(family)
          const charIndex = family.chars.indexOf(char)
          indices.push(familyIndex * 10 + charIndex) // Encoded index
        } else {
          indices.push(0)
        }
      }
    }
    return indices
  }
}
