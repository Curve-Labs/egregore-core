import { useState, useEffect, useRef, useCallback } from "react";
import { Link, useLocation } from "react-router-dom";
import { C, font } from "./tokens";
import { DOCS_NAV, DOCS } from "./docs-content";

const DocsPage = () => {
  const [activeId, setActiveId] = useState("overview");
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const location = useLocation();
  const observerRef = useRef(null);

  // Scroll to hash on mount
  useEffect(() => {
    const hash = location.hash?.slice(1);
    if (hash && document.getElementById(hash)) {
      setTimeout(() => {
        document.getElementById(hash)?.scrollIntoView({ behavior: "smooth", block: "start" });
        setActiveId(hash);
      }, 100);
    }
  }, []);

  // Scroll spy
  useEffect(() => {
    const ids = DOCS_NAV.flatMap(g => g.items.map(i => i.id));
    observerRef.current = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter(e => e.isIntersecting);
        if (visible.length > 0) {
          setActiveId(visible[0].target.id);
        }
      },
      { rootMargin: "-60px 0px -65% 0px" }
    );

    ids.forEach(id => {
      const el = document.getElementById(id);
      if (el) observerRef.current.observe(el);
    });

    return () => observerRef.current?.disconnect();
  }, []);

  const scrollTo = useCallback((id) => {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "start" });
      window.history.replaceState(null, "", `#${id}`);
      setActiveId(id);
      setSidebarOpen(false);
    }
  }, []);

  // ─── Block Renderer ───────────────────────────────────────────

  const renderBlock = (block, i) => {
    switch (block.type) {

      case "p":
        return (
          <p key={i} style={{
            ...font.serif, fontSize: "0.95rem", color: "#4a4640",
            lineHeight: 1.75, marginBottom: "0.9rem",
          }}>
            {block.text}
          </p>
        );

      case "h3":
        return (
          <h3 key={i} style={{
            ...font.mono, fontSize: "0.68rem", fontWeight: 700,
            color: C.gold, letterSpacing: "1.5px", textTransform: "uppercase",
            marginTop: "1.6rem", marginBottom: "0.5rem",
          }}>
            {block.text}
          </h3>
        );

      case "code":
        return (
          <pre key={i} style={{
            background: C.termBg, color: "#d4cfc5",
            ...font.ibmPlex, fontSize: "0.72rem", lineHeight: 1.65,
            padding: "0.9rem 1.2rem", borderRadius: "3px",
            marginBottom: "1rem", overflowX: "auto",
            border: "1px solid rgba(255,255,255,0.06)",
          }}>
            {block.text}
          </pre>
        );

      case "list":
        return (
          <ul key={i} style={{
            ...font.serif, fontSize: "0.92rem", color: "#4a4640",
            lineHeight: 1.75, marginBottom: "1rem",
            paddingLeft: "1.2rem", listStyleType: "none",
          }}>
            {block.items.map((item, j) => (
              <li key={j} style={{ marginBottom: "0.35rem", position: "relative", paddingLeft: "0.9rem" }}>
                <span style={{
                  position: "absolute", left: 0, top: "0.5rem",
                  width: 3, height: 3, background: C.crimson,
                  transform: "rotate(45deg)", display: "inline-block",
                }} />
                {item}
              </li>
            ))}
          </ul>
        );

      case "table":
        return (
          <div key={i} style={{ marginBottom: "1rem", overflowX: "auto" }}>
            <table style={{
              width: "100%", borderCollapse: "collapse",
              ...font.serif, fontSize: "0.88rem",
            }}>
              <tbody>
                {block.rows.map((row, j) => (
                  <tr key={j} style={{ borderBottom: `1px solid ${C.warmGray}` }}>
                    <td style={{
                      padding: "0.5rem 0.8rem 0.5rem 0",
                      ...font.mono, fontSize: "0.7rem",
                      color: C.ink, fontWeight: 700,
                      whiteSpace: "nowrap", verticalAlign: "top",
                      width: "35%",
                    }}>
                      {row[0]}
                    </td>
                    <td style={{
                      padding: "0.5rem 0",
                      color: "#4a4640", verticalAlign: "top",
                    }}>
                      {row[1]}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );

      case "quote":
        return (
          <blockquote key={i} style={{
            borderLeft: `2px solid ${C.gold}`,
            paddingLeft: "1.2rem", margin: "1.2rem 0",
            ...font.serif, fontSize: "0.92rem", fontStyle: "italic",
            color: C.muted, lineHeight: 1.7,
          }}>
            {block.text}
          </blockquote>
        );

      case "note":
        return (
          <div key={i} style={{
            background: "rgba(200,165,90,0.07)",
            borderLeft: `2px solid ${C.gold}`,
            padding: "0.7rem 1rem", marginBottom: "1rem",
            borderRadius: "0 3px 3px 0",
          }}>
            <p style={{
              ...font.serif, fontSize: "0.88rem", color: "#4a4640",
              lineHeight: 1.65, margin: 0,
            }}>
              {block.text}
            </p>
          </div>
        );

      case "divider":
        return (
          <div key={i} style={{
            display: "flex", alignItems: "center", justifyContent: "center",
            margin: "2rem 0", gap: "0.6rem",
          }}>
            <div style={{ height: 1, width: 40, background: C.warmGray }} />
            <div style={{ width: 4, height: 4, background: C.crimson, transform: "rotate(45deg)" }} />
            <div style={{ height: 1, width: 40, background: C.warmGray }} />
          </div>
        );

      default:
        return null;
    }
  };

  // ─── Sidebar Item ─────────────────────────────────────────────

  const SidebarItem = ({ id, title }) => {
    const [hovered, setHovered] = useState(false);
    const isActive = activeId === id;

    return (
      <div
        onClick={() => scrollTo(id)}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        style={{
          ...font.mono, fontSize: "0.65rem",
          color: isActive ? C.crimson : hovered ? C.ink : C.muted,
          cursor: "pointer",
          padding: "0.2rem 0 0.2rem 0.8rem",
          borderLeft: isActive ? `1.5px solid ${C.crimson}` : "1.5px solid transparent",
          transition: "all 0.15s ease",
          letterSpacing: "0.2px",
        }}
      >
        {title}
      </div>
    );
  };

  // ─── Render ───────────────────────────────────────────────────

  const allSections = DOCS_NAV.flatMap(g => g.items);

  return (
    <div style={{ background: C.parchment, color: C.ink, ...font.serif, lineHeight: 1.6, minHeight: "100vh" }}>

      {/* ─── Nav ─────────────────────────────────────────────── */}
      <nav className="mobile-nav" style={{
        position: "fixed", top: 0, width: "100%", zIndex: 900,
        height: "80px",
        padding: "0 4rem",
        display: "flex", justifyContent: "space-between", alignItems: "center",
        background: "rgba(244,241,234,0.95)",
        backdropFilter: "blur(10px)",
        borderBottom: `1px solid ${C.warmGray}`,
        transition: "all 0.3s ease",
      }}>
        <Link to="/" className="mobile-logo" style={{
          ...font.gothic, fontSize: "1.9rem", color: C.crimson, textDecoration: "none",
        }}>
          Egregore
        </Link>
        <div className="mobile-nav-links" style={{ display: "flex", gap: "2rem", alignItems: "center" }}>
          <Link to="/research" style={{
            ...font.ibmPlex, color: C.ink, textDecoration: "none",
            fontSize: "14px", letterSpacing: "0", textTransform: "uppercase",
            padding: "0.4rem 0",
          }}>
            /Research
          </Link>
          <a href="https://egregore.xyz/docs" style={{
            ...font.ibmPlex, color: C.ink, textDecoration: "none",
            fontSize: "14px", letterSpacing: "0", textTransform: "uppercase",
            padding: "0.4rem 0",
            borderBottom: `2px solid ${C.crimson}`,
          }}>
            /Docs
          </a>
          <Link to="/#join" className="mobile-button" style={{
            ...font.ibmPlex, color: C.ink, textDecoration: "none",
            fontSize: "14px", letterSpacing: "0", textTransform: "uppercase",
            border: `1px solid ${C.ink}`,
            padding: "0.4rem 1.1rem",
          }}>
            /Waitlist
          </Link>
        </div>
      </nav>

      {/* ─── Mobile sidebar toggle ───────────────────────────── */}
      <div
        onClick={() => setSidebarOpen(!sidebarOpen)}
        style={{
          display: "none",
          position: "sticky", top: "80px", zIndex: 90,
          padding: "0.5rem 1.5rem",
          background: C.parchment,
          borderBottom: `1px solid ${C.warmGray}`,
          ...font.mono, fontSize: "0.62rem", color: C.muted,
          cursor: "pointer", letterSpacing: "1px",
        }}
        className="docs-mobile-toggle"
      >
        {sidebarOpen ? "\u2715 Close" : "\u2261 Navigation"}
      </div>

      {/* ─── Layout ──────────────────────────────────────────── */}
      <div style={{ display: "flex", maxWidth: 960, margin: "0 auto", paddingTop: "80px" }}>

        {/* ─── Sidebar ─────────────────────────────────────── */}
        <aside
          className={`docs-sidebar${sidebarOpen ? " open" : ""}`}
          style={{
            width: 180, flexShrink: 0,
            position: "sticky", top: "80px",
            height: "calc(100vh - 80px)",
            overflowY: "auto",
            padding: "2rem 0 2rem 1.5rem",
            borderRight: `1px solid ${C.warmGray}`,
          }}
        >
          {DOCS_NAV.map((group, gi) => (
            <div key={gi} style={{ marginBottom: "1.2rem" }}>
              <div style={{
                ...font.mono, fontSize: "0.5rem", fontWeight: 700,
                letterSpacing: "2px", textTransform: "uppercase",
                color: C.warmGray, marginBottom: "0.35rem",
                paddingLeft: "0.8rem",
              }}>
                {group.group}
              </div>
              {group.items.map(item => (
                <SidebarItem key={item.id} id={item.id} title={item.title} />
              ))}
            </div>
          ))}
        </aside>

        {/* ─── Content ─────────────────────────────────────── */}
        <main style={{ flex: 1, minWidth: 0, padding: "2.5rem 2rem 3rem 3rem", maxWidth: 680 }}>

          {/* Header */}
          <div style={{ marginBottom: "2.5rem" }}>
            <div style={{
              ...font.mono, fontSize: "0.5rem", letterSpacing: "3px",
              textTransform: "uppercase", color: C.muted, marginBottom: "0.8rem",
            }}>
              Documentation
            </div>
            <h1 style={{
              ...font.serif, fontSize: "clamp(1.5rem, 3vw, 2.2rem)",
              fontWeight: 400, color: C.ink, lineHeight: 1.15, marginBottom: "0.8rem",
            }}>
              Command Reference
            </h1>
            <p style={{
              ...font.serif, fontSize: "0.95rem", color: C.muted,
              maxWidth: 460, lineHeight: 1.65, marginBottom: "1.5rem",
            }}>
              Everything you need to work inside an Egregore. Commands, architecture, and configuration.
            </p>
            <div style={{ height: 1, background: C.warmGray }} />
          </div>

          {/* Sections */}
          {allSections.map((item) => {
            const section = DOCS[item.id];
            if (!section) return null;

            const isCommand = section.title.startsWith("/");

            return (
              <section
                key={item.id}
                id={item.id}
                style={{
                  marginBottom: "2.8rem",
                  scrollMarginTop: "60px",
                }}
              >
                <h2 style={{
                  ...(isCommand ? font.mono : font.serif),
                  fontSize: isCommand ? "1.05rem" : "1.3rem",
                  fontWeight: isCommand ? 700 : 600,
                  color: C.ink,
                  marginBottom: "0.7rem",
                  lineHeight: 1.3,
                  letterSpacing: isCommand ? "-0.3px" : "0",
                }}>
                  {section.title}
                </h2>
                {section.blocks.map(renderBlock)}
              </section>
            );
          })}
        </main>
      </div>

      {/* ─── Footer ──────────────────────────────────────────── */}
      <div style={{ maxWidth: 960, margin: "0 auto", padding: "2rem 2rem 1.5rem" }}>
        <div style={{
          ...font.mono, fontSize: "0.5rem", color: C.warmGray,
          borderTop: `1px solid ${C.warmGray}`, paddingTop: "1.5rem",
          display: "flex", justifyContent: "space-between", letterSpacing: "1px",
        }}>
          <a href="https://www.curvelabs.eu/" target="_blank" rel="noopener noreferrer" style={{ color: "inherit", textDecoration: "none" }}>Curve Labs</a>
          <span>MMXXVI</span>
          <span>Berlin / The Graph</span>
        </div>
      </div>

      {/* ─── Responsive styles ───────────────────────────────── */}
      <style>{`
        .docs-mobile-toggle { display: none !important; }
        @media (max-width: 768px) {
          .docs-sidebar {
            display: none !important;
          }
          .docs-sidebar.open {
            display: block !important;
            position: fixed !important;
            top: 80px !important;
            left: 0 !important;
            width: 220px !important;
            height: calc(100vh - 80px) !important;
            background: ${C.parchment} !important;
            z-index: 80 !important;
            box-shadow: 4px 0 20px rgba(0,0,0,0.1) !important;
          }
          .docs-mobile-toggle { display: block !important; }
        }
      `}</style>
    </div>
  );
};

export default DocsPage;
