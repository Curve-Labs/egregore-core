import satori from "satori";
import { Resvg } from "@resvg/resvg-js";
import { writeFileSync, readFileSync, mkdirSync } from "fs";

const POSTS = [
  { slug: "towards-shared-minds", title: "Towards Shared Minds", excerpt: "Magical times are upon us. Yet it somehow feels atomised. Everyone with their workflows, their agents, their terminals — all they can share is stories of their single-player adventures.", tag: "Philosophy", date: "Feb 2026" },
  { slug: "machinations-of-egregore", title: "Machinations of Egregore", excerpt: "Not a tool Claude connects to — an environment Claude operates within. Each group receives a self-contained workspace distributed through GitHub.", tag: "Architecture", date: "Feb 2026" },
  { slug: "context-gardening", title: "Context Gardening", excerpt: "Engineering is top-down. Gardening is bottom-up. The best context engineering is already being delegated to AI — the right move is to let it do the engineering.", tag: "Philosophy", date: "Feb 2026" },
  { slug: "interface-of-desire", title: "Interface of Desire", excerpt: "People create workarounds when tools don't match their natural workflow — copying conversation logs, writing 'here's what I tried' messages.", tag: "Research", date: "Feb 2026" },
  { slug: "emergent-governance", title: "Can Systems Learn How Organizations Should Work?", excerpt: "Most tools force organizations to pre-configure their governance. But optimal structure emerges through practice.", tag: "Governance", date: "Feb 2026" },
  { slug: "from-retrieval-to-synthesis", title: "From Retrieval to Synthesis", excerpt: "Current AI retrieval finds documents. Synthesis is harder — insight that emerges only from seeing patterns across many contexts simultaneously.", tag: "Research", date: "Feb 2026" },
  { slug: "async-handoffs-replace-standups", title: "Async Handoffs Replace Standups", excerpt: "The standup exists for one reason: context sync. When the system holds persistent state, the ritual can evolve.", tag: "Practice", date: "Jan 2026" },
  { slug: "economics-of-context", title: "The Economics of Organizational Memory", excerpt: "Why flat team pricing, what drives our costs, and how we think about building a sustainable business around context infrastructure.", tag: "Economics", date: "Jan 2026" },
];

// Load ASCII art for background
function loadAsciiArt() {
  const raw = readFileSync("src/wizards working.txt", "utf-8");
  // Take a center crop — lines 20-120, trimmed to fit
  const lines = raw.split("\n").slice(20, 110);
  // Trim each line to ~200 chars from the center portion
  return lines.map((l) => {
    const trimmed = l.slice(80, 340);
    return trimmed || " ";
  }).join("\n");
}

async function loadFont() {
  const url = "https://fonts.googleapis.com/css2?family=Courier+Prime:wght@400;700&display=swap";
  const css = await fetch(url).then((r) => r.text());
  const fontUrl = css.match(/src: url\(([^)]+)\)/)?.[1];
  if (!fontUrl) throw new Error("Could not find font URL");
  return await fetch(fontUrl).then((r) => r.arrayBuffer());
}

async function loadSlovicFont() {
  return readFileSync("public/fonts/Slovic_Demo-Historic.otf").buffer;
}

