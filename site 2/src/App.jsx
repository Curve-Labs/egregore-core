import { useState, useEffect, useRef, useCallback } from "react";
import { Link } from "react-router-dom";
import { C, font } from "./tokens";
import { POSTS } from "./posts";
import wizardsWorking from "./wizards working.txt?raw";
import egregoricIntelligence from "./egregoric_intelligence.txt?raw";
import egregoreMonster from "./egregore_monster.txt?raw";
import terminalFrame from "./terminal_frame.txt?raw";
import footerFlower from "./footer flower.txt?raw";
import footerStar from "./footer_star_last.txt?raw";
import oneSubstrate from "./one_subsrate.txt?raw";
import contextGardening from "./context_gardening.txt?raw";
import organizationalLearning from "./new_organizational_learning.txt?raw";
import monsterOrnamentLeft from "./monster_ornament_left.txt?raw";
import monsterOrnamentRight from "./monster_ornament_right.txt?raw";
import astro from "./astro.txt?raw";

// ─── Utility Components ─────────────────────────────────────────
const Divider = () => (
  <div style={{ display: "flex", alignItems: "center", justifyContent: "center", margin: "3rem 0", gap: "1.5rem" }}>
    <div style={{ height: 1, width: 120, background: C.warmGray }} />
    <div style={{ width: 8, height: 8, background: C.crimson, transform: "rotate(45deg)" }} />
    <div style={{ height: 1, width: 120, background: C.warmGray }} />
  </div>
);

const SectionLabel = ({ children, light }) => (
  <div style={{
    ...font.mono, fontSize: "0.62rem", textTransform: "uppercase",
    letterSpacing: "3.5px", marginBottom: "1rem", textAlign: "center",
    color: light ? "rgba(244,241,234,0.35)" : C.muted,
  }}>
    {children}
  </div>
);

const Container = ({ children, style = {} }) => (
  <div className="mobile-container" style={{ maxWidth: 1500, margin: "0 auto", padding: "0 3rem", ...style }}>{children}</div>
);

// ─── Navigation ─────────────────────────────────────────────────
const Navigation = () => {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 50);
    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const linkStyle = {
    ...font.ibmPlex, color: C.ink, textDecoration: "none",
    fontSize: "14px", letterSpacing: "0", textTransform: "uppercase",
    padding: "0.4rem 0",
  };

  return (
    <nav className="mobile-nav" style={{
      position: "fixed", top: 0, width: "100%", zIndex: 900,
      height: "80px",
      padding: "0 4rem",
      display: "flex", justifyContent: "space-between", alignItems: "center",
      background: scrolled ? "rgba(244,241,234,0.95)" : "transparent",
      backdropFilter: scrolled ? "blur(10px)" : "none",
      borderBottom: scrolled ? `1px solid ${C.warmGray}` : "1px solid transparent",
      transition: "all 0.3s ease",
    }}>
      <a href="#top" className="mobile-logo" style={{
        ...font.gothic, fontSize: "1.9rem", color: C.crimson,
        textDecoration: "none",
      }}>
        Egregore
      </a>
      <div className="mobile-nav-links" style={{ display: "flex", gap: "2rem", alignItems: "center" }}>
        <Link to="/research" style={linkStyle}>/Research</Link>
        <Link to="/docs" style={linkStyle}>/Docs</Link>
        <a href="#join" className="mobile-button" style={{
          ...linkStyle, border: `1px solid ${C.ink}`,
          padding: "0.4rem 1.1rem",
        }}>
          /Waitlist
        </a>
      </div>
    </nav>
  );
};

// ─── Section 1: Hero ────────────────────────────────────────────
const Hero = () => (
  <section id="top" className="mobile-section mobile-section-padding" style={{
    height: "1000px", display: "flex", alignItems: "center",
    position: "relative", overflow: "hidden",
    padding: "8rem 4rem 3rem",
  }}>
    <Container style={{ width: "100%", maxWidth: "1600px" }}>
      <div className="mobile-flex-col mobile-gap-small" style={{
        display: "flex",
        alignItems: "center",
        gap: "4rem",
        justifyContent: "space-between",
      }}>
        {/* Left side - Text content */}
        <div style={{ flex: "1", maxWidth: "600px", position: "relative", zIndex: 2 }}>
          <h1 className="mobile-hero-title mobile-text-center" style={{
            ...font.slovic, fontSize: "52px",
            fontWeight: 400, lineHeight: 1.0, color: C.ink,
            marginBottom: "2rem", textTransform: "uppercase",
            letterSpacing: "0.01em",
            fontStyle: "oblique 10deg",
            fontSynthesis: "style",
          }}>
            summoning circle for<br />shared minds
          </h1>

          <p className="mobile-body-text mobile-text-center" style={{
            ...font.serif, fontSize: "1.25rem", fontWeight: 400,
            color: C.muted, maxWidth: 480, lineHeight: 1.75, marginBottom: "3rem",
          }}>
            A terminal-native platform where humans and AI agents <span style={{ color: C.gold }}>share</span> persistent context and work together as a single organizational mind.
          </p>

          <a href="#join" className="mobile-button" style={{
            ...font.mono, fontSize: "0.72rem", letterSpacing: "1.5px",
            display: "inline-block", textTransform: "uppercase",
            background: C.ink, color: C.parchment, border: "none",
            padding: "0.85rem 2.2rem", cursor: "pointer", textDecoration: "none",
            transition: "background 0.2s ease",
          }}>
            Join the Waitlist
          </a>

          <div style={{
            ...font.mono, fontSize: "0.58rem", color: C.warmGray,
            marginTop: "1rem", letterSpacing: "1.5px", textTransform: "uppercase",
          }}>
            Early access &middot; The circle is forming
          </div>
        </div>

        {/* Right side - Wizards Working ASCII art */}
        <div className="mobile-hide" style={{
          flex: "1",
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
          position: "relative",
          zIndex: 1,
        }}>
          <pre
            style={{
              ...font.mono,
              fontSize: "clamp(0.162rem, 0.225vw, 0.27rem)",
              lineHeight: 1.05,
              color: C.muted,
              whiteSpace: "pre",
              margin: 0,
              overflow: "visible",
            }}
          >
            {wizardsWorking}
          </pre>
        </div>
      </div>
    </Container>
  </section>
);

