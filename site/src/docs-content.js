// Docs navigation structure and content.
// Block types: p, h3, code, list, quote, divider, note, table

export const DOCS_NAV = [
  {
    group: "Getting Started",
    items: [
      { id: "overview", title: "Overview" },
      { id: "installation", title: "Installation" },
      { id: "first-session", title: "First Session" },
    ],
  },
  {
    group: "Session Loop",
    items: [
      { id: "activity", title: "/activity" },
      { id: "save", title: "/save" },
      { id: "handoff", title: "/handoff" },
    ],
  },
  {
    group: "Knowledge",
    items: [
      { id: "reflect", title: "/reflect" },
      { id: "add", title: "/add" },
      { id: "note", title: "/note" },
      { id: "ask", title: "/ask" },
    ],
  },
  {
    group: "Work",
    items: [
      { id: "quest", title: "/quest" },
      { id: "todo", title: "/todo" },
      { id: "project", title: "/project" },
    ],
  },
  {
    group: "Collaboration",
    items: [
      { id: "invite", title: "/invite" },
      { id: "meeting", title: "/meeting" },
    ],
  },
  {
    group: "Architecture",
    items: [
      { id: "memory", title: "Shared Memory" },
      { id: "graph", title: "Knowledge Graph" },
      { id: "hooks", title: "Hooks" },
      { id: "git-workflow", title: "Git Workflow" },
    ],
  },
  {
    group: "Configuration",
    items: [
      { id: "egregore-json", title: "egregore.json" },
      { id: "env-file", title: ".env" },
      { id: "update", title: "/update" },
      { id: "tutorial", title: "/tutorial" },
    ],
  },
];

