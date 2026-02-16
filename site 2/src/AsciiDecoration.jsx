import { useRef, useEffect, useState } from "react";
import { font } from "./tokens";

const PLACEMENTS = {
  "hero-backdrop": { position: "absolute", top: "5vh", right: "-2vw", zIndex: 0 },
  "flank-left": { position: "absolute", left: "-8vw", top: "10%", zIndex: 0 },
  "flank-right": { position: "absolute", right: "-8vw", top: "20%", zIndex: 0 },
  "centered-below": { margin: "0 auto", display: "block", textAlign: "center" },
  "section-bottom": { position: "absolute", bottom: "-2rem", left: "50%", transform: "translateX(-50%)", zIndex: 0 },
  "footer-left": { position: "absolute", left: "2vw", bottom: "5rem", zIndex: 0 },
  "footer-right": { position: "absolute", right: "2vw", bottom: "3rem", zIndex: 0 },
};

export default function AsciiDecoration({
  art,
  color = "rgba(200,165,90, 0.06)",
  fontSize = "clamp(0.35rem, 0.5vw, 0.55rem)",
  placement,
  className = "",
  style = {},
}) {
  const ref = useRef(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { threshold: 0.05, rootMargin: "100px" }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const placementStyle = placement ? PLACEMENTS[placement] || {} : {};
  const isCentered = placement === "centered-below";

  return (
    <pre
      ref={ref}
      aria-hidden="true"
      role="presentation"
      className={className}
      style={{
        ...font.mono,
        fontSize,
        lineHeight: 1.15,
        color,
        whiteSpace: "pre",
        overflowWrap: "normal",
        wordBreak: "keep-all",
        userSelect: "none",
        pointerEvents: "none",
        contain: isCentered ? "style paint" : "layout style paint",
        opacity: visible ? 1 : 0,
        transition: "opacity 1.2s ease",
        ...placementStyle,
        ...style,
      }}
    >
      {art}
    </pre>
  );
}
