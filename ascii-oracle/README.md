# ASCII Oracle

A WebGL-accelerated generative ASCII art system with oracle interaction mode.

## Features

- **GPU-Accelerated Rendering**: WebGL shaders for energy field computation and SDF-based character rendering
- **Multiple Interaction Modes**:
  - **Ambient**: Auto-playing generative animation
  - **Oracle**: Question input with Claude API integration for responses
  - **Interactive**: Mouse/touch creates energy ripples
- **Post-Processing**: Bloom, vignette effects via @react-three/postprocessing
- **Performance Presets**: Minimal, balanced, and intense modes
- **Accessibility**: Reduced motion support

## Tech Stack

- React + TypeScript
- Three.js via @react-three/fiber
- Zustand for state management
- Vite for build tooling
- GLSL shaders

## Getting Started

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Architecture

```
src/
├── components/
│   ├── AsciiOracle.tsx      # Main Three.js canvas component
│   ├── InputOverlay.tsx     # Oracle question input UI
│   └── ModeIndicator.tsx    # Mode selector UI
├── shaders/
│   ├── noise.glsl           # Simplex noise functions
│   ├── energy.frag          # Energy field computation
│   ├── ascii.vert/frag      # Character rendering
│   ├── bloom.frag           # Bloom extraction
│   └── composite.frag       # Final composition
├── hooks/
│   ├── useOracleState.ts    # Zustand store
│   └── useInteraction.ts    # Mouse/touch handling
├── lib/
│   ├── constants.ts         # Colors, zones, presets
│   ├── characters.ts        # Character definitions
│   └── markov.ts            # Transition logic
└── types.ts
```

## Energy Field System

The visual effect is created by layering multiple generative systems:

1. **Zone-based base energy**: Radial zones from center to edge
2. **Flow field**: Curl noise provides directional coherence
3. **Multi-scale noise**: FBM creates organic patterns
4. **Pulse system**: Orbiting and interaction-triggered ripples
5. **Oracle energy**: Thinking/revealing states boost energy

## Character Families

Characters are organized into families based on visual complexity:

- void: spaces
- sparse: `.` `·` `:` `∙`
- dots: `•` `◦` `○` `●` `◎` `◉`
- circles: `◯` `⊙` `⊚` `⊛` `◐` `◑`
- geometric: `△` `▽` `◇` `◆` `□` `■` `⬡`
- lines: `│` `─` `┼` `╱` `╲` `╳`
- special: `✦` `✧` `★` `☆` `✶`
- mystic: `☉` `☽` `☾` `✡` `⚝`

Energy level determines which family is rendered, with Markov transitions providing smooth evolution.

## Integration

```tsx
import { AsciiOracle } from './components/AsciiOracle'

function App() {
  const handleQuery = async (question: string): Promise<string> => {
    // Call your Claude API endpoint
    const response = await fetch('/api/oracle', {
      method: 'POST',
      body: JSON.stringify({ question }),
    })
    const data = await response.json()
    return data.answer
  }

  return (
    <AsciiOracle
      showModeSelector={true}
      onOracleQuery={handleQuery}
    />
  )
}
```

## Performance

- **Minimal**: 50% grid density, no post-processing
- **Balanced**: 75% grid density, bloom + vignette
- **Intense**: 100% grid density, full effects

Targets 60fps on modern hardware. Mobile devices may run at reduced settings.