// ─── Section 2: Value Propositions ──────────────────────────────
const ValueProps = () => {
  const cards = [
    {
      title: "UNIFIED SUBSTRATE",
      body: "Production and coordination are not separate activities. They happen in the same environment \u2014 eliminating the boundary between tools for doing work and tools for talking about work.",
      ascii: oneSubstrate,
    },
    {
      title: "CONTEXT GARDENING",
      body: "The overhead of context engineering approaches zero. Context surfaces are pegged to the edges of the organization \u2014 and these edges multiply as the organization interacts.",
      ascii: contextGardening,
    },
    {
      title: "ORGANIZATIONAL LEARNING",
      body: "As the system accumulates, patterns surface from repeated activity and emergent context. Egregore evolves according to the tools, workflows, and coordination patterns of the host organization.",
      ascii: organizationalLearning,
    },
  ];

  return (
    <section className="mobile-section mobile-section-padding" style={{ height: "1000px", padding: "3.5rem 0 6rem", position: "relative", display: "flex", alignItems: "center" }}>
      <Container style={{ position: "relative", zIndex: 1, width: "100%" }}>
        <div className="mobile-value-grid" style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "3.5rem" }}>
          {cards.map((card) => (
            <div key={card.title}>
              {/* ASCII art above the card */}
              <div style={{
                display: "flex",
                justifyContent: "center",
                alignItems: "center",
                marginBottom: "1rem",
              }}>
                <pre style={{
                  ...font.mono,
                  fontSize: "0.06rem",
                  lineHeight: 1.05,
                  color: "#8A8578",
                  whiteSpace: "pre",
                  margin: 0,
                  textAlign: "center",
                }}>
                  {card.ascii}
                </pre>
              </div>

              <div style={{ borderTop: `2px solid ${C.gold}`, paddingTop: "1.5rem" }}>
                <h3 className="mobile-card-title" style={{
                  ...font.mono, fontSize: "0.95rem", fontWeight: 700,
                  color: C.gold, letterSpacing: "2px", marginBottom: "1rem",
                }}>
                  {card.title}
                </h3>
                <p className="mobile-body-text" style={{
                  ...font.serif, fontSize: "1.15rem", color: "#5a5650", lineHeight: 1.75,
                }}>
                  {card.body}
                </p>
              </div>
            </div>
          ))}
        </div>
      </Container>
    </section>
  );
};

// ─── Section 3: Egregoric Intelligence ──────────────────────────
const EgregoricIntelligence = () => {
  return (
    <section className="mobile-section mobile-section-padding" style={{ height: "1000px", padding: "2rem 0 5rem", position: "relative", display: "flex", alignItems: "center" }}>
      <Container style={{ position: "relative", zIndex: 1, maxWidth: "1600px", width: "100%" }}>
        <Divider />
        <div className="mobile-flex-col mobile-gap-small" style={{
          display: "flex",
          alignItems: "center",
          gap: "5rem",
          justifyContent: "space-between",
        }}>
          {/* Left side - Text content */}
          <div className="mobile-text-center" style={{ flex: "1", maxWidth: "700px" }}>
            <h2 className="mobile-section-title" style={{
              ...font.gothic, fontSize: "3rem", color: C.crimson,
              marginBottom: "1.5rem", lineHeight: 1.2,
            }}>
              Egregoric Intelligence
            </h2>
            <p className="mobile-body-text" style={{
              ...font.serif, fontSize: "1.25rem",
              color: C.muted, lineHeight: 1.75,
            }}>
              Production requires coordination. Coordination generates context. Context compounds into organizational learning &mdash; and feeds back into production. A shared substrate makes every coordination act context-rich &mdash; AI workflows operate with full organizational awareness.
            </p>
          </div>

          {/* Right side - Egregoric Intelligence ASCII art */}
          <div className="mobile-hide" style={{
            flex: "1",
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            position: "relative",
          }}>
            <pre
              style={{
                ...font.mono,
                fontSize: "clamp(0.09rem, 0.125vw, 0.15rem)",
                lineHeight: 1.05,
                color: C.muted,
                whiteSpace: "pre",
                margin: 0,
                overflow: "visible",
              }}
            >
              {egregoricIntelligence}
            </pre>
          </div>
        </div>
      </Container>
    </section>
  );
};

