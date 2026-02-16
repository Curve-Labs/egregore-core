import { useState } from "react";
import { Link } from "react-router-dom";
import { POSTS } from "./posts";
import { C, font } from "./tokens";

const ResearchPage = () => {
  const [hoveredIdx, setHoveredIdx] = useState(null);

  return (
    <div style={{ background: C.parchment, color: C.ink, ...font.serif, lineHeight: 1.6, minHeight: "100vh" }}>
      {/* Nav */}
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
          ...font.gothic, fontSize: "1.9rem", color: C.crimson,
          textDecoration: "none",
        }}>
          Egregore
        </Link>
        <div className="mobile-nav-links" style={{ display: "flex", gap: "2rem", alignItems: "center" }}>
          <Link to="/research" style={{
            ...font.ibmPlex, color: C.ink, textDecoration: "none",
            fontSize: "14px", letterSpacing: "0", textTransform: "uppercase",
            padding: "0.4rem 0",
            borderBottom: `2px solid ${C.crimson}`,
          }}>
            /Research
          </Link>
          <Link to="/docs" style={{
            ...font.ibmPlex, color: C.ink, textDecoration: "none",
            fontSize: "14px", letterSpacing: "0", textTransform: "uppercase",
            padding: "0.4rem 0",
          }}>
            /Docs
          </Link>
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

      {/* Header */}
      <div style={{ maxWidth: 900, margin: "0 auto", padding: "8rem 2rem 2rem" }}>
        <div style={{
          ...font.mono, fontSize: "0.58rem", letterSpacing: "3.5px",
          textTransform: "uppercase", color: C.muted, marginBottom: "1rem",
        }}>
          Research
        </div>
        <h1 style={{
          ...font.serif, fontSize: "clamp(2rem, 4vw, 3.2rem)",
          fontWeight: 400, color: C.ink, lineHeight: 1.15, marginBottom: "1rem",
        }}>
          Dispatches from the field.
        </h1>
        <p style={{
          ...font.serif, fontSize: "1.15rem", color: C.muted,
          maxWidth: 560, lineHeight: 1.7, marginBottom: "3rem",
        }}>
          On shared cognition, coordination infrastructure, and what emerges when organizations develop memory.
        </p>

        <div style={{ height: 1, background: C.warmGray, marginBottom: "2rem" }} />

        {/* Post list */}
        <div style={{ display: "flex", flexDirection: "column" }}>
          {POSTS.map((post, i) => (
            <Link
              key={post.slug}
              to={`/research/${post.slug}`}
              onMouseEnter={() => setHoveredIdx(i)}
              onMouseLeave={() => setHoveredIdx(null)}
              style={{
                textDecoration: "none", color: "inherit",
                display: "grid",
                gridTemplateColumns: "120px 1fr",
                gap: "2rem",
                padding: "2rem 0",
                borderBottom: i < POSTS.length - 1 ? `1px solid ${C.warmGray}` : "none",
                transition: "background 0.2s",
                background: hoveredIdx === i ? "rgba(200,165,90,0.04)" : "transparent",
                margin: "0 -1rem",
                paddingLeft: "1rem",
                paddingRight: "1rem",
              }}
            >
              <div>
                <div style={{
                  ...font.mono, fontSize: "0.58rem", letterSpacing: "2px",
                  textTransform: "uppercase",
                  color: hoveredIdx === i ? C.gold : C.muted,
                  transition: "color 0.2s",
                  marginBottom: "0.4rem",
                }}>
                  {post.tag}
                </div>
                <div style={{
                  ...font.mono, fontSize: "0.58rem", color: C.warmGray, letterSpacing: "1px",
                }}>
                  {post.date}
                </div>
              </div>

              <div>
                <h2 style={{
                  ...font.serif, fontSize: "1.35rem", fontWeight: 600,
                  color: hoveredIdx === i ? C.crimson : C.ink,
                  transition: "color 0.2s",
                  marginBottom: "0.5rem", lineHeight: 1.3,
                }}>
                  {post.title}
                </h2>
                <p style={{
                  ...font.serif, fontSize: "0.98rem", color: C.muted,
                  lineHeight: 1.65, maxWidth: 560,
                }}>
                  {post.excerpt}
                </p>
              </div>
            </Link>
          ))}
        </div>
      </div>

      {/* Footer */}
      <div style={{
        maxWidth: 900, margin: "0 auto", padding: "4rem 2rem 2rem",
      }}>
        <div style={{
          ...font.mono, fontSize: "0.55rem", color: C.warmGray,
          borderTop: `1px solid ${C.warmGray}`,
          paddingTop: "2rem",
          display: "flex", justifyContent: "space-between", letterSpacing: "1px",
        }}>
          <span>Egregore Systems</span>
          <span>MMXXVI</span>
          <span>Berlin / The Graph</span>
        </div>
      </div>
    </div>
  );
};

export default ResearchPage;
