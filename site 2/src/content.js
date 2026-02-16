// Article content as structured blocks.
// Types: h2, h3, p, quote, divider

export const ARTICLE_CONTENT = {

  "machinations-of-egregore": [
    { type: "p", text: "Egregore is not a tool that Claude connects to \u2014 it\u2019s an environment that Claude operates within. Each group gets a self-contained workspace distributed through GitHub. When you join an Egregore, your machine receives the full environment: the codebase, the command protocol, the connection layer, and the collective memory. Claude Code reads this environment at session start and becomes your group\u2019s AI \u2014 aware of who\u2019s working on what, what decisions were made, and what needs attention." },
    { type: "p", text: "The environment is designed to evolve. Participants add commands, modify schemas, and reshape workflows as their practice develops. The affordance space grows alongside the group \u2014 Egregore becomes more capable as a consequence of being used, not as a consequence of platform updates." },
    { type: "divider" },

    { type: "h2", text: "The Stack" },
    { type: "h3", text: "Claude Code" },
    { type: "p", text: "The runtime. Every interaction happens through Claude in the terminal. There is no wrapper, no middleware, no custom UI between you and the model. Claude reads the environment\u2019s instructions and acts accordingly \u2014 running queries, creating files, updating the graph, opening PRs, notifying participants." },
    { type: "h3", text: "CLAUDE.md" },
    { type: "p", text: "The system prompt. It tells Claude who it is inside your Egregore, what conventions to follow, how to interact with the knowledge graph, and what the current priorities are. CLAUDE.md is living tissue \u2014 when the group discovers a pattern worth preserving, it goes here. Over time, it becomes a distillation of everything the collective has learned about how to work together." },
    { type: "h3", text: "Slash Commands" },
    { type: "p", text: "The coordination protocol. Each command is a markdown file in .claude/commands/ that defines a specific action: /activity to see what happened since you were last here, /handoff to transfer context to another participant, /save to checkpoint your work, /reflect to surface patterns across the collective, /quest to scope work into named investigations. Commands compose naturally through conversation \u2014 the vocabulary grows as the Egregore does." },
    { type: "h3", text: "Neo4j" },
    { type: "p", text: "The knowledge graph. Entities, relationships, temporal layers, and session traces. Queries go through a lightweight shell script that hits Neo4j\u2019s HTTP API directly \u2014 no ORM, no abstraction layer, just Cypher and curl." },
    { type: "h3", text: "GitHub" },
    { type: "p", text: "The distribution and versioning layer. Each group gets a fork of egregore-core. The codebase, the commands, the memory \u2014 all versioned in Git. /save and /handoff create branches and open PRs. Upstream updates pull cleanly. The group\u2019s private memory repo stores handoffs, session artifacts, and shared documents." },
    { type: "h3", text: "The Gateway" },
    { type: "p", text: "The Railway API gateway handles authentication, provisioning, and proxies all graph and notification traffic. The local environment never touches infrastructure secrets directly. On first launch, session-start.sh authenticates against the gateway and establishes the session." },
    { type: "divider" },

    { type: "h2", text: "The Session Lifecycle" },
    { type: "p", text: "You open your terminal and type your alias. Claude Code launches, reads CLAUDE.md, and you\u2019re in context. You run /activity to see what\u2019s happened since you were last here \u2014 recent sessions, decisions, handoffs, and open threads pulled from the knowledge graph. You work. When you\u2019re done, /save checkpoints to Git and updates the graph, or /handoff does the same plus packages context for a specific person who picks it up in their next session." },
    { type: "p", text: "Every session leaves a trace. The graph accumulates. The next person who opens the terminal inherits not just the files, but the collective state." },
    { type: "divider" },

    { type: "h2", text: "What Egregore Is Not" },
    { type: "p", text: "Egregore is not a chatbot wrapper. It does not add a GUI on top of an LLM. It is not a project management tool with AI features bolted on." },
    { type: "p", text: "Egregore is an environment architecture \u2014 a way of structuring what Claude sees, what Claude can do, and what persists between sessions so that an AI can function as a genuine participant in collective work rather than a stateless utility." },
  ],

  "context-gardening": [
    { type: "quote", text: "Why the best AI context isn\u2019t engineered \u2014 it\u2019s grown." },
    { type: "p", text: "The prevailing term in AI tooling right now is \u201Ccontext engineering\u201D \u2014 the idea that if you\u2019re methodical enough, you can assemble the optimal set of information for a model to work with. Curate the right documents, structure the right prompts, retrieve the right chunks. Engineering implies a known target state: you design, you build, you ship." },
    { type: "p", text: "But this framing carries a quiet assumption that doesn\u2019t survive contact with real organizations. It assumes one person \u2014 or one system \u2014 can know in advance what the relevant context is. That relevance is a property of documents rather than a property of situations. That the right information can be selected before the moment it\u2019s needed." },
    { type: "p", text: "In practice, context doesn\u2019t work like that. Context emerges." },
    { type: "divider" },

    { type: "h2", text: "What Emergence Knows" },
    { type: "p", text: "Context gardening starts from a different premise: you don\u2019t manufacture context, you cultivate the conditions for it to grow. You set the soil \u2014 the environment, the capture methodologies, the tooling \u2014 and then you let the organic practice of teams working together produce the context that matters." },
    { type: "p", text: "The difference is not cosmetic. Engineering is top-down: someone decides what\u2019s relevant, builds a pipeline to surface it, and hopes the selection holds. Gardening is bottom-up: priorities emerge from interactions, from the actual texture of work, from what teams repeatedly reach for and what they let fall away. No one has to synthetically tell the model what matters. The model discovers what matters by being embedded in a space where real work is happening." },
    { type: "p", text: "This is closer to how institutional knowledge actually forms. Nobody writes the definitive document on \u201Chow we make decisions here.\u201D Instead, patterns accumulate. Certain references become load-bearing. Informal agreements harden into defaults. The organization develops a sense \u2014 distributed across people, artifacts, and habits \u2014 of what its context actually is." },
    { type: "divider" },

    { type: "h2", text: "Egregore as a Context Garden" },
    { type: "p", text: "When teams work inside an Egregore environment, every session contributes to a growing substrate of organizational intelligence. The knowledge graph doesn\u2019t start from a schema designed by an administrator \u2014 it grows from the actual patterns of collaboration. What teams discuss, what they reference, what they build on, what they contradict \u2014 all of this feeds the soil." },
    { type: "p", text: "The result is that AI systems plugged into an Egregore workspace don\u2019t operate on a static retrieval set. They operate on living context \u2014 context that reflects real priorities, real tensions, real momentum. The difference shows up immediately in output quality. Materials produced within this environment are not generically competent. They are tailor-made, because the context they draw from was tailor-grown by the people who will use them." },
    { type: "p", text: "This is where the gardening metaphor earns its weight. A garden doesn\u2019t produce the same thing every season. It responds to what you plant, how you tend it, what the conditions are. An Egregore environment does the same \u2014 it becomes more aware, more attuned, more useful as the team\u2019s work deepens." },
    { type: "divider" },

    { type: "h2", text: "What This Means in Practice" },
    { type: "p", text: "Context gardening shifts the burden of AI effectiveness away from prompt engineering and retrieval optimization and toward something more fundamental: the quality of the collaborative environment itself." },
    { type: "p", text: "If your team works in fragmented tools with no shared substrate, there is no garden \u2014 only scattered seeds. If your team works inside a persistent, accumulative environment, context grows whether or not anyone is explicitly tending it. The capture happens at the level of practice, not process." },
    { type: "p", text: "The most powerful context for AI is the one that no single person designed \u2014 the kind that can only emerge from the collective intelligence of the people who produced it. Egregore is the environment where that emergence happens." },
  ],

  "interface-of-desire": [
    { type: "p", text: "Before a tool exists, people improvise. They build workarounds. They copy conversation logs into shared documents. They write \u201Chere\u2019s what I tried\u201D messages in Slack threads that no one will find again. They create shared prompt libraries in Google Docs. They paste terminal output into pull request descriptions so the next person has context." },
    { type: "p", text: "These are desire paths \u2014 the unofficial routes people wear into the landscape when the official paths don\u2019t go where they need to go." },
    { type: "divider" },

    { type: "h2", text: "Desire Paths in AI Collaboration" },
    { type: "p", text: "Technology adoption theory suggests that successful tools amplify existing behaviors rather than imposing new ones. The question for any new coordination tool is: are you paving a desire path, or building a road no one asked for?" },
    { type: "p", text: "We looked for evidence of latent demand. Are people already doing something like Egregore\u2019s handoff pattern \u2014 manually? The answer, consistently, was yes. Teams collaborating on AI-assisted work (coding with Copilot, research with Claude, writing with ChatGPT) have invented their own handoff rituals. They\u2019re ad hoc, fragile, and lossy. But they exist. The desire is there." },
    { type: "p", text: "[Research findings: specific examples from interviews, existing workaround patterns, what breaks in current workflows.]" },
    { type: "divider" },

    { type: "h2", text: "The Shape of the Desire" },
    { type: "p", text: "What people want isn\u2019t a better chat interface. It isn\u2019t a dashboard. It isn\u2019t another SaaS surface with notifications and kanban boards." },
    { type: "p", text: "What they want is for the next person to have the context. That\u2019s it. The desire is simple: I worked on this thing, I learned things, someone else needs to continue, and they should know what I know without me having to explain it all over again." },
    { type: "p", text: "Every handoff is a desire for continuity. Every status meeting is a desire for shared state. Every \u201Cwhere did we land on X?\u201D is a desire for persistent memory." },
    { type: "divider" },

    { type: "h2", text: "Machinic Desire" },
    { type: "p", text: "There\u2019s a Deleuzian reading here. Desire is not lack \u2014 not the absence of a tool. Desire is productive. It generates. The workarounds people build are not symptoms of a missing product. They are the product, trying to assemble itself from available parts." },
    { type: "p", text: "Egregore\u2019s design principle: don\u2019t invent workflows. Observe the desire paths. Then make them permanent infrastructure." },
    { type: "p", text: "[Expand: the relationship between desire paths and emergent governance. How observed patterns become suggested structure. The system that learns what the organization wants to be.]" },
  ],

};