// ─── Section 3: See It Work — Slash Command Demo ────────────────
const COMMANDS = [
  {
    cmd: "/activity",
    label: "activity",
    lines: [
      { t: "", s: "blank" },
      { t: "EGREGORE \u25C6 ACTIVITY                    VESPER \u00B7 FEB 07", s: "header" },
      { t: "", s: "blank" },
      { t: "RECENT SESSIONS", s: "section" },
      { t: "  TODAY      Egregore.md architecture \u2014 soul.md survey", s: "line" },
      { t: "  YESTERDAY  Three-layer structure: declared,", s: "line" },
      { t: "             constitutional, emergent", s: "dim" },
      { t: "  FEB 05     Graph seed schema with Cael", s: "line" },
      { t: "  FEB 04     Reviewed Maren\u2019s ritual cadence proposal", s: "line" },
      { t: "  FEB 03     Membrane permeability model", s: "line" },
      { t: "", s: "blank" },
      { t: "TEAM (LAST 7 DAYS)", s: "section" },
      { t: "  TODAY      Amendment mechanics for egregore.md    WREN", s: "line" },
      { t: "  TODAY      Tonal grammar \u2014 egregore voice         RUNE", s: "line" },
      { t: "  YESTERDAY  Weekly synthesis ritual design         MAREN", s: "line" },
      { t: "  YESTERDAY  Ontology seeding \u2014 312 nodes          CAEL", s: "line" },
      { t: "  FEB 05     Epistemic posture under uncertainty    WREN", s: "line" },
      { t: "  FEB 04     Sigil as membrane \u2014 visual threshold   RUNE", s: "line" },
      { t: "  FEB 03     Edge properties for transformation    CAEL", s: "line" },
      { t: "", s: "blank" },
      { t: "ACTIVE QUESTS", s: "section" },
      { t: "  EGREGORE-SOUL     Draft and ratify egregore.md   5  9", s: "line" },
      { t: "  SEED-ONTOLOGY     Bootstrap graph from traces    2  4", s: "line" },
      { t: "  RITUAL-DESIGN     Collective cadences + triggers 1  3", s: "line" },
      { t: "", s: "blank" },
      { t: "  4 more quests \u2014 /quest to see all", s: "dim" },
    ],
  },
  {
    cmd: "/handoff",
    label: "handoff",
    lines: [
      { t: "", s: "blank" },
      { t: "EGREGORE \u25C6 HANDOFF                     VESPER \u2192 WREN", s: "header" },
      { t: "", s: "blank" },
      { t: "EGREGORE.MD ARCHITECTURE RESEARCH (3H 10M)", s: "section" },
      { t: "", s: "blank" },
      { t: "  Surveyed soul.md landscape \u2014 OpenClaw, Claude", s: "line" },
      { t: "  Diary, DAO constitutions, Arbitrum hash pattern.", s: "line" },
      { t: "  Mapped design space for org identity documents", s: "line" },
      { t: "  backed by knowledge graph.", s: "line" },
      { t: "", s: "blank" },
      { t: "FINDINGS", s: "section" },
      { t: "  \u2192 Three-layer structure: declared (human-authored),", s: "line" },
      { t: "    constitutional (governance), emergent (from graph)", s: "line" },
      { t: "  \u2192 Declared + constitutional in repo \u2014 changes are", s: "line" },
      { t: "    governance events. Emergent in memory.", s: "line" },
      { t: "  \u2192 Constitutional hash (SHA-256) for integrity", s: "line" },
      { t: "  \u2192 Preamble must stay under 50 lines", s: "line" },
      { t: "", s: "blank" },
      { t: "OPEN FOR WREN", s: "section" },
      { t: "  \u2192 Amendment mechanics: who modifies which layer?", s: "line" },
      { t: "  \u2192 Guardian function may not need a separate agent", s: "line" },
      { t: "    \u2014 session infrastructure is already the guardian", s: "line" },
      { t: "", s: "blank" },
      { t: "  \u2713 6 findings \u00B7 2 security decisions \u00B7 1 artifact", s: "accent" },
      { t: "  \u2713 Graph: Session \u2192 Research(soul-md-landscape)", s: "accent" },
      { t: "  \u2713 Wren notified \u2014 ready for implementation spec", s: "accent" },
    ],
  },
  {
    cmd: "/ask",
    label: "ask",
    lines: [
      { t: "", s: "blank" },
      { t: "EGREGORE \u25C6 ASK                         WREN \u2192 CAEL", s: "header" },
      { t: "", s: "blank" },
      { t: "  Wren is drafting the implementation spec and needs", s: "dim" },
      { t: "  graph-level constraints before committing.", s: "dim" },
      { t: "", s: "blank" },
      { t: "CONTEXT", s: "section" },
      { t: "  Vesper \u2192 Wren, Feb 07: Three-layer structure \u2014", s: "line" },
      { t: "    declared, constitutional, emergent.", s: "line" },
      { t: "  Cael, Feb 05: Ontology seeding \u2014 312 nodes,", s: "line" },
      { t: "    edges carry weight, authorship, and decay.", s: "line" },
      { t: "", s: "blank" },
      { t: "QUESTIONS", s: "section" },
      { t: "", s: "blank" },
      { t: "  1. Can the graph enforce the cascade model \u2014", s: "line" },
      { t: "     org ceiling individual configs can\u2019t exceed?", s: "line" },
      { t: "", s: "blank" },
      { t: "     \u25CB Yes, permission layers already scoped", s: "option" },
      { t: "     \u25CB Partially \u2014 needs validation on write", s: "option" },
      { t: "     \u25CB Not yet, requires schema changes", s: "option" },
      { t: "", s: "blank" },
      { t: "  2. Can you diff two graph states reliably?", s: "line" },
      { t: "", s: "blank" },
      { t: "     \u25CB Yes, snapshots are versioned", s: "option" },
      { t: "     \u25CB Nodes yes, edge weights not yet", s: "option" },
      { t: "     \u25CB Would need to build this", s: "option" },
      { t: "", s: "blank" },
      { t: "  3. How should emergent content get selected", s: "line" },
      { t: "     into the 50-line preamble budget?", s: "line" },
      { t: "", s: "blank" },
      { t: "     [ \u258C                                       ]", s: "input" },
    ],
  },
  {
    cmd: "/reflect",
    label: "reflect",
    lines: [
      { t: "", s: "blank" },
      { t: "EGREGORE \u25C6 REFLECT                           FEB 11", s: "header" },
      { t: "", s: "blank" },
      { t: "  Vesper\u2019s architecture research, Wren\u2019s implementation", s: "line" },
      { t: "  work, and Rune\u2019s sigil design are converging on a", s: "line" },
      { t: "  shared constraint across three workstreams:", s: "line" },
      { t: "", s: "blank" },
      { t: "  Vesper: Preamble must stay under 50 lines \u2014 the", s: "quote" },
      { t: "    egregore.md can\u2019t say everything. It selects.", s: "quote" },
      { t: "  Wren: Too many amendment rules and the system", s: "quote" },
      { t: "    becomes brittle. Must protect against", s: "quote" },
      { t: "    over-specification.", s: "quote" },
      { t: "  Rune: The sigil carries ambiguity by design \u2014", s: "quote" },
      { t: "    if it resolves fully, it stops working.", s: "quote" },
      { t: "", s: "blank" },
      { t: "  Same constraint, three directions: the egregore.md", s: "line" },
      { t: "  must be compressed enough to remain functional and", s: "line" },
      { t: "  open enough to remain alive. Selection pressure and", s: "line" },
      { t: "  interpretive room are the same design requirement.", s: "line" },
      { t: "", s: "blank" },
      { t: "  Implication for Quest(egregore-soul): the three-", s: "accent" },
      { t: "  layer architecture needs a compression principle", s: "accent" },
      { t: "  governing what the declared layer includes.", s: "accent" },
      { t: "  Currently unspecified in Wren\u2019s draft.", s: "accent" },
      { t: "", s: "blank" },
      { t: "  Vesper, Feb 07 \u00B7 Wren, Feb 09 \u00B7 Rune, Feb 04", s: "dim" },
      { t: "  9 sessions \u00B7 3 people \u00B7 2 quests", s: "dim" },
    ],
  },
];

