/**
 * CPU-side morphological dilation for binary masks.
 * Pre-computes dilation once when thickness changes, avoiding 20+ texture lookups in shader.
 */

/**
 * Pre-compute circular structuring element offsets for a given radius.
 */
export function createCircularKernel(radius: number): Array<[number, number]> {
  const offsets: Array<[number, number]> = []
  const r = Math.ceil(radius)
  const r2 = radius * radius

  for (let dy = -r; dy <= r; dy++) {
    for (let dx = -r; dx <= r; dx++) {
      if (dx * dx + dy * dy <= r2) {
        offsets.push([dx, dy])
      }
    }
  }

  return offsets
}

/**
 * Dilate a binary mask using a circular structuring element.
 */
export function dilateMask(
  mask: Uint8Array,
  width: number,
  height: number,
  radius: number
): Uint8Array {
  if (radius <= 0) {
    return new Uint8Array(mask)
  }

  const kernel = createCircularKernel(radius)
  const output = new Uint8Array(width * height)

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const outIdx = y * width + x

      for (const [dx, dy] of kernel) {
        const nx = x + dx
        const ny = y + dy

        if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
          const inIdx = ny * width + nx
          if (mask[inIdx] > 127) {
            output[outIdx] = 255
            break
          }
        }
      }
    }
  }

  return output
}

/**
 * Convert normalized thickness (0-1.2) to pixel radius.
 */
export function thicknessToRadius(thickness: number, gridCellSize: number): number {
  const normalized = Math.max(0, Math.min(thickness / 1.2, 1))
  const gridRadius = Math.pow(normalized, 0.85) * 2.5
  return gridRadius * gridCellSize
}

/**
 * Combine two binary masks into RGBA data.
 */
export function combineMasks(
  maskA: Uint8Array,
  maskB: Uint8Array,
  width: number,
  height: number
): Uint8Array {
  const pixelCount = width * height
  const rgba = new Uint8Array(pixelCount * 4)

  for (let i = 0; i < pixelCount; i++) {
    rgba[i * 4] = maskA[i]
    rgba[i * 4 + 1] = maskB[i]
    rgba[i * 4 + 2] = 0
    rgba[i * 4 + 3] = 255
  }

  return rgba
}
