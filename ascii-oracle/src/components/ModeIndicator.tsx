import { useOracleStore } from '../hooks/useOracleState'
import { COLORS } from '../lib/constants'
import type { InteractionMode } from '../types'

const MODE_LABELS: Record<InteractionMode, string> = {
  ambient: 'Ambient',
  oracle: 'Oracle',
  interactive: 'Interactive',
}

const MODE_ICONS: Record<InteractionMode, string> = {
  ambient: '◎',
  oracle: '☉',
  interactive: '⚛',
}

interface ModeIndicatorProps {
  showSelector?: boolean
}

export function ModeIndicator({ showSelector = false }: ModeIndicatorProps) {
  const mode = useOracleStore((s) => s.mode)
  const setMode = useOracleStore((s) => s.setMode)
  const performancePreset = useOracleStore((s) => s.performancePreset)
  const setPerformancePreset = useOracleStore((s) => s.setPerformancePreset)
  const reducedMotion = useOracleStore((s) => s.reducedMotion)
  const setReducedMotion = useOracleStore((s) => s.setReducedMotion)

  const modes: InteractionMode[] = ['ambient', 'oracle', 'interactive']

  return (
    <div
      style={{
        position: 'absolute',
        top: '1rem',
        right: '1rem',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'flex-end',
        gap: '0.5rem',
        pointerEvents: 'auto',
        zIndex: 10,
      }}
    >
      {/* Current mode indicator */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '0.5rem',
          padding: '0.5rem 1rem',
          background: 'rgba(10, 10, 15, 0.8)',
          border: `1px solid ${COLORS.dim}`,
          borderRadius: '4px',
          color: COLORS.mid,
          fontFamily: 'monospace',
          fontSize: '0.8rem',
        }}
      >
        <span style={{ color: COLORS.accent }}>{MODE_ICONS[mode]}</span>
        <span>{MODE_LABELS[mode]}</span>
      </div>

      {/* Mode selector */}
      {showSelector && (
        <div
          style={{
            display: 'flex',
            gap: '0.25rem',
            padding: '0.25rem',
            background: 'rgba(10, 10, 15, 0.8)',
            border: `1px solid ${COLORS.dim}`,
            borderRadius: '4px',
          }}
        >
          {modes.map((m) => (
            <button
              key={m}
              onClick={() => setMode(m)}
              style={{
                padding: '0.5rem 0.75rem',
                background: mode === m ? COLORS.accent : 'transparent',
                border: 'none',
                borderRadius: '2px',
                color: mode === m ? COLORS.highlight : COLORS.mid,
                fontFamily: 'monospace',
                fontSize: '0.75rem',
                cursor: 'pointer',
                transition: 'background 0.2s, color 0.2s',
              }}
              title={MODE_LABELS[m]}
            >
              {MODE_ICONS[m]}
            </button>
          ))}
        </div>
      )}

      {/* Performance preset selector */}
      {showSelector && (
        <div
          style={{
            display: 'flex',
            gap: '0.25rem',
            padding: '0.25rem',
            background: 'rgba(10, 10, 15, 0.8)',
            border: `1px solid ${COLORS.dim}`,
            borderRadius: '4px',
          }}
        >
          {(['minimal', 'balanced', 'intense'] as const).map((preset) => (
            <button
              key={preset}
              onClick={() => setPerformancePreset(preset)}
              style={{
                padding: '0.25rem 0.5rem',
                background:
                  performancePreset === preset ? COLORS.dim : 'transparent',
                border: 'none',
                borderRadius: '2px',
                color:
                  performancePreset === preset ? COLORS.highlight : COLORS.mid,
                fontFamily: 'monospace',
                fontSize: '0.65rem',
                cursor: 'pointer',
                textTransform: 'uppercase',
              }}
            >
              {preset.slice(0, 3)}
            </button>
          ))}
        </div>
      )}

      {/* Reduced motion toggle */}
      {showSelector && (
        <button
          onClick={() => setReducedMotion(!reducedMotion)}
          style={{
            padding: '0.25rem 0.5rem',
            background: reducedMotion ? COLORS.dim : 'transparent',
            border: `1px solid ${COLORS.dim}`,
            borderRadius: '4px',
            color: reducedMotion ? COLORS.highlight : COLORS.mid,
            fontFamily: 'monospace',
            fontSize: '0.65rem',
            cursor: 'pointer',
          }}
        >
          {reducedMotion ? 'Motion: Off' : 'Motion: On'}
        </button>
      )}
    </div>
  )
}