const THINKING_MESSAGES = {
  "/activity": [
    "\u25C6 Loading session graph",
    "\u25C6 Scanning 5 vessels, 14 active sessions",
    "\u25C6 Resolving quest dependencies",
  ],
  "/handoff": [
    "\u25C6 Serializing session context",
    "\u25C6 Extracting decisions and open threads",
    "\u25C6 Preparing transfer for Wren",
  ],
  "/ask": [
    "\u25C6 Resolving context intersection",
    "\u25C6 Vesper\u2019s handoff \u2192 Wren\u2019s draft \u2192 Cael\u2019s schema",
    "\u25C6 Generating contextual questions",
  ],
  "/reflect": [
    "\u25C6 Traversing knowledge graph",
    "\u25C6 Cross-referencing 9 sessions, 3 workstreams",
    "\u25C6 Pattern detected \u2014 convergence across members",
    "\u25C6 Synthesizing",
  ],
};

const TERM_STYLE_MAP = {
  header: { color: "#c8a55a", fontWeight: 700, letterSpacing: "0.03em" },
  section: { color: "#c8a55a", fontWeight: 600, letterSpacing: "0.05em", fontSize: "0.78rem" },
  line: { color: "#d4d0c8" },
  dim: { color: "#6b6860" },
  accent: { color: "#8b9e7a" },
  quote: { color: "#a89e8c", fontStyle: "italic" },
  option: { color: "#8a8070" },
  input: { color: "#555049" },
  blank: { color: "transparent", userSelect: "none" },
};

function ThinkingIndicator({ messages, active, onDone }) {
  const [step, setStep] = useState(0);
  const [dots, setDots] = useState("");

  useEffect(() => {
    if (!active) { setStep(0); setDots(""); return; }
    setStep(0);
    let s = 0;
    const stepInterval = setInterval(() => {
      s++;
      if (s >= messages.length) {
        clearInterval(stepInterval);
        setTimeout(() => onDone(), 350);
        return;
      }
      setStep(s);
    }, 450);
    return () => clearInterval(stepInterval);
  }, [active, onDone, messages.length]);

  useEffect(() => {
    if (!active) return;
    const dotInterval = setInterval(() => {
      setDots((d) => (d.length >= 3 ? "" : d + "."));
    }, 280);
    return () => clearInterval(dotInterval);
  }, [active]);

  if (!active) return null;

  return (
    <div style={{ padding: "4px 0" }}>
      {messages.slice(0, step + 1).map((msg, i) => (
        <div key={i} style={{
          color: "#6b6860", fontSize: "0.78rem",
          fontFamily: "'Berkeley Mono', 'JetBrains Mono', 'Fira Code', monospace",
          lineHeight: "1.5em", whiteSpace: "pre",
          opacity: i === step ? 0.85 : 0.35,
          transition: "opacity 0.3s",
        }}>
          {"  "}{msg}{i === step ? dots : ""}
        </div>
      ))}
    </div>
  );
}

function TerminalLine({ text, style, delay, visible }) {
  const [show, setShow] = useState(false);
  useEffect(() => {
    if (!visible) { setShow(false); return; }
    const t = setTimeout(() => setShow(true), delay);
    return () => clearTimeout(t);
  }, [delay, visible]);

  if (!show) return <div style={{ height: style === "blank" ? "0.45em" : "1.15em" }} />;
  return (
    <div style={{
      ...TERM_STYLE_MAP[style],
      height: style === "blank" ? "0.45em" : "auto",
      lineHeight: "1.15em", whiteSpace: "pre",
      fontFamily: "'Berkeley Mono', 'JetBrains Mono', 'Fira Code', monospace",
      fontSize: "0.78rem",
      transition: "opacity 0.2s ease",
      opacity: show ? 1 : 0,
    }}>
      {text}
    </div>
  );
}

const PHASE = { IDLE: 0, TYPING: 1, THINKING: 2, RENDERING: 3 };

