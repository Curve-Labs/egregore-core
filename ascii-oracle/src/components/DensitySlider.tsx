import { COLORS } from '../lib/constants'

interface SliderRowProps {
  label: string
  value: number
  onChange: (value: number) => void
  min: number
  max: number
  step: number
  decimals?: number
}

function SliderRow({ label, value, onChange, min, max, step, decimals = 2 }: SliderRowProps) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
      <span style={{ color: COLORS.mid, fontSize: '0.7rem', minWidth: '55px' }}>{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{
          width: '100px',
          accentColor: COLORS.accent,
          cursor: 'pointer',
        }}
      />
      <span
        style={{
          color: COLORS.highlight,
          fontSize: '0.85rem',
          minWidth: '4ch',
          textAlign: 'right',
          fontWeight: 'bold',
        }}
      >
        {value.toFixed(decimals)}
      </span>
    </div>
  )
}

interface ControlSlidersProps {
  density: number
  onDensityChange: (value: number) => void
  size: number
  onSizeChange: (value: number) => void
  weBuildThickness: number
  onWeBuildThicknessChange: (value: number) => void
  monochrome: boolean
  onMonochromeToggle: () => void
}

export function ControlSliders({
  density,
  onDensityChange,
  size,
  onSizeChange,
  weBuildThickness,
  onWeBuildThicknessChange,
  monochrome,
  onMonochromeToggle,
}: ControlSlidersProps) {
  return (
    <div
      style={{
        position: 'absolute',
        bottom: '1.5rem',
        left: '50%',
        transform: 'translateX(-50%)',
        display: 'flex',
        flexDirection: 'column',
        gap: '0.5rem',
        padding: '0.75rem 1.25rem',
        background: 'rgba(10, 10, 15, 0.85)',
        border: `1px solid ${COLORS.dim}`,
        borderRadius: '8px',
        zIndex: 20,
        fontFamily: 'monospace',
      }}
    >
      <SliderRow
        label="DENSITY"
        value={density}
        onChange={onDensityChange}
        min={0.2}
        max={1.5}
        step={0.05}
      />
      <SliderRow
        label="SIZE"
        value={size}
        onChange={onSizeChange}
        min={0.3}
        max={1.2}
        step={0.05}
        decimals={2}
      />
      <SliderRow
        label="WE BUILD"
        value={weBuildThickness}
        onChange={onWeBuildThicknessChange}
        min={0.0}
        max={1.2}
        step={0.02}
        decimals={2}
      />
      <button
        type="button"
        onClick={onMonochromeToggle}
        style={{
          alignSelf: 'flex-end',
          padding: '0.35rem 0.6rem',
          borderRadius: '6px',
          border: `1px solid ${monochrome ? COLORS.accent : COLORS.dim}`,
          background: monochrome ? 'rgba(120, 80, 220, 0.2)' : 'transparent',
          color: monochrome ? COLORS.highlight : COLORS.mid,
          fontSize: '0.7rem',
          fontFamily: 'monospace',
          cursor: 'pointer',
          letterSpacing: '0.04em',
        }}
      >
        MONOCHROME {monochrome ? 'ON' : 'OFF'}
      </button>
    </div>
  )
}

// Keep old export for compatibility
export function DensitySlider(props: { value: number; onChange: (v: number) => void }) {
  return (
    <ControlSliders
      density={props.value}
      onDensityChange={props.onChange}
      size={1}
      onSizeChange={() => {}}
      weBuildThickness={0.6}
      onWeBuildThicknessChange={() => {}}
      monochrome={false}
      onMonochromeToggle={() => {}}
    />
  )
}
