import { useParams, Link } from "react-router-dom";
import { POSTS } from "./posts";
import { C, font } from "./tokens";
import { ARTICLE_CONTENT } from "./content";

const ArticlePage = () => {
  const { slug } = useParams();
  const post = POSTS.find((p) => p.slug === slug);
  const content = ARTICLE_CONTENT[slug];

  if (!post) {
    return (
      <div style={{ background: C.parchment, minHeight: "100vh", padding: "6rem 2rem", textAlign: "center" }}>
        <p style={{ ...font.serif, fontSize: "1.2rem", color: C.muted }}>Article not found.</p>
        <Link to="/research" style={{ ...font.mono, fontSize: "0.72rem", color: C.crimson, marginTop: "2rem", display: "inline-block" }}>
          Back to research
        </Link>
      </div>
    );
  }

  // Find adjacent posts for navigation
  const idx = POSTS.findIndex((p) => p.slug === slug);
  const prev = idx > 0 ? POSTS[idx - 1] : null;
  const next = idx < POSTS.length - 1 ? POSTS[idx + 1] : null;

  return (
    <div style={{ background: C.parchment, color: C.ink, ...font.serif, lineHeight: 1.6, minHeight: "100vh" }}>
      {/* Nav */}
      <nav style={{
        padding: "1.2rem 3rem",
        display: "flex", justifyContent: "space-between", alignItems: "center",
        borderBottom: `1px solid ${C.warmGray}`,
      }}>
        <Link to="/" style={{
          ...font.gothic, fontSize: "1.9rem", color: C.crimson, textDecoration: "none",
        }}>
          Egregore
        </Link>
        <div style={{ display: "flex", gap: "2rem", alignItems: "center" }}>
          <Link to="/research" style={{
            ...font.mono, color: C.ink, textDecoration: "none",
            fontSize: "0.67rem", letterSpacing: "1.5px", textTransform: "uppercase",
          }}>
            Research
          </Link>
          <a href="https://github.com/Curve-Labs/egregore-core" target="_blank" rel="noopener noreferrer" style={{
            ...font.mono, color: C.ink, textDecoration: "none",
            fontSize: "0.67rem", letterSpacing: "1.5px", textTransform: "uppercase",
          }}>
            Docs
          </a>
          <Link to="/#join" style={{
            ...font.mono, color: C.ink, textDecoration: "none",
            fontSize: "0.67rem", letterSpacing: "1.5px", textTransform: "uppercase",
            border: `1px solid ${C.ink}`, padding: "0.4rem 1.1rem",
          }}>
            Waitlist
          </Link>
        </div>
      </nav>

      {/* Article */}
      <article style={{ maxWidth: 680, margin: "0 auto", padding: "4rem 2rem 3rem" }}>
        {/* Meta */}
        <Link to="/research" style={{
          ...font.mono, fontSize: "0.58rem", letterSpacing: "2px",
          textTransform: "uppercase", color: C.muted, textDecoration: "none",
          display: "inline-block", marginBottom: "2rem",
        }}>
          &larr; Research
        </Link>

        <div style={{
          ...font.mono, fontSize: "0.58rem", letterSpacing: "2px",
          textTransform: "uppercase", color: C.gold, marginBottom: "1rem",
        }}>
          {post.tag} &middot; {post.date}
        </div>

        <h1 style={{
          ...font.serif, fontSize: "clamp(2rem, 4vw, 3rem)",
          fontWeight: 400, color: C.ink, lineHeight: 1.15, marginBottom: "1.5rem",
        }}>
          {post.title}
        </h1>

        <p style={{
          ...font.serif, fontSize: "1.2rem", color: C.muted,
          lineHeight: 1.7, marginBottom: "3rem",
          borderBottom: `1px solid ${C.warmGray}`, paddingBottom: "2rem",
        }}>
          {post.excerpt}
        </p>

        {/* Body */}
        {content ? (
          <div>
            {content.map((block, i) => {
              if (block.type === "h2") {
                return (
                  <h2 key={i} style={{
                    ...font.serif, fontSize: "1.6rem", fontWeight: 600,
                    color: C.ink, marginTop: "2.5rem", marginBottom: "1rem", lineHeight: 1.3,
                  }}>
                    {block.text}
                  </h2>
                );
              }
              if (block.type === "h3") {
                return (
                  <h3 key={i} style={{
                    ...font.mono, fontSize: "0.82rem", fontWeight: 700,
                    color: C.gold, letterSpacing: "1.5px", textTransform: "uppercase",
                    marginTop: "2rem", marginBottom: "0.75rem",
                  }}>
                    {block.text}
                  </h3>
                );
              }
              if (block.type === "p") {
                return (
                  <p key={i} style={{
                    ...font.serif, fontSize: "1.08rem", color: "#4a4640",
                    lineHeight: 1.8, marginBottom: "1.2rem",
                  }}>
                    {block.text}
                  </p>
                );
              }
              if (block.type === "quote") {
                return (
                  <blockquote key={i} style={{
                    borderLeft: `2px solid ${C.gold}`,
                    paddingLeft: "1.5rem", margin: "1.5rem 0",
                    ...font.serif, fontSize: "1.05rem", fontStyle: "italic",
                    color: C.muted, lineHeight: 1.75,
                  }}>
                    {block.text}
                  </blockquote>
                );
              }
              if (block.type === "divider") {
                return (
                  <div key={i} style={{
                    display: "flex", alignItems: "center", justifyContent: "center",
                    margin: "2.5rem 0", gap: "0.8rem",
                  }}>
                    <div style={{ height: 1, width: 60, background: C.warmGray }} />
                    <div style={{ width: 5, height: 5, background: C.crimson, transform: "rotate(45deg)" }} />
                    <div style={{ height: 1, width: 60, background: C.warmGray }} />
                  </div>
                );
              }
              return null;
            })}
          </div>
        ) : (
          <div style={{
            ...font.mono, fontSize: "0.78rem", color: C.muted,
            padding: "3rem 0", textAlign: "center", letterSpacing: "1px",
          }}>
            Article in progress.
          </div>
        )}

        {/* Adjacent post nav */}
        <div style={{
          borderTop: `1px solid ${C.warmGray}`, marginTop: "3rem", paddingTop: "2rem",
          display: "flex", justifyContent: "space-between",
        }}>
          {prev ? (
            <Link to={`/research/${prev.slug}`} style={{
              textDecoration: "none", color: "inherit", maxWidth: "45%",
            }}>
              <div style={{ ...font.mono, fontSize: "0.55rem", color: C.muted, letterSpacing: "1.5px", textTransform: "uppercase", marginBottom: "0.3rem" }}>
                &larr; Previous
              </div>
              <div style={{ ...font.serif, fontSize: "1rem", color: C.crimson, lineHeight: 1.3 }}>
                {prev.title}
              </div>
            </Link>
          ) : <div />}
          {next ? (
            <Link to={`/research/${next.slug}`} style={{
              textDecoration: "none", color: "inherit", textAlign: "right", maxWidth: "45%",
            }}>
              <div style={{ ...font.mono, fontSize: "0.55rem", color: C.muted, letterSpacing: "1.5px", textTransform: "uppercase", marginBottom: "0.3rem" }}>
                Next &rarr;
              </div>
              <div style={{ ...font.serif, fontSize: "1rem", color: C.crimson, lineHeight: 1.3 }}>
                {next.title}
              </div>
            </Link>
          ) : <div />}
        </div>
      </article>

      {/* Footer */}
      <div style={{ maxWidth: 680, margin: "0 auto", padding: "3rem 2rem 2rem" }}>
        <div style={{
          ...font.mono, fontSize: "0.55rem", color: C.warmGray,
          borderTop: `1px solid ${C.warmGray}`, paddingTop: "2rem",
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

export default ArticlePage;