const SeeItWork = () => {
  const [active, setActive] = useState(0);
  const [phase, setPhase] = useState(PHASE.IDLE);
  const [runKey, setRunKey] = useState(0);
  const [typedText, setTypedText] = useState("");
  const [typingDone, setTypingDone] = useState(false);
  const scrollRef = useRef(null);
  const typeRef = useRef(null);
  const sectionRef = useRef(null);
  const [hasStarted, setHasStarted] = useState(false);

  const cmd = COMMANDS[active];

  const startSequence = useCallback((i) => {
    if (typeRef.current) clearInterval(typeRef.current);
    setActive(i);
    setRunKey((k) => k + 1);
    setPhase(PHASE.TYPING);
    setTypedText("");
    setTypingDone(false);
    if (scrollRef.current) scrollRef.current.scrollTop = 0;

    const text = COMMANDS[i].cmd;
    let ci = 0;
    const delay = setTimeout(() => {
      typeRef.current = setInterval(() => {
        ci++;
        setTypedText(text.slice(0, ci));
        if (ci >= text.length) {
          clearInterval(typeRef.current);
          setTypingDone(true);
        }
      }, 50);
    }, 200);

    return () => { clearTimeout(delay); clearInterval(typeRef.current); };
  }, []);

  useEffect(() => {
    if (typingDone && phase === PHASE.TYPING) {
      const t = setTimeout(() => setPhase(PHASE.THINKING), 350);
      return () => clearTimeout(t);
    }
  }, [typingDone, phase]);

  const handleThinkDone = useCallback(() => {
    setPhase(PHASE.RENDERING);
  }, []);

  useEffect(() => {
    if (hasStarted) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setHasStarted(true);
          startSequence(0);
          observer.disconnect();
        }
      },
      { threshold: 0.3 }
    );
    if (sectionRef.current) observer.observe(sectionRef.current);
    return () => observer.disconnect();
  }, [hasStarted, startSequence]);

  return (
    <section ref={sectionRef} style={{ height: "1000px", padding: "0", background: C.ink, position: "relative", overflow: "hidden", display: "flex", alignItems: "center" }}>
      {/* Terminal Frame Background */}
      <div style={{
        position: "absolute",
        top: "50%",
        left: "50%",
        transform: "translate(-50%, -50%)",
        pointerEvents: "none",
        opacity: 0.5,
        width: "1440px",
        height: "890px",
        overflow: "hidden",
      }}>
        <pre style={{
          ...font.mono,
          fontSize: "5.83px",
          lineHeight: 1.05,
          color: "#ffffff",
          whiteSpace: "pre",
          margin: 0,
          textAlign: "center",
        }}>
          {terminalFrame}
        </pre>
      </div>

      <Container style={{ position: "relative", zIndex: 1, width: "100%" }}>
        <div style={{ maxWidth: 700, margin: "0 auto" }}>
          <div style={{
            background: C.termBg, borderRadius: "10px",
            border: "1px solid #252320", overflow: "hidden",
            boxShadow: "0 2px 80px rgba(200, 165, 90, 0.03), 0 16px 48px rgba(0,0,0,0.55)",
            fontFamily: "'Berkeley Mono', 'JetBrains Mono', 'Fira Code', monospace",
          }}>
            <div style={{ display: "flex", alignItems: "center", padding: "9px 13px 0", gap: 5 }}>
              <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#2a2723" }} />
              <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#2a2723" }} />
              <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#2a2723" }} />
              <span style={{ marginLeft: "auto", color: "#332f2a", fontSize: "0.58rem", letterSpacing: "0.12em" }}>
                EGREGORE v0.1
              </span>
            </div>

            <div style={{ display: "flex", padding: "8px 13px 0", borderBottom: "1px solid #1a1916" }}>
              {COMMANDS.map((c, i) => (
                <button key={c.cmd} onClick={() => startSequence(i)} style={{
                  background: "none", border: "none",
                  borderBottom: active === i ? "1px solid #c8a55a" : "1px solid transparent",
                  color: active === i ? "#c8a55a" : "#44413c",
                  fontFamily: "'Berkeley Mono', 'JetBrains Mono', monospace",
                  fontSize: "0.72rem", letterSpacing: "0.06em",
                  padding: "4px 9px 6px", cursor: "pointer",
                  transition: "color 0.2s, border-color 0.2s",
                  fontWeight: active === i ? 600 : 400,
                }}>
                  /{c.label}
                </button>
              ))}
            </div>

            <div ref={scrollRef} style={{
              padding: "10px 14px 6px", height: 390,
              overflowY: "auto", overflowX: "hidden",
              scrollbarWidth: "thin", scrollbarColor: "#2a2824 transparent",
            }}>
              <div key={`${active}-${runKey}`}>
                <div style={{ display: "flex", alignItems: "center", gap: 7, height: "1.3em", marginBottom: 1 }}>
                  <span style={{ color: "#c8a55a", fontSize: "0.82rem" }}>{"\u276F"}</span>
                  <span style={{
                    color: "#d4d0c8", fontSize: "0.78rem",
                    fontFamily: "'Berkeley Mono', 'JetBrains Mono', 'Fira Code', monospace",
                  }}>
                    {phase >= PHASE.TYPING ? typedText : ""}
                    {phase === PHASE.TYPING && !typingDone && (
                      <span style={{
                        display: "inline-block", width: 5, height: 12,
                        background: "#c8a55a", marginLeft: 1,
                        verticalAlign: "text-bottom",
                        animation: "blink 0.7s step-end infinite",
                      }} />
                    )}
                  </span>
                </div>

                {phase === PHASE.THINKING && (
                  <ThinkingIndicator
                    messages={THINKING_MESSAGES[cmd.cmd]}
                    active={true}
                    onDone={handleThinkDone}
                  />
                )}

                {phase === PHASE.RENDERING &&
                  cmd.lines.map((line, i) => (
                    <TerminalLine
                      key={`${runKey}-${i}`}
                      text={line.t}
                      style={line.s}
                      delay={i * 28}
                      visible={true}
                    />
                  ))}
              </div>
            </div>

            <div style={{
              borderTop: "1px solid #1a1916", padding: "6px 14px",
              display: "flex", alignItems: "center",
            }}>
              <span style={{
                color: "#2e2b26", fontSize: "0.58rem", letterSpacing: "0.1em",
                fontFamily: "'Berkeley Mono', 'JetBrains Mono', monospace",
              }}>
                dev/main &middot; memory synced &middot; {"\u25C6"}
              </span>
            </div>
          </div>
        </div>
      </Container>
    </section>
  );
};

