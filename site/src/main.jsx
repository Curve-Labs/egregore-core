import { StrictMode, useEffect } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { C } from './tokens'
import App from './App.jsx'
import ResearchPage from './ResearchPage.jsx'
import ArticlePage from './ArticlePage.jsx'

function GlobalStyles() {
  useEffect(() => {
    const style = document.createElement("style");
    style.textContent = `
      @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,600;1,400&family=Space+Mono:ital,wght@0,400;0,700;1,400&family=UnifrakturMaguntia&display=swap');
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
      </Routes>
    </BrowserRouter>
  </StrictMode>,
)