export const DOCS = {

  // \u2500\u2500\u2500 GETTING STARTED \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  "overview": {
    title: "Overview",
    blocks: [
      { type: "p", text: "Egregore is a shared intelligence layer for organizations using Claude Code. It gives teams persistent memory, async handoffs, and accumulated knowledge across sessions and people." },
      { type: "p", text: "It is not a chatbot wrapper. It does not add a GUI on top of an LLM. Egregore is an environment architecture \u2014 a way of structuring what Claude sees, what Claude can do, and what persists between sessions so that AI can function as a genuine participant in collective work." },
      { type: "divider" },
      { type: "h3", text: "How it works" },
      { type: "p", text: "Each organization gets a self-contained workspace distributed through GitHub. When you join an Egregore, your machine receives the full environment: the codebase, the command protocol, the connection layer, and the collective memory. Claude Code reads this environment at session start and becomes your group\u2019s AI \u2014 aware of who\u2019s working on what, what decisions were made, and what needs attention." },
      { type: "h3", text: "The Stack" },
      { type: "list", items: [
        "Claude Code \u2014 The runtime. Every interaction happens in the terminal.",
        "CLAUDE.md \u2014 The system prompt. Living tissue that evolves with the group.",
        "Slash Commands \u2014 The coordination protocol. Markdown files that define actions.",
        "Neo4j \u2014 The knowledge graph. Entities, relationships, and session traces.",
        "GitHub \u2014 The distribution layer. Forks, branches, PRs, and memory repos.",
        "Telegram \u2014 Notifications for handoffs, invites, and team alerts (optional).",
      ] },
      { type: "h3", text: "Core Loop" },
      { type: "p", text: "Open terminal \u2192 type egregore \u2192 /activity to see what happened \u2192 work \u2192 /save or /handoff when done. Every session leaves a trace. The graph accumulates. The next person inherits the collective state." },
    ],
  },

  "installation": {
    title: "Installation",
    blocks: [
      { type: "p", text: "Egregore is installed via a single terminal command. You get this command after signing up through the waitlist or receiving an invite." },
      { type: "h3", text: "Requirements" },
      { type: "table", rows: [
        ["Claude Code", "Anthropic CLI \u2014 install from claude.ai/code"],
        ["GitHub", "Account with org access (or personal account)"],
        ["Node.js", "v20+ for the installer"],
        ["Shell", "Bash, Zsh, or Fish"],
      ] },
      { type: "note", text: "Egregore runs entirely through Claude Code. There is no separate app, no web dashboard, no IDE plugin. Your terminal is the interface." },
      { type: "divider" },
      { type: "h3", text: "Founders \u2014 creating a new Egregore" },
      { type: "p", text: "After signing up on the waitlist, you receive a personalized install command:" },
      { type: "code", text: "npx create-egregore --token ek_your_token" },
      { type: "p", text: "The installer authenticates with GitHub, forks the environment to your org, creates your shared memory repo, and configures everything. It also:" },
      { type: "list", items: [
        "Sets up a shell alias so you can type egregore from any terminal",
        "Creates a Telegram group for your team (optional)",
        "Lets you choose which repos to manage through Egregore (optional)",
        "Runs an interactive tutorial to walk you through the core loop",
      ] },
      { type: "p", text: "When you\u2019re ready to add teammates, run /invite \u2014 it generates a link they can use to join." },
      { type: "divider" },
      { type: "h3", text: "Joiners \u2014 accepting an invite" },
      { type: "p", text: "When someone invites you, you receive a link. Open it, sign in with GitHub, and you\u2019ll get your own install command:" },
      { type: "code", text: "npx create-egregore --token ek_your_token" },
      { type: "p", text: "The installer connects you to the existing Egregore \u2014 same environment, same memory, same graph. Your shell alias is set up automatically. Open a new terminal and type egregore to start." },
    ],
  },

  "first-session": {
    title: "First Session",
    blocks: [
      { type: "p", text: "Open a new terminal and type egregore. The session-start hook fires automatically, syncing your branch and memory. You see the greeting:" },
      { type: "code", text: `  \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2557  \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557
  \u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d\u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d \u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d\u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d \u2588\u2588\u2554\u2550\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d
  \u2588\u2588\u2588\u2588\u2588\u2557  \u2588\u2588\u2551  \u2588\u2588\u2588\u2557\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u2588\u2588\u2588\u2588\u2588\u2557  \u2588\u2588\u2551  \u2588\u2588\u2588\u2557\u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u2588\u2588\u2588\u2588\u2588\u2557
  \u2588\u2588\u2554\u2550\u2550\u255d  \u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2554\u2550\u2550\u255d  \u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2551   \u2588\u2588\u2551\u2588\u2588\u2554\u2550\u2550\u2588\u2588\u2557\u2588\u2588\u2554\u2550\u2550\u255d
  \u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557\u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u2588\u2588\u2551  \u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557\u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2554\u255d\u2588\u2588\u2551  \u2588\u2588\u2551\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2557
  \u255a\u2550\u2550\u2550\u2550\u2550\u2550\u255d \u255a\u2550\u2550\u2550\u2550\u2550\u255d \u255a\u2550\u255d  \u255a\u2550\u255d\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u255d \u255a\u2550\u2550\u2550\u2550\u2550\u255d  \u255a\u2550\u2550\u2550\u2550\u2550\u255d \u255a\u2550\u255d  \u255a\u2550\u255d\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u255d

  New session started.
  Branch: dev/oz/2026-02-07-session
  Develop: synced
  Memory: synced` },
      { type: "p", text: "Claude asks: \u201CWhat are you working on?\u201D Tell it. A topic-based branch is created automatically. Work normally \u2014 Claude has full context of your organization\u2019s memory, recent activity, and open threads." },
      { type: "p", text: "When you\u2019re done, run /save to checkpoint your work, or /handoff to transfer context to someone specific. You never need to touch git directly \u2014 Egregore handles branching, commits, PRs, and merges behind the scenes." },
    ],
  },

  // \u2500\u2500\u2500 SESSION LOOP \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  "activity": {
    title: "/activity",
    blocks: [
      { type: "p", text: "See what happened since your last session. Pulls from the knowledge graph to show recent sessions, decisions, handoffs directed at you, and open threads." },
      { type: "code", text: "> /activity" },
      { type: "p", text: "Displays a formatted dashboard with:" },
      { type: "list", items: [
        "Recent sessions by all team members (last 7 days)",
        "Open handoffs directed at you (with status icons)",
        "Recent decisions and artifacts",
        "Active quests and their momentum",
      ] },
      { type: "p", text: "Handoffs directed at you show with status indicators: \u25cf pending (unread), \u25d0 read but open, \u25cb resolved. Select a numbered item to read the full handoff." },
      { type: "note", text: "Run /activity at the start of every session to catch up on what happened while you were away." },
    ],
  },

  "save": {
    title: "/save",
    blocks: [
      { type: "p", text: "Checkpoint your contributions. Syncs to the knowledge graph, commits, pushes, and creates PRs \u2014 all in one command. You never need to run git commands directly." },
      { type: "code", text: "> /save" },
      { type: "h3", text: "What it does" },
      { type: "list", items: [
        "Syncs new handoffs, artifacts, and quests to the knowledge graph",
        "Pushes memory changes directly to main (markdown-only, always safe)",
        "Ensures you\u2019re on a working branch (creates one if needed)",
        "Rebases onto latest develop, pushes, creates PR",
        "Auto-merges markdown-only PRs; leaves code PRs for review",
      ] },
      { type: "h3", text: "Managed repos" },
      { type: "p", text: "If your org has managed repos in egregore.json, /save scans them all for uncommitted changes and handles each one with the same workflow." },
    ],
  },

  "handoff": {
    title: "/handoff",
    blocks: [
      { type: "p", text: "End a session with a summary for the next person. Packages your session context, creates a handoff file, updates the knowledge graph, and notifies the recipient." },
      { type: "code", text: `> /handoff mcp auth to oz

> /handoff          \u2190 triages open handoffs first` },
      { type: "h3", text: "With a recipient" },
      { type: "p", text: "Specify a topic and who it\u2019s for. The recipient gets a Telegram notification (if your org has Telegram enabled) and sees the handoff on their next /activity. The handoff file includes a session summary, key decisions, open threads, and entry points for picking up the work." },
      { type: "h3", text: "Triage mode" },
      { type: "p", text: "Run bare /handoff with no arguments to triage open handoffs directed at you. Walk through each one and mark them as done, still open, or not relevant. Then optionally create a new handoff." },
      { type: "h3", text: "What gets created" },
      { type: "list", items: [
        "Handoff file in memory/handoffs/",
        "Session node in the knowledge graph (with HANDED_TO relationship)",
        "Index entry in memory/handoffs/index.md",
        "Telegram notification to recipient (if enabled)",
      ] },
      { type: "p", text: "Auto-saves after creating the handoff \u2014 no need to run /save separately." },
    ],
  },

  // \u2500\u2500\u2500 KNOWLEDGE \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  "reflect": {
    title: "/reflect",
    blocks: [
      { type: "p", text: "Capture insights from your work. The system queries the knowledge graph to surface what\u2019s worth reflecting on, asks Socratic follow-ups, and auto-classifies what emerges into decisions, findings, or patterns." },
      { type: "h3", text: "Three modes" },
      { type: "table", rows: [
        ["/reflect", "Deep \u2014 full Socratic flow with graph context"],
        ["/reflect [content]", "Quick \u2014 rapid capture, auto-classify"],
        ["/reflect about [topic]", "Focused \u2014 deep but pre-seeded on a topic"],
      ] },
      { type: "h3", text: "Category override" },
      { type: "code", text: `> /reflect decision: use stdio for MCP
> /reflect finding: Neo4j HTTP faster than Bolt
> /reflect pattern: agents as individual PMF` },
      { type: "p", text: "Prefix with a category to skip classification. Artifacts are saved to memory/knowledge/ and indexed in the knowledge graph with topic tags and quest links." },
      { type: "note", text: "You never pick a category manually. The system auto-classifies from language cues, structural signals, and graph context." },
    ],
  },

  "add": {
    title: "/add",
    blocks: [
      { type: "p", text: "Ingest an artifact with minimal friction. Tell it what you\u2019re adding and the system suggests relations \u2014 which quest it belongs to, what topics apply, and which existing artifacts it connects to." },
      { type: "code", text: `> /add competitive analysis of cursor vs egregore
> /add meeting notes from investor call` },
      { type: "p", text: "Creates the artifact file in memory, indexes it in the knowledge graph with topic tags, and links it to relevant quests and existing artifacts." },
    ],
  },

  "note": {
    title: "/note",
    blocks: [
      { type: "p", text: "Save a personal note. Private by default \u2014 never shared, never pushed. You choose what to share later." },
      { type: "code", text: "> /note the pricing model needs to account for team size" },
      { type: "p", text: "Notes live locally (gitignored). They\u2019re visible only to you. Use /reflect or /add to promote a note to shared knowledge when you\u2019re ready." },
    ],
  },

  "ask": {
    title: "/ask",
    blocks: [
      { type: "p", text: "Ask questions \u2014 to yourself, the org, or a specific person. Context-aware and graph-backed." },
      { type: "code", text: `> /ask what did we decide about pricing?
> /ask oz what's the status of the MCP auth?
> /ask how does the session-start hook work?` },
      { type: "p", text: "Queries the knowledge graph for relevant decisions, artifacts, and session history. If directed at a person, checks their recent sessions and handoffs. If the answer isn\u2019t in the graph, tells you honestly and suggests who might know." },
    ],
  },

  // \u2500\u2500\u2500 WORK \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  "quest": {
    title: "/quest",
    blocks: [
      { type: "p", text: "Manage quests \u2014 open-ended explorations that anyone can contribute to. Quests are larger than tasks: they\u2019re named investigations that accumulate artifacts over time." },
      { type: "code", text: `> /quest                         \u2190 list active quests
> /quest new grants pipeline     \u2190 create a quest
> /quest grants                  \u2190 view quest details` },
      { type: "h3", text: "How quests work" },
      { type: "list", items: [
        "Quests live in memory/quests/ as markdown files",
        "Artifacts link to quests via PART_OF relationships in the graph",
        "Topic signatures are derived from linked artifacts automatically",
        "Quests have priority levels and status (active/completed/archived)",
        "/activity shows quest momentum based on recent artifact activity",
      ] },
    ],
  },

  "todo": {
    title: "/todo",
    blocks: [
      { type: "p", text: "Manage personal todos \u2014 lightweight intent capture that flows into quests, asks, and activity." },
      { type: "code", text: `> /todo review ali's PR on auth flow
> /todo                          \u2190 show open todos
> /todo done 3                   \u2190 mark #3 complete` },
      { type: "p", text: "Todos are personal and local. They\u2019re not shared with the team. When a todo grows into something bigger, promote it to a quest with /quest." },
    ],
  },

  "project": {
    title: "/project",
    blocks: [
      { type: "p", text: "Show project status \u2014 linked quests, recent artifacts, and entry points." },
      { type: "code", text: "> /project" },
      { type: "p", text: "Queries the knowledge graph for all quests, artifacts, and sessions related to the current project. Shows momentum, recent activity, and who\u2019s working on what." },
    ],
  },

  // \u2500\u2500\u2500 COLLABORATION \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  "invite": {
    title: "/invite",
    blocks: [
      { type: "p", text: "Invite someone to your Egregore. Generates a personalized join link they can use to get set up in one step." },
      { type: "code", text: "> /invite ali" },
      { type: "h3", text: "What it does" },
      { type: "list", items: [
        "Sends a GitHub org invitation (if org account)",
        "Generates a join link with pre-filled configuration",
        "Creates a Person node in the knowledge graph",
        "Notifies via Telegram (if enabled)",
      ] },
      { type: "p", text: "The invited person opens the link, signs in with GitHub, and receives their own npx install command. After running it, they\u2019re in the same Egregore \u2014 shared memory, shared graph, ready to work." },
    ],
  },

  "meeting": {
    title: "/meeting",
    blocks: [
      { type: "p", text: "Ingest meeting knowledge from Granola. Uses a multi-dimensional analysis pipeline with three analyst agents plus synthesis to extract rich artifacts from meetings." },
      { type: "code", text: "> /meeting" },
      { type: "p", text: "Paste your Granola meeting transcript and the system extracts decisions, action items, findings, and creates corresponding artifacts in memory and the knowledge graph. Participants are linked automatically." },
    ],
  },

  // \u2500\u2500\u2500 ARCHITECTURE \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  "memory": {
    title: "Shared Memory",
    blocks: [
      { type: "p", text: "Memory is a Git repository shared by all team members. It stores everything the organization accumulates: handoffs, artifacts, decisions, findings, patterns, and quests." },
      { type: "h3", text: "Structure" },
      { type: "code", text: `memory/
  people/           \u2190 who\u2019s involved, roles, interests
  handoffs/         \u2190 session handoffs and index
  knowledge/
    decisions/      \u2190 decisions with rationale
    findings/       \u2190 discoveries and observations
    patterns/       \u2190 recurring patterns worth naming
  quests/           \u2190 open-ended explorations` },
      { type: "p", text: "Memory is set up automatically during installation. Changes push directly to main (no PRs needed) since it\u2019s all markdown. A retry loop handles concurrent pushes from other team members." },
      { type: "h3", text: "How it accumulates" },
      { type: "p", text: "Every /save syncs new files to the knowledge graph. Every /handoff creates a session trace. Every /reflect produces an artifact. Over time, the memory repo becomes a living record of everything the organization knows \u2014 searchable both through files and through the graph." },
    ],
  },

  "graph": {
    title: "Knowledge Graph",
    blocks: [
      { type: "p", text: "Neo4j is the query layer over shared memory. It stores entities, relationships, temporal layers, and session traces. Commands like /activity, /reflect, and /ask query the graph automatically \u2014 you never need to write queries yourself." },
      { type: "h3", text: "Schema" },
      { type: "table", rows: [
        ["Person", "Team members with names and roles"],
        ["Session", "Individual work sessions with topics and summaries"],
        ["Artifact", "Decisions, findings, patterns, and other knowledge"],
        ["Quest", "Open-ended explorations that accumulate artifacts"],
        ["Project", "Named projects that quests and sessions relate to"],
      ] },
      { type: "h3", text: "Relationships" },
      { type: "code", text: `(Session)-[:BY]->(Person)
(Session)-[:HANDED_TO]->(Person)
(Artifact)-[:CONTRIBUTED_BY]->(Person)
(Artifact)-[:PART_OF]->(Quest)
(Artifact)-[:RELATES_TO]->(Artifact)` },
      { type: "p", text: "The graph is provisioned automatically for each organization. All queries route through the API gateway \u2014 no database credentials needed locally." },
    ],
  },

  "hooks": {
    title: "Hooks",
    blocks: [
      { type: "p", text: "Hooks are shell commands that execute automatically in response to Claude Code events. Egregore uses one primary hook that makes the whole system work." },
      { type: "h3", text: "Session Start" },
      { type: "p", text: "The SessionStart hook fires before your first message in every session. It:" },
      { type: "list", items: [
        "Syncs the develop branch from remote",
        "Resumes your working branch (or stays on develop until you start working)",
        "Pulls latest shared memory",
        "Outputs the greeting with ASCII art and status",
      ] },
      { type: "p", text: "This hook is pre-configured during installation. It\u2019s what makes typing egregore feel like launching an app rather than opening a terminal." },
      { type: "h3", text: "Custom hooks" },
      { type: "p", text: "Organizations can add custom hooks for events like PreToolUse, PostToolUse, and Stop. These can enforce policies, log activity, or trigger integrations. Configured in .claude/settings.json." },
    ],
  },

  "git-workflow": {
    title: "Git Workflow",
    blocks: [
      { type: "p", text: "Egregore handles all git operations behind the scenes. You never need to run git commands directly \u2014 /save manages branching, commits, rebasing, pushing, and PR creation automatically." },
      { type: "h3", text: "Branch structure" },
      { type: "code", text: `main           \u2190 stable releases
  develop      \u2190 integration (PRs land here)
    dev/oz/... \u2190 working branches (auto-created)` },
      { type: "h3", text: "Flow" },
      { type: "list", items: [
        "On launch: syncs develop + memory automatically",
        "When you say what you\u2019re working on: creates a topic-based branch",
        "/save: commits, rebases, pushes, creates PR to develop",
        "Markdown-only PRs auto-merge; code PRs are left for review",
      ] },
      { type: "h3", text: "Managed repos" },
      { type: "p", text: "Teams can add their own repos to egregore.json. These follow the same branching strategy and /save scans all of them for changes." },
    ],
  },

  // \u2500\u2500\u2500 CONFIGURATION \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  "egregore-json": {
    title: "egregore.json",
    blocks: [
      { type: "p", text: "The main configuration file. Committed to git. Contains non-secret org config only \u2014 set up automatically during installation." },
      { type: "code", text: `{
  "org_name": "Acme Corp",
  "github_org": "acme-corp",
  "memory_repo": "https://github.com/acme-corp/acme-corp-memory.git",
  "api_url": "https://api.egregore.xyz",
  "slug": "acme",
  "repos": ["frontend", "backend"]
}` },
      { type: "table", rows: [
        ["org_name", "Display name of the organization"],
        ["github_org", "GitHub org or username"],
        ["memory_repo", "URL of the shared memory repository"],
        ["api_url", "Egregore API gateway URL"],
        ["slug", "Short identifier for the org"],
        ["repos", "Managed repos (optional, cloned as siblings)"],
      ] },
      { type: "note", text: "Never put secrets in egregore.json. Tokens and API keys go in .env (gitignored)." },
    ],
  },

  "env-file": {
    title: ".env",
    blocks: [
      { type: "p", text: "Personal secrets file. Gitignored \u2014 never committed. Created automatically during installation." },
      { type: "code", text: `GITHUB_TOKEN=ghp_...
EGREGORE_API_KEY=ek_...` },
      { type: "table", rows: [
        ["GITHUB_TOKEN", "Personal access token \u2014 created via GitHub device flow during setup"],
        ["EGREGORE_API_KEY", "Org API key \u2014 provisioned automatically or provided by your team admin"],
      ] },
    ],
  },

  "update": {
    title: "/update",
    blocks: [
      { type: "p", text: "Update your local Egregore environment. Syncs framework updates from upstream and pulls all repos." },
      { type: "code", text: "> /update" },
      { type: "p", text: "Fetches the latest commands, hooks, and configuration from upstream, merges into your fork, and pulls all managed repos. Safe to run anytime \u2014 your org\u2019s customizations are preserved." },
    ],
  },

  "tutorial": {
    title: "/tutorial",
    blocks: [
      { type: "p", text: "Interactive walkthrough of Egregore\u2019s core loop. Runs automatically after installation. Run anytime to revisit." },
      { type: "code", text: "> /tutorial" },
      { type: "p", text: "Walks you through the session loop step by step: /activity to see context, /reflect to capture an insight, /handoff to transfer context. Creates real artifacts in your knowledge graph as you go." },
    ],
  },
};