// ─── Section 4: The Session Cycle ───────────────────────────────
const SessionCycle = () => {
  const commands = [
    { cmd: "/session", desc: "Connect an existing repo to seed the egregore with context, or start from scratch." },
    { cmd: "/invite", desc: "Bring humans and AI agents into the magic circle." },
    { cmd: "/handoff", desc: "Transfer full context between any participants \u2014 zero switching cost." },
    { cmd: "/activity", desc: "A glance at the organizational mind: decisions, outputs, sessions." },
    { cmd: "/reflect", desc: "The egregore reviews its own patterns, gaps, and emergent connections." },
  ];

  const cycleSteps = [
    { label: "ORIENT", sub: "/activity", angle: -90 },
    { label: "WORK", sub: "/egregore", angle: -18 },
    { label: "PERSIST", sub: "/save", angle: 54 },
    { label: "HANDOFF", sub: "/handoff", angle: 126 },
    { label: "REFLECT", sub: "/reflect", angle: 198 },
  ];

  const [hovered, setHovered] = useState(null);

  // Compute node positions
  const r = 125, cx = 160, cy = 160;
  const nodes = cycleSteps.map((step) => ({
    ...step,
    x: cx + r * Math.cos((step.angle * Math.PI) / 180),
    y: cy + r * Math.sin((step.angle * Math.PI) / 180),
  }));

  // Outer edges (pentagon) and inner edges (star)
  const outerEdges = nodes.map((_, i) => [i, (i + 1) % 5]);
  const starEdges = nodes.map((_, i) => [i, (i + 2) % 5]);

  return (
    <section className="mobile-section mobile-section-padding" style={{ height: "1000px", padding: "3rem 0 4rem", position: "relative", display: "flex", alignItems: "center" }}>
      <Container style={{ position: "relative", zIndex: 1, maxWidth: "1400px", width: "100%" }}>
        <Divider />
        <SectionLabel>How it works</SectionLabel>
        <h2 style={{
          ...font.serif, fontSize: "2.8rem", fontWeight: 400,
          textAlign: "center", color: C.ink, marginBottom: "0.8rem", lineHeight: 1.2,
        }}>
          The Session Cycle
        </h2>
        <p style={{
          ...font.serif, fontSize: "1.2rem", textAlign: "center",
          color: C.muted, maxWidth: 600, margin: "0 auto 3.5rem", lineHeight: 1.7,
        }}>
          Every interaction strengthens the shared context. The egregore remembers so individuals don't have to.
        </p>

        <div className="mobile-session-grid" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "4rem", alignItems: "center" }}>
          <div>
            {commands.map((c, i) => (
              <div key={i} style={{
                display: "grid", gridTemplateColumns: "130px 1fr", gap: "2rem",
                padding: "1.3rem 0",
                borderBottom: i < commands.length - 1 ? `1px solid ${C.warmGray}` : "none",
                alignItems: "baseline",
              }}>
                <code style={{ ...font.mono, fontSize: "0.92rem", color: C.crimson, fontWeight: 700 }}>
                  {c.cmd}
                </code>
                <p style={{ ...font.serif, fontSize: "1.1rem", color: "#5a5650", lineHeight: 1.6 }}>
                  {c.desc}
                </p>
              </div>
            ))}
          </div>

          <div style={{ display: "flex", justifyContent: "center", alignItems: "center" }}>
            <div style={{ position: "relative", width: 320, height: 320 }}>
              {/* Center label */}
              <div style={{
                position: "absolute", top: "50%", left: "50%",
                transform: "translate(-50%, -50%)", textAlign: "center",
                transition: "opacity 0.3s",
                opacity: hovered !== null ? 0.3 : 1,
              }}>
                <div style={{
                  ...font.mono, fontSize: "0.55rem", letterSpacing: "2px",
                  color: C.muted, textTransform: "uppercase", lineHeight: 1.6,
                }}>
                  Knowledge<br />Graph +<br />Git Memory
                </div>
              </div>

              <svg viewBox="0 0 320 320" style={{ position: "absolute", top: 0, left: 0, width: "100%", height: "100%" }}>
                <defs>
                  <marker id="arrow" viewBox="0 0 10 8" refX="8" refY="4"
                    markerWidth="6" markerHeight="5" orient="auto-start-reverse">
                    <path d="M 0 0 L 10 4 L 0 8 z" fill="rgba(200,165,90,0.4)" />
                  </marker>
                  <marker id="arrowHover" viewBox="0 0 10 8" refX="8" refY="4"
                    markerWidth="6" markerHeight="5" orient="auto-start-reverse">
                    <path d="M 0 0 L 10 4 L 0 8 z" fill="rgba(200,165,90,0.8)" />
                  </marker>
                </defs>
                {/* Outer pentagon edges */}
                {outerEdges.map(([a, b], i) => {
                  const highlighted = hovered !== null && (hovered === a || hovered === b);
                  return (
                    <line key={`o${i}`}
                      x1={nodes[a].x} y1={nodes[a].y} x2={nodes[b].x} y2={nodes[b].y}
                      stroke={highlighted ? "rgba(122,15,27,0.6)" : "rgba(122,15,27,0.2)"}
                      strokeWidth={highlighted ? 1.8 : 1}
                      style={{ transition: "stroke 0.3s, stroke-width 0.3s" }}
                    />
                  );
                })}
                {/* Inner star edges — bolder with arrowheads */}
                {starEdges.map(([a, b], i) => {
                  const highlighted = hovered !== null && (hovered === a || hovered === b);
                  return (
                    <line key={`s${i}`}
                      x1={nodes[a].x} y1={nodes[a].y} x2={nodes[b].x} y2={nodes[b].y}
                      stroke={highlighted ? "rgba(200,165,90,0.7)" : "rgba(200,165,90,0.22)"}
                      strokeWidth={highlighted ? 1.8 : 1.2}
                      markerEnd={highlighted ? "url(#arrowHover)" : "url(#arrow)"}
                      style={{ transition: "stroke 0.3s, stroke-width 0.3s" }}
                    />
                  );
                })}
                {/* Node dots */}
                {nodes.map((n, i) => {
                  const isHovered = hovered === i;
                  return (
                    <g key={i}>
                      {isHovered && (
                        <circle cx={n.x} cy={n.y} r={12}
                          fill="none" stroke="rgba(122,15,27,0.15)" strokeWidth="1"
                          style={{ transition: "opacity 0.3s" }}
                        />
                      )}
                      <circle cx={n.x} cy={n.y} r={isHovered ? 6 : 4}
                        fill={C.crimson}
                        style={{ transition: "r 0.2s", cursor: "pointer" }}
                      />
                    </g>
                  );
                })}
              </svg>

              {/* Labels with hover zones */}
              {nodes.map((node, i) => {
                const labelR = 158;
                const lx = cx + labelR * Math.cos((node.angle * Math.PI) / 180);
                const ly = cy + labelR * Math.sin((node.angle * Math.PI) / 180);
                const isHovered = hovered === i;
                return (
                  <div key={i}
                    onMouseEnter={() => setHovered(i)}
                    onMouseLeave={() => setHovered(null)}
                    style={{
                      position: "absolute", left: lx, top: ly,
                      transform: "translate(-50%, -50%)", textAlign: "center",
                      cursor: "pointer", padding: "6px 10px",
                      transition: "transform 0.2s",
                    }}
                  >
                    <div style={{
                      ...font.mono, fontSize: "0.62rem", fontWeight: 700,
                      color: isHovered ? C.crimson : C.ink,
                      letterSpacing: "1.5px",
                      transition: "color 0.2s",
                    }}>
                      {node.label}
                    </div>
                    <div style={{
                      ...font.mono, fontSize: "0.55rem",
                      color: isHovered ? C.gold : C.crimson,
                      transition: "color 0.2s",
                    }}>
                      {node.sub}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </Container>
    </section>
  );
};

// ─── Wizards Banner Section ─────────────────────────────────────
const WizardsBanner = () => {
  return (
    <section style={{ height: "1000px", padding: "3rem 0", background: C.parchment, position: "relative", overflow: "hidden", display: "flex", alignItems: "center" }}>
      <Container style={{ position: "relative", zIndex: 1, width: "100%" }}>
        <div style={{
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
        }}>
          <pre style={{
            ...font.mono,
            fontSize: "clamp(0.2rem, 0.3vw, 0.4rem)",
            lineHeight: 1.05,
            color: C.ink,
            whiteSpace: "pre",
            margin: 0,
            textAlign: "center",
          }}>
            {astro}
          </pre>
        </div>
      </Container>
    </section>
  );
};

// ─── Section 5: Research ─────────────────────────────────────
const Research = () => {
  const featured = POSTS.filter((p) => p.featured);
  return (
    <section id="research" style={{ height: "1000px", padding: "3rem 0 5rem", display: "flex", alignItems: "center" }}>
      <Container style={{ width: "100%" }}>
        <Divider />
        <SectionLabel>Research</SectionLabel>
        <h2 style={{
          ...font.serif, fontSize: "2.8rem", fontWeight: 400,
          textAlign: "center", color: C.ink, marginBottom: "0.8rem", lineHeight: 1.2,
        }}>
          From the field.
        </h2>
        <p style={{
          ...font.serif, fontSize: "1.2rem", textAlign: "center",
          color: C.muted, maxWidth: 600, margin: "0 auto 3rem", lineHeight: 1.7,
        }}>
          Dispatches on shared cognition, coordination infrastructure, and what emerges when organizations develop memory.
        </p>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "3rem" }}>
          {featured.map((post) => (
            <Link key={post.slug} to={`/research/${post.slug}`} style={{
              textDecoration: "none", color: "inherit",
              border: `1px solid ${C.warmGray}`, padding: "2.2rem 2rem",
              display: "flex", flexDirection: "column",
              transition: "border-color 0.2s, transform 0.2s",
            }}
              onMouseEnter={(e) => { e.currentTarget.style.borderColor = C.gold; e.currentTarget.style.transform = "translateY(-2px)"; }}
              onMouseLeave={(e) => { e.currentTarget.style.borderColor = C.warmGray; e.currentTarget.style.transform = "translateY(0)"; }}
            >
              <div style={{
                ...font.mono, fontSize: "0.65rem", letterSpacing: "2px",
                textTransform: "uppercase", color: C.gold, marginBottom: "0.8rem",
              }}>
                {post.tag}
              </div>
              <h3 style={{
                ...font.serif, fontSize: "1.35rem", fontWeight: 600,
                color: C.ink, marginBottom: "0.75rem", lineHeight: 1.3,
              }}>
                {post.title}
              </h3>
              <p style={{
                ...font.serif, fontSize: "1.05rem", color: C.muted,
                lineHeight: 1.65, flex: 1,
              }}>
                {post.excerpt}
              </p>
              <div style={{
                ...font.mono, fontSize: "0.65rem", color: C.warmGray,
                letterSpacing: "1px", marginTop: "1.2rem",
              }}>
                {post.date}
              </div>
            </Link>
          ))}
        </div>

        <div style={{ textAlign: "center", marginTop: "2.5rem" }}>
          <Link to="/research" style={{
            ...font.mono, fontSize: "0.67rem", letterSpacing: "1.5px",
            textTransform: "uppercase", color: C.crimson,
            textDecoration: "none", borderBottom: `1px solid ${C.crimson}`,
            paddingBottom: "2px",
          }}>
            View all research
          </Link>
        </div>
      </Container>
    </section>
  );
};

