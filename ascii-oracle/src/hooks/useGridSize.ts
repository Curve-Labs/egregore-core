import { useState, useEffect, useMemo } from 'react'
import { GRID, PERFORMANCE_PRESETS } from '../lib/constants'
import { useOracleStore } from './useOracleState'

interface GridSize {
  cols: number
  rows: number
}

export function useGridSize(): GridSize {
  const performancePreset = useOracleStore((s) => s.performancePreset)
  const [windowSize, setWindowSize] = useState({
    width: typeof window !== 'undefined' ? window.innerWidth : 1920,
    height: typeof window !== 'undefined' ? window.innerHeight : 1080,
  })

  useEffect(() => {
    let timeoutId: ReturnType<typeof setTimeout>

    const handleResize = () => {
      // Debounce resize events
      clearTimeout(timeoutId)
      timeoutId = setTimeout(() => {
        setWindowSize({
          width: window.innerWidth,
          height: window.innerHeight,
        })
      }, 100)
    }

    window.addEventListener('resize', handleResize)
    return () => {
      window.removeEventListener('resize', handleResize)
      clearTimeout(timeoutId)
    }
  }, [])

  const gridSize = useMemo(() => {
    const preset = PERFORMANCE_PRESETS[performancePreset]

    const cols = Math.floor(
      Math.min(
        GRID.maxCols,
        Math.max(GRID.minCols, windowSize.width / GRID.baseCellSize)
      ) * preset.gridDensity
    )

    const rows = Math.floor(
      Math.min(
        GRID.maxRows,
        Math.max(GRID.minRows, windowSize.height / GRID.baseCellSize)
      ) * preset.gridDensity
    )

    return { cols, rows }
  }, [windowSize.width, windowSize.height, performancePreset])

  return gridSize
}