function card(post, asciiArt) {
  return {
    type: "div",
    props: {
      style: {
        width: "1200px",
        height: "630px",
        background: "#F4F1EA",
        display: "flex",
        flexDirection: "column",
        position: "relative",
        overflow: "hidden",
        fontFamily: "Courier Prime",
      },
      children: [
        // ASCII art background
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              top: "-20px",
              left: "-40px",
              right: "-40px",
              bottom: "-20px",
              fontSize: "4.5px",
              lineHeight: 1.05,
              color: "rgba(26,23,20,0.06)",
              fontFamily: "Courier Prime",
              whiteSpace: "pre",
              letterSpacing: "0px",
            },
            children: asciiArt,
          },
        },
        // Large gothic E watermark
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              top: "50%",
              right: "60px",
              transform: "translateY(-50%)",
              fontSize: "320px",
              fontFamily: "Slovic",
              color: "rgba(122,15,27,0.12)",
              lineHeight: 1,
            },
            children: "E",
          },
        },
        // Content overlay
        {
          type: "div",
          props: {
            style: {
              position: "relative",
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              padding: "55px 65px",
              height: "100%",
            },
            children: [
              // Tag
              {
                type: "div",
                props: {
                  style: {
                    fontSize: "14px",
                    letterSpacing: "3px",
                    textTransform: "uppercase",
                    color: "#c8a55a",
                  },
                  children: post.tag,
                },
              },
              // Title + excerpt
              {
                type: "div",
                props: {
                  style: { display: "flex", flexDirection: "column", gap: "18px", maxWidth: "850px" },
                  children: [
                    {
                      type: "div",
                      props: {
                        style: {
                          fontSize: "46px",
                          fontWeight: 700,
                          color: "#1a1714",
                          lineHeight: 1.15,
                        },
                        children: post.title,
                      },
                    },
                    {
                      type: "div",
                      props: {
                        style: {
                          fontSize: "18px",
                          color: "#8a8578",
                          lineHeight: 1.6,
                          maxWidth: "750px",
                        },
                        children: post.excerpt,
                      },
                    },
                  ],
                },
              },
              // Bottom bar
              {
                type: "div",
                props: {
                  style: {
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    borderTop: "1px solid #d4cfc5",
                    paddingTop: "18px",
                  },
                  children: [
                    {
                      type: "div",
                      props: {
                        style: {
                          fontSize: "16px",
                          color: "#7A0F1B",
                          letterSpacing: "3px",
                          textTransform: "uppercase",
                        },
                        children: "Egregore",
                      },
                    },
                    {
                      type: "div",
                      props: {
                        style: {
                          fontSize: "14px",
                          color: "#8a8578",
                        },
                        children: post.date,
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
      ],
    },
  };
}

async function main() {
  console.log("Generating OG images...");
  const [fontData, slovicFont] = await Promise.all([loadFont(), loadSlovicFont()]);
  const asciiArt = loadAsciiArt();

  const fonts = [
    { name: "Courier Prime", data: fontData, weight: 400, style: "normal" },
    { name: "Courier Prime", data: fontData, weight: 700, style: "normal" },
    { name: "Slovic", data: slovicFont, weight: 400, style: "normal" },
  ];

  mkdirSync("public/og", { recursive: true });

  for (const post of POSTS) {
    const svg = await satori(card(post, asciiArt), { width: 1200, height: 630, fonts });
    const png = new Resvg(svg, { fitTo: { mode: "width", value: 1200 } }).render().asPng();
    writeFileSync(`public/og/${post.slug}.png`, png);
    console.log(`  ✓ ${post.slug}.png`);
  }

  // Default OG image
  const defaultCard = {
    type: "div",
    props: {
      style: {
        width: "1200px",
        height: "630px",
        background: "#F4F1EA",
        display: "flex",
        position: "relative",
        overflow: "hidden",
        fontFamily: "Courier Prime",
      },
      children: [
        // ASCII art background
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              top: "-20px",
              left: "-40px",
              right: "-40px",
              bottom: "-20px",
              fontSize: "4.5px",
              lineHeight: 1.05,
              color: "rgba(26,23,20,0.06)",
              fontFamily: "Courier Prime",
              whiteSpace: "pre",
              letterSpacing: "0px",
            },
            children: asciiArt,
          },
        },
        // Gothic Egregore watermark
        {
          type: "div",
          props: {
            style: {
              position: "absolute",
              top: "50%",
              left: "50%",
              transform: "translate(-50%, -50%)",
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: "16px",
            },
            children: [
              {
                type: "div",
                props: {
                  style: {
                    fontSize: "96px",
                    fontFamily: "Slovic",
                    color: "#7A0F1B",
                    lineHeight: 1,
                  },
                  children: "Egregore",
                },
              },
              {
                type: "div",
                props: {
                  style: {
                    fontSize: "18px",
                    color: "#8a8578",
                    letterSpacing: "4px",
                    textTransform: "uppercase",
                  },
                  children: "Shared cognition for teams and agents",
                },
              },
            ],
          },
        },
      ],
    },
  };

  const svg = await satori(defaultCard, { width: 1200, height: 630, fonts });
  writeFileSync("public/og/default.png", new Resvg(svg, { fitTo: { mode: "width", value: 1200 } }).render().asPng());
  console.log("  ✓ default.png");
  console.log("Done.");
}

main();
