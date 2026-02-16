const SITE_NAME = "Egregore";

const ARTICLES = {
  "towards-shared-minds": {
    title: "Towards Shared Minds",
    description: "Magical times are upon us. Yet it somehow feels atomised. Everyone with their workflows, their agents, their terminals \u2014 all they can share is stories of their single-player adventures. Our visceral rebellion against this status quo led us to Egregore.",
  },
  "machinations-of-egregore": {
    title: "Machinations of Egregore",
    description: "Not a tool Claude connects to \u2014 an environment Claude operates within. Each group receives a self-contained workspace distributed through GitHub: the codebase, the command protocol, the connection layer, and the collective memory.",
  },
  "context-gardening": {
    title: "Context Gardening",
    description: "Engineering is top-down. Gardening is bottom-up. The best context engineering is already being delegated to AI \u2014 the right move is to let it do the engineering, give it the tools, and get out of its way.",
  },
  "interface-of-desire": {
    title: "Interface of Desire",
    description: "People create workarounds when tools don\u2019t match their natural workflow \u2014 copying conversation logs, writing \u201Chere\u2019s what I tried\u201D messages, building shared prompt libraries. These desire paths reveal latent demand.",
  },
  "emergent-governance": {
    title: "Can Systems Learn How Organizations Should Work?",
    description: "Most tools force organizations to pre-configure their governance. But optimal structure emerges through practice \u2014 it isn\u2019t known in advance.",
  },
  "from-retrieval-to-synthesis": {
    title: "From Retrieval to Synthesis",
    description: "Current AI retrieval finds documents. Synthesis is harder \u2014 insight that emerges only from seeing patterns across many contexts simultaneously.",
  },
  "async-handoffs-replace-standups": {
    title: "Async Handoffs Replace Standups",
    description: "The standup exists for one reason: context sync. When the system holds persistent state, the ritual can evolve.",
  },
  "economics-of-context": {
    title: "The Economics of Organizational Memory",
    description: "Why flat team pricing, what drives our costs, and how we think about building a sustainable business around context infrastructure.",
  },
};

const PAGES = {
  "/research": {
    title: "Research \u2014 Egregore",
    description: "Dispatches on shared cognition, coordination infrastructure, and what emerges when organizations develop memory.",
  },
  "/docs": {
    title: "Documentation \u2014 Egregore",
    description: "Architecture, setup, and usage documentation for Egregore \u2014 the shared intelligence layer for organizations using Claude Code.",
  },
};

function getMeta(request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const path = url.pathname;

  // Article pages: /research/:slug
  const articleMatch = path.match(/^\/research\/([^/]+)\/?$/);
  if (articleMatch) {
    const slug = articleMatch[1];
    const article = ARTICLES[slug];
    if (article) {
      return {
        title: `${article.title} \u2014 Egregore`,
        description: article.description,
        url: `${origin}/research/${slug}`,
        image: `${origin}/og/${slug}.png`,
        type: "article",
      };
    }
  }

  // Static pages
  const page = PAGES[path] || PAGES[path.replace(/\/$/, "")];
  if (page) {
    return {
      title: page.title,
      description: page.description,
      url: `${origin}${path}`,
      image: `${origin}/og/default.png`,
      type: "website",
    };
  }

  // Homepage
  if (path === "/" || path === "") {
    return {
      title: "Egregore \u2014 Shared Cognition for Teams and Agents",
      description: "A terminal-native platform where humans and AI agents share persistent context and work together as a single organizational mind.",
      url: origin,
      image: `${origin}/og/default.png`,
      type: "website",
    };
  }

  return null;
}

function injectOgTags(html, meta) {
  const ogTags = `
    <meta property="og:type" content="${meta.type}" />
    <meta property="og:site_name" content="${SITE_NAME}" />
    <meta property="og:title" content="${meta.title}" />
    <meta property="og:description" content="${meta.description}" />
    <meta property="og:url" content="${meta.url}" />
    <meta property="og:image" content="${meta.image}" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${meta.title}" />
    <meta name="twitter:description" content="${meta.description}" />
    <meta name="twitter:image" content="${meta.image}" />`;

  // Replace existing OG tags and title
  let result = html;

  // Replace <title>
  result = result.replace(
    /<title>[^<]*<\/title>/,
    `<title>${meta.title}</title>`
  );

  // Replace existing OG/twitter meta block with new one
  result = result.replace(
    /\s*<!-- Open Graph -->[\s\S]*?<meta name="twitter:image"[^>]*\/>/,
    ogTags
  );

  return result;
}

export default async (request, context) => {
  const meta = getMeta(request);

  // No custom meta needed — pass through
  if (!meta) {
    return context.next();
  }

  const response = await context.next();
  const contentType = response.headers.get("content-type") || "";

  // Only transform HTML responses
  if (!contentType.includes("text/html")) {
    return response;
  }

  const html = await response.text();
  const transformed = injectOgTags(html, meta);

  return new Response(transformed, {
    status: response.status,
    headers: response.headers,
  });
};

export const config = {
  path: "/*",
};