// ─── Monster Banner Section ─────────────────────────────────────
const MonsterBanner = () => {
  return (
    <section style={{ height: "1000px", padding: "1.4rem 0", background: "#1A1714", position: "relative", overflow: "hidden", display: "flex", alignItems: "center" }}>
      {/* Left ASCII decoration */}
      <div style={{
        position: "absolute",
        left: "0",
        top: "50%",
        transform: "translateY(-50%)",
        pointerEvents: "none",
      }}>
        <pre style={{
          ...font.mono,
          fontSize: "0.105rem",
          lineHeight: 1.05,
          color: "#ffffff",
          whiteSpace: "pre",
          margin: 0,
        }}>
          {monsterOrnamentLeft}
        </pre>
      </div>

      {/* Right ASCII decoration */}
      <div style={{
        position: "absolute",
        right: "0",
        top: "50%",
        transform: "translateY(-50%)",
        pointerEvents: "none",
      }}>
        <pre style={{
          ...font.mono,
          fontSize: "0.105rem",
          lineHeight: 1.05,
          color: "#ffffff",
          whiteSpace: "pre",
          margin: 0,
        }}>
          {monsterOrnamentRight}
        </pre>
      </div>

      {/* Center monster ASCII */}
      <Container style={{ position: "relative", zIndex: 1, width: "100%" }}>
        <div style={{
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
        }}>
          <pre style={{
            ...font.mono,
            fontSize: "clamp(0.06825rem, 0.1025vw, 0.1365rem)",
            lineHeight: 1.05,
            color: "#ffffff",
            whiteSpace: "pre",
            margin: 0,
            textAlign: "center",
          }}>
            {egregoreMonster}
          </pre>
        </div>
      </Container>
    </section>
  );
};

// ─── Section 6: CTA ─────────────────────────────────────────────
const API_URL = import.meta.env.VITE_API_URL || "https://egregore-production-55f2.up.railway.app";

