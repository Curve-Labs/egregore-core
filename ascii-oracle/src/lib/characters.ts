import { CHARACTER_FAMILIES, ALL_CHARACTERS } from './constants'

// Character to index mapping for shader
export const charToIndex = new Map<string, number>()
ALL_CHARACTERS.forEach((char, index) => {
  charToIndex.set(char, index)
})

// Get character index, with fallback to space
export function getCharIndex(char: string): number {
  return charToIndex.get(char) ?? 0
}

// Get character by index
export function getCharByIndex(index: number): string {
  return ALL_CHARACTERS[Math.min(index, ALL_CHARACTERS.length - 1)] ?? ' '
}

// Get family index for a character
export function getCharFamily(char: string): string {
  for (const family of CHARACTER_FAMILIES) {
    if (family.chars.includes(char)) {
      return family.name
    }
  }
  return 'void'
}

// Get a random character from a family
export function getRandomFromFamily(familyName: string): string {
  const family = CHARACTER_FAMILIES.find(f => f.name === familyName)
  if (!family) return ' '
  return family.chars[Math.floor(Math.random() * family.chars.length)]
}

// Map energy level (0-1) to appropriate character family
export function energyToFamily(energy: number): string {
  if (energy < 0.1) return 'void'
  if (energy < 0.25) return 'sparse'
  if (energy < 0.4) return 'dots'
  if (energy < 0.55) return 'circles'
  if (energy < 0.7) return 'geometric'
  if (energy < 0.85) return 'lines'
  if (energy < 0.95) return 'special'
  return 'mystic'
}

// Map energy to character index (for shader)
export function energyToCharIndex(energy: number): number {
  const family = energyToFamily(energy)
  const familyObj = CHARACTER_FAMILIES.find(f => f.name === family)
  if (!familyObj) return 0

  // Find start index of this family in ALL_CHARACTERS
  let startIndex = 0
  for (const f of CHARACTER_FAMILIES) {
    if (f.name === family) break
    startIndex += f.chars.length
  }

  // Pick character within family based on sub-energy
  const familyProgress = (energy % 0.15) / 0.15 // Normalize within family range
  const charOffset = Math.floor(familyProgress * familyObj.chars.length)

  return startIndex + charOffset
}

// For text reveals - get indices for a string
export function stringToIndices(text: string): number[] {
  return Array.from(text).map(char => {
    const index = charToIndex.get(char)
    if (index !== undefined) return index
    // For text characters not in our set, use dots
    return charToIndex.get('•') ?? 4
  })
}

// Character set info for shader uniforms
export const CHAR_SET_INFO = {
  totalChars: ALL_CHARACTERS.length,
  familyCount: CHARACTER_FAMILIES.length,
  families: CHARACTER_FAMILIES.map(f => ({
    name: f.name,
    startIndex: ALL_CHARACTERS.indexOf(f.chars[0]),
    count: f.chars.length,
  })),
}
