import { useCallback, useEffect, useRef } from 'react'
import { Vector2 } from 'three'
import { useOracleStore, createInteractionPulse } from './useOracleState'

interface UseInteractionOptions {
  containerRef: React.RefObject<HTMLElement | null>
  enabled?: boolean
}

export function useInteraction({ containerRef, enabled = true }: UseInteractionOptions) {
  const setPointerPosition = useOracleStore((s) => s.setPointerPosition)
  const setPointerDown = useOracleStore((s) => s.setPointerDown)
  const addPulse = useOracleStore((s) => s.addPulse)
  const mode = useOracleStore((s) => s.mode)

  const lastTapTime = useRef(0)
  const isInteractive = mode === 'interactive' || mode === 'ambient'

  // Convert screen coordinates to normalized (-0.5 to 0.5) centered coordinates
  const screenToNormalized = useCallback(
    (clientX: number, clientY: number): Vector2 | null => {
      const container = containerRef.current
      if (!container) return null

      const rect = container.getBoundingClientRect()
      const x = ((clientX - rect.left) / rect.width - 0.5)
      const y = -((clientY - rect.top) / rect.height - 0.5) // Flip Y

      // Adjust for aspect ratio
      const aspect = rect.width / rect.height
      return new Vector2(x * aspect, y)
    },
    [containerRef]
  )

  // Mouse move handler
  const handleMouseMove = useCallback(
    (e: MouseEvent) => {
      if (!enabled || !isInteractive) return

      const pos = screenToNormalized(e.clientX, e.clientY)
      setPointerPosition(pos)
    },
    [enabled, isInteractive, screenToNormalized, setPointerPosition]
  )

  // Mouse down handler
  const handleMouseDown = useCallback(
    (e: MouseEvent) => {
      if (!enabled || !isInteractive) return

      setPointerDown(true)

      // Create pulse at click location
      const pos = screenToNormalized(e.clientX, e.clientY)
      if (pos) {
        addPulse(createInteractionPulse(pos.x, pos.y))
      }
    },
    [enabled, isInteractive, screenToNormalized, setPointerDown, addPulse]
  )

  // Mouse up handler
  const handleMouseUp = useCallback(() => {
    setPointerDown(false)
  }, [setPointerDown])

  // Mouse leave handler
  const handleMouseLeave = useCallback(() => {
    setPointerPosition(null)
    setPointerDown(false)
  }, [setPointerPosition, setPointerDown])

  // Touch move handler
  const handleTouchMove = useCallback(
    (e: TouchEvent) => {
      if (!enabled || !isInteractive) return

      const touch = e.touches[0]
      if (touch) {
        const pos = screenToNormalized(touch.clientX, touch.clientY)
        setPointerPosition(pos)
      }
    },
    [enabled, isInteractive, screenToNormalized, setPointerPosition]
  )

  // Touch start handler
  const handleTouchStart = useCallback(
    (e: TouchEvent) => {
      if (!enabled || !isInteractive) return

      setPointerDown(true)

      const touch = e.touches[0]
      if (touch) {
        const pos = screenToNormalized(touch.clientX, touch.clientY)
        setPointerPosition(pos)

        // Create pulse at touch location
        if (pos) {
          addPulse(createInteractionPulse(pos.x, pos.y))
        }

        // Detect double tap
        const now = Date.now()
        if (now - lastTapTime.current < 300) {
          // Double tap - create stronger pulse
          if (pos) {
            addPulse({
              ...createInteractionPulse(pos.x, pos.y),
              intensity: 1.5,
              speed: 0.8,
            })
          }
        }
        lastTapTime.current = now
      }
    },
    [enabled, isInteractive, screenToNormalized, setPointerPosition, setPointerDown, addPulse]
  )

  // Touch end handler
  const handleTouchEnd = useCallback(() => {
    setPointerPosition(null)
    setPointerDown(false)
  }, [setPointerPosition, setPointerDown])

  // Set up event listeners
  useEffect(() => {
    const container = containerRef.current
    if (!container || !enabled) return

    container.addEventListener('mousemove', handleMouseMove)
    container.addEventListener('mousedown', handleMouseDown)
    container.addEventListener('mouseup', handleMouseUp)
    container.addEventListener('mouseleave', handleMouseLeave)
    container.addEventListener('touchmove', handleTouchMove, { passive: true })
    container.addEventListener('touchstart', handleTouchStart, { passive: true })
    container.addEventListener('touchend', handleTouchEnd)

    return () => {
      container.removeEventListener('mousemove', handleMouseMove)
      container.removeEventListener('mousedown', handleMouseDown)
      container.removeEventListener('mouseup', handleMouseUp)
      container.removeEventListener('mouseleave', handleMouseLeave)
      container.removeEventListener('touchmove', handleTouchMove)
      container.removeEventListener('touchstart', handleTouchStart)
      container.removeEventListener('touchend', handleTouchEnd)
    }
  }, [
    containerRef,
    enabled,
    handleMouseMove,
    handleMouseDown,
    handleMouseUp,
    handleMouseLeave,
    handleTouchMove,
    handleTouchStart,
    handleTouchEnd,
  ])

  return {
    screenToNormalized,
  }
}