const WaitlistCTA = () => {
  const [form, setForm] = useState({ name: "", email: "", source: "" });
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  const handleSubmit = async () => {
    if (!form.name || !form.email || !form.source) return;
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch(`${API_URL}/api/admin/waitlist`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(form),
      });
      if (!res.ok) throw new Error("Failed to submit");
      setSubmitted(true);
    } catch {
      setError("Something went wrong. Try again.");
    } finally {
      setSubmitting(false);
    }
  };

  const inputStyle = {
    ...font.mono, fontSize: "0.78rem",
    background: "transparent", border: "none",
    borderBottom: "1px solid rgba(244,241,234,0.2)",
    color: C.parchment, padding: "0.6rem 0", width: "100%",
    outline: "none", letterSpacing: "0.5px",
  };

  const labelStyle = {
    ...font.mono, fontSize: "0.58rem", letterSpacing: "2.5px",
    textTransform: "uppercase", color: "rgba(244,241,234,0.3)",
    marginBottom: "0.3rem", display: "block",
  };

  return (
    <footer id="join" className="mobile-section mobile-section-padding" style={{ height: "1000px", background: C.ink, color: C.parchment, padding: "6rem 0 3rem", position: "relative", overflow: "hidden", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div className="mobile-flex-col" style={{ maxWidth: 1700, margin: "0 auto", display: "flex", alignItems: "center", justifyContent: "center", gap: "3rem", padding: "0 3rem" }}>
        {/* Left ASCII decoration */}
        <div className="mobile-hide" style={{ flex: "0 0 auto" }}>
          <pre style={{
            ...font.mono,
            fontSize: "0.128rem",
            lineHeight: 1.05,
            color: "#ffffff",
            whiteSpace: "pre",
            margin: 0,
          }}>
            {footerFlower}
          </pre>
        </div>

        {/* Center form content */}
        <Container style={{ maxWidth: 550, position: "relative", zIndex: 1, flex: "0 0 auto" }}>
        {!submitted ? (
          <>
            <div style={{ textAlign: "center", marginBottom: "3rem" }}>
              <div style={{ width: 12, height: 12, background: C.gold, transform: "rotate(45deg)", margin: "0 auto 2rem" }} />
              <h2 style={{ ...font.serif, fontSize: "2.6rem", fontWeight: 400, marginBottom: "0.75rem", lineHeight: 1.2 }}>
                The circle is forming.
              </h2>
              <p style={{ ...font.mono, fontSize: "0.88rem", color: "rgba(244,241,234,0.45)", lineHeight: 1.6 }}>
                Egregore is in early access. Speak your name and intent.
              </p>
            </div>

            <div>
              <div style={{ marginBottom: "1.8rem" }}>
                <label style={labelStyle}>Name</label>
                <input type="text" value={form.name}
                  onChange={(e) => setForm({ ...form, name: e.target.value })}
                  className="mobile-input"
                  style={inputStyle} />
              </div>
              <div style={{ marginBottom: "1.8rem" }}>
                <label style={labelStyle}>Email</label>
                <input type="email" value={form.email}
                  onChange={(e) => setForm({ ...form, email: e.target.value })}
                  className="mobile-input"
                  style={inputStyle} />
              </div>
              <div style={{ marginBottom: "2.5rem" }}>
                <label style={labelStyle}>Intent</label>
                <textarea value={form.source}
                  onChange={(e) => setForm({ ...form, source: e.target.value })}
                  rows={2}
                  className="mobile-input"
                  style={{ ...inputStyle, resize: "none", fontFamily: font.mono.fontFamily }}
                  placeholder="What do you want to use Egregore for?" />
              </div>
              {error && (
                <div style={{ ...font.mono, fontSize: "0.68rem", color: C.crimson, marginBottom: "1rem", textAlign: "center" }}>
                  {error}
                </div>
              )}
              <button onClick={handleSubmit} disabled={submitting} className="mobile-button" style={{
                ...font.mono, fontSize: "0.7rem", letterSpacing: "2px",
                textTransform: "uppercase", width: "100%",
                background: submitting ? C.muted : C.parchment, color: C.ink, border: "none",
                padding: "0.9rem 1.5rem", cursor: submitting ? "wait" : "pointer",
                transition: "opacity 0.2s",
              }}>
                {submitting ? "Submitting..." : "Join the Circle"}
              </button>
            </div>
          </>
        ) : (
          <div style={{ textAlign: "center", padding: "4rem 0" }}>
            <div style={{ ...font.serif, fontSize: "1.6rem", marginBottom: "1.2rem", color: C.gold }}>
              {"\u2726"} Received.
            </div>
            <p style={{ ...font.mono, fontSize: "0.8rem", color: "rgba(244,241,234,0.45)", lineHeight: 1.7 }}>
              You'll know when the gates open.
            </p>
          </div>
        )}

        <div style={{
          ...font.mono, fontSize: "0.55rem", color: "rgba(244,241,234,0.2)",
          borderTop: "1px solid rgba(244,241,234,0.08)",
          paddingTop: "2rem", marginTop: "4rem",
          display: "flex", justifyContent: "space-between", letterSpacing: "1px",
        }}>
          <span>Egregore Systems</span>
          <span>MMXXVI</span>
          <span>Berlin / The Graph</span>
        </div>
      </Container>

        {/* Right ASCII decoration */}
        <div className="mobile-hide" style={{ flex: "0 0 auto" }}>
          <pre style={{
            ...font.mono,
            fontSize: "0.128rem",
            lineHeight: 1.05,
            color: "#ffffff",
            whiteSpace: "pre",
            margin: 0,
          }}>
            {footerStar}
          </pre>
        </div>
      </div>
    </footer>
  );
};

// ─── Egregore Text Banner ────────────────────────────────────────
const EgregoreTextBanner = () => {
  return null;
};

// ─── App ────────────────────────────────────────────────────────
export default function App() {
  return (
    <div style={{ background: C.parchment, color: C.ink, ...font.serif, lineHeight: 1.6, overflowX: "hidden" }}>
      <Navigation />
      <Hero />
      <EgregoricIntelligence />
      <ValueProps />
      <SeeItWork />
      <MonsterBanner />
      <EgregoreTextBanner />
      <SessionCycle />
      <WizardsBanner />
      <Research />
      <WaitlistCTA />
    </div>
  );
}
