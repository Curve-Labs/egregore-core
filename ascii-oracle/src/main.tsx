import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { useOracleStore } from './hooks/useOracleState'

// Check for reduced motion preference
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
if (prefersReducedMotion) {
  useOracleStore.getState().setReducedMotion(true)
}

// Listen for changes to reduced motion preference
window.matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', (e) => {
  useOracleStore.getState().setReducedMotion(e.matches)
})

// Detect mobile and set appropriate performance preset
const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent)
if (isMobile) {
  useOracleStore.getState().setPerformancePreset('minimal')
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
