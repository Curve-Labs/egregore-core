import { StrictMode, useEffect } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { C } from './tokens'
import App from './App.jsx'
import ResearchPage from './ResearchPage.jsx'
import ArticlePage from './ArticlePage.jsx'
import DocsPage from './DocsPage.jsx'

function GlobalStyles() {
  useEffect(() => {
    const style = document.createElement("style");
    style.textContent = `
      @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,600;1,400&family=Space+Mono:ital,wght@0,400;0,700;1,400&family=UnifrakturMaguntia&family=IBM+Plex+Mono:wght@400;700&family=Courier+Prime:wght@400;700&display=swap');

      @font-face {
        font-family: 'Slovic';
        src: url('/fonts/Slovic_Demo-Historic.otf') format('opentype');
        font-weight: normal;
        font-style: normal;
        font-display: swap;
      }

      * { box-sizing: border-box; margin: 0; padding: 0; }
      html { scroll-behavior: smooth; }
      body { background: ${C.parchment}; }
      @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
      ::selection { background: ${C.crimson}; color: ${C.parchment}; }
      ::-webkit-scrollbar { width: 4px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb { background: rgba(122,15,27,0.3); border-radius: 2px; }
      ::-webkit-scrollbar-thumb:hover { background: rgba(122,15,27,0.5); }
      textarea:focus, input:focus { border-bottom-color: rgba(200,165,90,0.5) !important; }

      /* ASCII decoration responsive */
      .ascii-hide-mobile { display: block; }
      .ascii-hide-tablet { display: block; }
      @media (max-width: 768px) { .ascii-hide-mobile { display: none !important; } }
      @media (max-width: 1024px) { .ascii-hide-tablet { display: none !important; } }

      /* Egregore calligraphic text scaling */
      .ascii-egregore-text { transform-origin: center center; }
      @media (max-width: 1200px) { .ascii-egregore-text { transform: scale(0.7) !important; } }
      @media (max-width: 768px) { .ascii-egregore-text { transform: scale(0.45) !important; } }

      /* Mobile adjustments: 375px × 812px baseline */
      @media (max-width: 480px) {
        body { font-size: 16px; }
        .mobile-container { padding: 0 5% !important; max-width: 100% !important; }
        .mobile-section { height: auto !important; min-height: 600px !important; }
        .mobile-section-padding { padding: 3rem 1.25rem !important; }
        .mobile-nav { height: 70px !important; padding: 0 1.5rem !important; }
        .mobile-logo { font-size: 1.4rem !important; }
        .mobile-nav-links { gap: 1rem !important; font-size: 12px !important; }
        .mobile-hide { display: none !important; }
        .mobile-text-center { text-align: center !important; }
        .mobile-gap-small { gap: 1.5rem !important; }
        .mobile-flex-col { flex-direction: column !important; align-items: center !important; }
        .mobile-hero-title { font-size: 32px !important; line-height: 1.1 !important; }
        .mobile-section-title { font-size: 28px !important; line-height: 1.2 !important; }
        .mobile-body-text { font-size: 16px !important; line-height: 1.65 !important; }
        .mobile-card-title { font-size: 0.75rem !important; }
        .mobile-button { padding: 0.7rem 1.5rem !important; font-size: 12px !important; min-height: 44px !important; }
        .mobile-value-grid { grid-template-columns: 1fr !important; gap: 3rem !important; }
        .mobile-session-grid { grid-template-columns: 1fr !important; gap: 2rem !important; }
        .mobile-input { font-size: 16px !important; padding: 0.75rem !important; min-height: 44px !important; }
      }

      /* Print: hide all decorative ASCII */
      @media print { pre[aria-hidden="true"], .ascii-hide-mobile, .ascii-hide-tablet, .ascii-egregore-text { display: none !important; } }
    `;
    document.head.appendChild(style);
    return () => document.head.removeChild(style);
  }, []);
  return null;
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <GlobalStyles />
      <Routes>
        <Route path="/" element={<App />} />
        <Route path="/research" element={<ResearchPage />} />
        <Route path="/research/:slug" element={<ArticlePage />} />
        <Route path="/docs" element={<DocsPage />} />
      </Routes>
    </BrowserRouter>
  </StrictMode>,
)
