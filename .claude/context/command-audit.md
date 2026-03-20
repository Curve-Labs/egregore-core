# Command Audit: Neo4j Dependency Classification

**Date**: 2026-03-18 (updated 2026-03-20)
**Author**: cem (updated: oz)
**Context**: CORK Mar 17 — 27 of ~50 commands currently fail without Neo4j. Updated after mode-aware implementation (PRs #364-#373).

## Mode detection

`egregore.json` now has a `mode` field: `"local"` (OSS) or `"connected"` (hosted). Written during `create-egregore` setup. Commands read this to decide behavior — local mode skips ALL graph/API calls silently. No "Graph offline" warnings, no "/connect" suggestions. See `oss-launch.md` for full spec.

## Philosophy

Egregore ships as a coherent OS product: 15-20 commands that work
without any infrastructure beyond Git and a memory/ directory. Everything
else is a clearly marked extension that lights up when the knowledge
graph is connected.

The mental model:

```
Files = truth. Graph = query layer on top.
```

Commands that create artifacts always write a file first. Graph nodes are
indexing — they make things queryable, linkable, and visible in
dashboards, but the file is the canonical record. This means every
file-writing command can work without the graph. Commands that only read
from the graph (dashboard, todo, quest-suggest) have no file fallback
and belong in the managed tier.

### Progressive Rollout

| Phase | Commands | When |
|-------|----------|------|
| **Launch** | activity, handoff, invite, quest | Day 1 — the four commands new users see first |
| **Core** | reflect, save, wrap, setup, onboarding, pr, issue, test, meeting, + git commands | Surfaces contextually as users work |
| **Extension** | dashboard, todo, deep-reflect, ask, 22 others | Available with Egregore Managed (`/connect`) |
| **Infra** | release, sync-public, deploy-*, waitlist | Maintainer/admin only |

---

## Classification Summary

| Category | Count | Description |
|----------|-------|-------------|
| **1 — Works as-is** | 20 | Zero graph calls. Ships unchanged. |
| **2 — Works in local mode** | 28 | Graph is supplementary. FS fallback implemented or trivial. |
| **3 — Graph-required** | 7 | Core purpose is the graph. Connected-only. |
| **Total** | **55** | |

**Updated 2026-03-20**: `/ask`, `/dashboard`, `/deep-reflect`, `/me` moved from Cat 3 → Cat 2 (local mode implemented). `/activity`, `/handoff`, `/invite`, `/quest`, `/reflect`, `/onboarding` all have mode detection shipped.

---

## Category 1 — Works without Neo4j as-is (20 commands)

These commands have no graph operations whatsoever. They work in OSS
mode today with no changes.

| # | Command | Purpose | Phase |
|---|---------|---------|-------|
| 1 | `announce` | Send Telegram group message | Core |
| 2 | `branch` | Create working branch (EnterWorktree) | Core |
| 3 | `commit` | Stage and commit | Core |
| 4 | `connect` | Manage OAuth connectors (local state) | Core |
| 5 | `deploy-image` | Build/deploy Docker workspace image | Infra |
| 6 | `deploy-preview` | Netlify preview branch deploy | Infra |
| 7 | `deploy-site` | Production site deploy | Infra |
| 8 | `deploy-template` | Coder workspace template push | Infra |
| 9 | `docs` | Open architecture docs in browser | Core |
| 10 | `env` | Configure .env file | Core |
| 11 | `ingest` | Router — dispatches to meeting/interview/google | Core |
| 12 | `note` | Personal notes in .egregore/notes/ | Core |
| 13 | `pull` | Sync develop + pull memory | Core |
| 14 | `push` | Push working branch to remote | Core |
| 15 | `release` | Merge develop → main + tag + notify | Infra |
| 16 | `sync-public` | Rsync curve-labs-core → egregore-core | Infra |
| 17 | `sync-repos` | Fetch/pull all managed repos | Core |
| 18 | `telemetry` | Manage telemetry on/off/show/clear | Core |
| 19 | `update` | Framework sync from upstream | Core |
| 20 | `waitlist` | Admin waitlist management (Supabase API) | Infra |

---

## Category 2 — Needs modification for FS memory (24 commands)

Each command below uses the graph for enrichment, indexing, or context
gathering. The core function can work from files. Modifications are
listed per command.

### Launch Set (must ship on day 1)

#### activity
- **Current graph usage**: `activity-data.sh` fetches all dashboard data (sessions, handoffs, quests, artifacts, PRs) from Neo4j. `record-focus`, `mark-read`, `mark-done` mutate graph state.
- **Modification**: Build an FS scanner that reads:
  - `memory/handoffs/index.md` → parse for recent handoffs, extract recipient/author/date
  - `memory/quests/*.md` → parse frontmatter for status, priority, started_by
  - `memory/wraps/YYYY-MM/*.md` → recent sessions (author, topic, date)
  - `git log --oneline -20` → commit activity as proxy for session data
  - Skip `record-focus`, `mark-read`, `mark-done` (no-op without graph)
- **Render**: Same TUI layout but populated from files. In local mode, footer shows "Local mode — showing activity from memory". **DONE** (PR #372).
- **Effort**: High — this is the biggest single modification.

#### handoff
- **Current graph usage**: `index-handoff.sh` creates Session node + HANDED_TO/BY/ABOUT edges. Triage mode queries open handoffs. Artifact query pulls today's artifacts.
- **Modification**:
  - Skip triage mode (no graph to query open handoffs)
  - Skip artifact query
  - Skip Session node creation via `index-handoff.sh`
  - Keep: file write to `memory/handoffs/`, index.md update, `notify.sh` call (works via API), auto-save
- **User sees**: Handoff file is created and pushed. "Handoff saved to memory. Team will see it in /activity."
- **Effort**: Medium — mostly removing calls, core flow unchanged.

#### invite
- **Current graph usage**: `graph.sh` MERGE Person node, Telegram lookup for notification, Supabase sync.
- **Modification**:
  - Skip graph Person creation + orphan merge
  - Skip Telegram lookup (graph-based — `p.telegramId`)
  - Keep: GitHub org invite via API, invite URL generation, person file in `memory/people/`
- **User sees**: Invite works. Graph registration happens when they `/connect`.
- **Effort**: Low — remove 2 graph calls.

#### quest
- **Current graph usage**: Quest/Person/Project nodes, STARTED_BY edge, priority/status SET, linked Todos query.
- **Modification**:
  - **List**: Scan `memory/quests/*.md`, parse frontmatter (status, priority, started_by)
  - **Show**: Parse quest markdown for threads. Grep `memory/knowledge/` for artifacts with matching topics in frontmatter. Omit Todos section (graph-only).
  - **New**: Write quest file + push memory. Skip graph Quest node creation.
  - **Prioritize/Pause/Complete**: Update frontmatter in quest file. Skip graph SET.
  - **Contribute**: Append to quest file. Skip graph.
- **User sees**: Full quest management from files. No todo integration. **DONE** (PR #372 — mode detection added).
- **Effort**: High — needs FS scanner for list/show, but patterns reusable from activity.

### Core Commands

#### reflect
- **Current graph usage**: 6 context queries (sessions, quests, artifacts, knowledge gaps, decisions, topic deep-dive), Artifact node creation, relation detection (quest links, related artifacts).
- **Modification**:
  - Deep mode: Skip context queries. Fall back to generic opening ("What's on your mind?") instead of graph-aware prompts.
  - Quick mode: Already works with minimal context — just skip relation detection.
  - Skip Artifact node creation. Keep file creation in `memory/knowledge/{type}s/`.
  - Skip RELATES_TO/PART_OF edge creation.
- **User sees**: Full reflect flow. Deep mode is less "smart" (no graph-aware openings). File still created. "Graph offline — saved to memory. Quest linking available when connected."
- **Effort**: Medium — mostly skipping calls, degrading gracefully.

#### save
- **Current graph usage**: `sync-graph.sh` scans memory/ for files without graph nodes and creates them. `graph-op.sh create-pr` tracks PRs. Metadata enrichment (topics, types, timestamps).
- **Modification**:
  - Skip `sync-graph.sh` entirely (it's a graph sync step)
  - Skip `graph-op.sh create-pr` (fire-and-forget)
  - Skip metadata enrichment queries
  - Keep: ALL git operations — memory push, branch push, PR creation, preflight, auto-merge
- **User sees**: Identical git workflow. No graph sync line in output.
- **Effort**: Low — remove 2 calls.

#### wrap
- **Current graph usage**: Session node update (topic, summary, openThreads), quest linking, todo completion, WAL writes.
- **Modification**:
  - Skip all graph writes (Session update, quest linking, todo completion)
  - Keep: wrap file creation in `memory/wraps/`, auto-save, TUI confirmation
  - Omit "Links" section from TUI when graph offline
- **User sees**: Wrap file saved. Session captured in file, not graph.
- **Effort**: Low — skip graph writes, keep file writes.

#### setup
- **Current graph usage**: `graph.sh` MERGE Person node for registration.
- **Modification**: Skip Neo4j registration step. Keep: memory clone, symlink, project setup. "Graph registration skipped — run /connect to enable knowledge graph."
- **Effort**: Trivial.

#### onboarding
- **Current graph usage**: ORIENT queries (active quests, recent handoffs), COMPLETE Person node creation + Supabase sync.
- **Modification**:
  - ORIENT: Skip graph queries. Use FS fallback — scan `memory/quests/` for active quests, `memory/handoffs/index.md` for recent handoffs. If empty: "It's early — you're one of the first here."
  - COMPLETE: Skip graph Person creation. Keep: egregore.md update, person file in `memory/people/`, state file, shell alias.
- **Effort**: Medium — ORIENT needs the same FS scanner as activity (reuse).

#### pr
- **Current graph usage**: `graph-op.sh create-pr` (fire-and-forget tracking).
- **Modification**: Remove the fire-and-forget `graph-op.sh` call. Everything else (`gh pr create`, diff summary) works as-is.
- **Effort**: Trivial — delete one line.

#### issue
- **Current graph usage**: Session context query, Issue node + REPORTED_BY edge. List/close/search modes query Issue nodes.
- **Modification**:
  - Create mode: Skip session context query. Skip Issue node. Keep: file in `memory/knowledge/issues/`, GitHub issue via `gh`, notify, auto-save.
  - List mode: Scan `memory/knowledge/issues/*.md` frontmatter for status/title/author.
  - Close mode: Update frontmatter `status: closed` in issue file. `gh issue close` still works.
  - Search mode: Grep issue files by title/topic.
- **Effort**: Medium — list/close/search need FS implementations.

#### test
- **Current graph usage**: Live Cypher validation (executes extracted queries against graph).
- **Modification**: Already has offline fallback — shows "Graph offline — skipped" for live queries. Static analysis runs regardless. No changes needed beyond what exists.
- **Effort**: None (already handled).

#### review-pr
- **Current graph usage**: None directly. Checks Cypher syntax statically (pattern matching, not live execution).
- **Modification**: None needed. Already works without graph.
- **Effort**: None.

#### checkup
- **Current graph usage**: Person node check (step 3b), graph connectivity test (step 5), identity drift auto-fix.
- **Modification**: Skip checks 3b and 5 when graph offline. Show "(graph offline, skipping)" for those checks. Keep all other diagnostics.
- **Effort**: Low.

#### meeting
- **Current graph usage**: 5 cross-meeting context queries via `graph-batch.sh`, attendee resolution against Person nodes, 20+ graph writes for Meeting/Artifact nodes.
- **Modification**:
  - Skip Step 4 context queries (already has "continue without" fallback in spec)
  - Skip attendee graph resolution — use email-derived names only
  - Skip Step 11 graph batch writes entirely
  - Keep: Granola fetch, all analysis (inline or sub-agents), file creation in `memory/meetings/` and `memory/knowledge/`, auto-save
- **User sees**: Full meeting analysis. Less continuity context. Files saved. "Graph offline — meeting analysis saved to memory."
- **Effort**: Medium — mostly removing calls; analysis pipeline unchanged.

#### tutorial
- **Current graph usage**: `activity-data.sh` for dashboard, graph queries for quest/session state, Artifact/Quest node creation during tutorial.
- **Modification**:
  - Replace graph queries with FS scans (same pattern as activity)
  - Skip Artifact/Quest node creation — rely on file creation
  - Tutorial flow still works: questions → file writes → TUI confirmation
- **Effort**: Medium — reuses FS scanner from activity.

### Extension Commands (surfaces with /connect)

#### archive
- **Current graph usage**: 4 context queries (sessions, patterns, quests, artifacts), Artifact node, PART_OF/RELATES_TO edges.
- **Modification**: Skip context queries (use conversation context only). Skip graph indexing. Keep: pattern file write to `memory/knowledge/patterns/`.
- **Effort**: Low.

#### add
- **Current graph usage**: Artifact node, quest linking queries, CONTRIBUTED_BY/PART_OF edges.
- **Modification**: Skip graph node creation. Keep: file creation in `memory/artifacts/` with frontmatter. Quest linking is manual (edit frontmatter).
- **Effort**: Low.

#### harvest
- **Current graph usage**: Person queries, prior harvest queries, Harvest/Session/Turn nodes.
- **Modification**: Skip all graph reads/writes. Keep: question generation, elicitation, synthesis file in `memory/knowledge/harvests/`. "Graph offline — running solo harvest."
- **Effort**: Low.

#### eval
- **Current graph usage**: `eval-op.sh get-runs`, `get-latest-report` per pipeline.
- **Modification**: Show file-based inventory from `eval-specs/*.md` and `.egregore/eval-runs/`. Skip graph-stored run metadata.
- **Effort**: Low.

#### eval-multiagent
- **Current graph usage**: `eval-op.sh create-run/match/report` per execution.
- **Modification**: Wrap graph writes with `|| true`. Core eval (run + tournament + Elo) works entirely from disk. "Graph offline — results saved locally only."
- **Effort**: Trivial.

#### ingest-google
- **Current graph usage**: Person matching, quest matching, Artifact node + edges.
- **Modification**: Skip graph Person/Quest matching. Keep: Google fetch, analysis, file creation in `memory/knowledge/sources/google/`.
- **Effort**: Low.

#### ingest-user-interview
- **Current graph usage**: 4 cross-interview context queries, Artifact nodes per analyst output.
- **Modification**: Skip graph context. Keep: multi-agent analysis pipeline, file creation.
- **Effort**: Low.

#### summon
- **Current graph usage**: Graph context scan (quests, sessions, spirits), Spirit node creation.
- **Modification**: Skip graph context — fall back to conversation context for design questions. Skip Spirit node. Keep: spec file in `.spirits/`, CronCreate scheduling.
- **Effort**: Low.

---

## Category 3 — Graph-required, managed-only (11 commands)

These commands exist to query, analyze, or maintain the knowledge graph.
They have no meaningful file-system equivalent. In OSS mode, they show
an informative message directing the user to `/connect`.

### User Experience in OSS Mode

When a user runs a category-3 command without the graph connected, they
see a message like:

```
/dashboard shows your personal command center — sessions, todos,
open threads. This is an Egregore Managed feature.

Run /connect to enable the knowledge graph, or use /activity for
a file-based overview of what's happening.
```

The message always: (1) explains what the command does, (2) names it as
a managed feature, (3) suggests an alternative or next step.

### Command Table

Commands that truly require the knowledge graph. In local mode, show an informative message — never an error.

| # | Command | Purpose | Connected-only feature |
|---|---------|---------|----------------------|
| 1 | `todo` | Personal task management (graph-only storage) | Yes — no FS equivalent |
| 2 | `quest-suggest` | Quest drift analysis: orphan ratio, stale priorities | Yes — requires graph metrics |
| 3 | `project` | Project status: linked quests, artifacts, domain | Yes — requires graph |
| 4 | `character-v4` | Egregore personality seeded from graph metrics | Yes — requires graph |
| 5 | `delete-user` | Remove member from graph + GitHub + Supabase | Partially — GitHub removal works, graph/Supabase need API |
| 6 | `graph-diagnostic` | 26 diagnostic queries against Neo4j | Yes — no data without graph |
| 7 | `graph-maintain` | Graph maintenance: scan, auto-fix, suggest | Yes — no data without graph |

**Moved to Category 2 (2026-03-20):** `ask`, `dashboard`, `deep-reflect`, `me` — all now have local mode fallbacks implemented.

---

## Recurring Modification Patterns

The 24 category-2 commands share a few recurring patterns. Implementing
these as shared utilities reduces per-command effort significantly.

### Pattern A: Fire-and-forget graph tracking (trivial)
Commands: `pr`, `save`

The graph call is a non-blocking tracking operation (`graph-op.sh
create-pr`, `sync-graph.sh`). Remove or wrap with `|| true`. Zero
impact on user experience.

### Pattern B: Graph context enrichment (skip gracefully)
Commands: `reflect`, `meeting`, `tutorial`, `archive`, `harvest`,
`ingest-google`, `ingest-user-interview`, `summon`

Graph queries fetch context before the main operation (recent sessions,
active quests, related artifacts). When offline, the command still works
— it just has less context. Show a one-line note: "Graph offline —
working with local context only."

### Pattern C: Graph node creation alongside file creation (skip node)
Commands: `handoff`, `quest`, `issue`, `reflect`, `add`, `meeting`,
`onboarding`, `setup`, `wrap`, `tutorial`

Every artifact-creating command writes a file first, then creates a
graph node for indexing. When offline, skip the graph node. The file is
the truth. Graph sync happens later via `sync-graph.sh` when the user
runs `/connect` and `/save`.

### Pattern D: Graph-only queries powering display (replace with FS scanner)
Commands: `activity`, `quest` (list/show), `issue` (list/search/close),
`onboarding` (ORIENT)

These commands query the graph to build a display. Replace with FS
scanners that read `memory/` directories:

```
activity-data-fs.sh (or inline logic):
  - memory/handoffs/index.md     → recent handoffs
  - memory/quests/*.md           → quest status/priority
  - memory/wraps/YYYY-MM/*.md    → recent sessions
  - memory/knowledge/issues/*.md → open issues
  - git log --oneline -20        → commit activity
```

This is the highest-effort pattern but it's shared across multiple
commands. Build it once as a utility.

---

## Implementation Plan

### Phase 1: Launch Set (activity, handoff, invite, quest)

These four commands are the first thing new users see. They must work
flawlessly without the graph.

**Recommended order:**
1. `handoff` — easiest of the four (mostly removing calls)
2. `invite` — low effort (remove 2 graph calls)
3. `quest` — medium effort (FS scanner for list/show)
4. `activity` — highest effort (full FS scanner, biggest bang)

**Shared utility to build first:**
- `bin/activity-data-fs.sh` or equivalent FS scanner logic
- Reads handoffs, quests, wraps, issues from `memory/`
- Returns structured JSON matching the existing `activity-data.sh` format
- Reused by: activity, onboarding (ORIENT), tutorial

### Phase 2: Core Commands

After the launch set, make the daily workflow commands work:

1. `save` + `pr` — trivial (remove fire-and-forget calls)
2. `wrap` + `reflect` — low/medium (skip graph writes/context)
3. `setup` + `onboarding` — medium (reuse FS scanner from Phase 1)
4. `issue` + `meeting` + `test` + `checkup` — medium (FS fallbacks)
5. `tutorial` — medium (reuse FS scanner)

### Phase 3: Extension Gating

For category-3 commands, implement a shared gate:

```bash
# bin/require-graph.sh (or inline check)
if ! bash bin/graph.sh test 2>/dev/null; then
  echo "$MESSAGE"
  echo ""
  echo "Run /connect to enable the knowledge graph."
  exit 0
fi
```

Each category-3 command spec gets a gate at the top that calls this
with its specific message. This is a one-line addition per command.

For category-2 extension commands (archive, add, harvest, eval, etc.),
the same pattern applies but the command continues with reduced
functionality instead of stopping.

### Phase 4: Extension Commands

Lower priority. These commands work in managed mode and show informative
messages in OSS mode. Implement FS fallbacks as demand warrants.

---

## Design Principles

1. **Files are truth, graph is index.** Every file-writing command must
   work without the graph. The graph makes things queryable, not real.

2. **Never remove graph code.** All modifications are additive — check
   for graph availability, then either use it or fall back. Connected
   mode must never regress.

3. **Degrade gracefully, not silently.** When a feature is unavailable,
   tell the user what they're missing and how to enable it. Never show
   a dead error or empty output without explanation.

4. **One FS scanner, many consumers.** The `memory/` directory scanner
   is the core utility. Build it once with a clean interface and reuse
   it across activity, quest, issue, onboarding, and tutorial.

5. **Graph sync is deferred, not lost.** Files created without graph
   nodes get synced when the user connects the graph and runs `/save`.
   `sync-graph.sh` already handles this — it scans memory/ for files
   without graph nodes and creates them.

---

## Validation Checklist

Before shipping each phase, verify:

- [ ] Command works with no `.env` file at all
- [ ] Command works with `EGREGORE_API_KEY` absent
- [ ] Command works with `graph.sh test` returning failure
- [ ] Connected mode (with API key) still works identically
- [ ] No graph errors leak to user output
- [ ] Category-3 commands show informative message, not error
- [ ] Files created in local mode sync correctly when graph connects later
