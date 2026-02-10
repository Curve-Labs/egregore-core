Activity dashboard. Display it immediately — no preamble, no narration, no reasoning text. Output the box and nothing else before AskUserQuestion.

Topic: $ARGUMENTS

## Step 1: Fetch data

Run ONE command to get all dashboard data:

```bash
bash bin/activity-data.sh
```

Returns JSON: `me`, `org`, `date`, `my_sessions`, `team_sessions`, `quests`, `pending_questions`, `answered_questions`, `handoffs_to_me`, `all_handoffs`, `knowledge_gap`, `orphans`, `checkins`, `stale_blockers`, `todos`, `last_checkin`, `prs`, `disk`.

If the command fails, run this scoped fallback instead — ONLY read from this project's own directory:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Read from $SCRIPT_DIR/memory/ ONLY — never browse parent or sibling directories
ls -1 "$SCRIPT_DIR/memory/handoffs/$(date +%Y-%m)/" 2>/dev/null | head -10
ls -1t "$SCRIPT_DIR/memory/knowledge/decisions/" 2>/dev/null | head -5
```

Add `(offline)` after ✦ in header. If empty data is returned (graph has no sessions, no handoffs), display the dashboard with empty sections — do NOT explore the filesystem for alternative data sources. NEVER read from directories outside this project.

## Step 2: Render dashboard

Output the TUI box directly. 72 chars wide. Use these frame lines (copy exactly):

```
┌──────────────────────────────────────────────────────────────────────┐
├──────────────────────────────────────────────────────────────────────┤
└──────────────────────────────────────────────────────────────────────┘
```

Content rows: `│  {text padded with trailing spaces}  │`

**DO NOT count characters or show reasoning.** Approximate padding is fine — the frame is decorative, not pixel-perfect. Go straight from data to rendered output.

### Sections (separated by `├────┤`)

**Header**: `{ORG} EGREGORE ✦ ACTIVITY DASHBOARD` left, `{me} · {date}` right

**Insight** (1-2 lines): Synthesize what's happening. Warm, concise, connective. Additional insight lines:
- If `stale_blockers.staleBlockedCount > 0`: `{N} todos blocked for 3+ days. /todo check to review.`
- If no check-in in 3+ days (check `last_checkin`) AND `todos.activeTodoCount >= 3`: `{N} active todos, no check-in in {days}d. /todo check to review.`

**Handoffs & Asks** (skip if all empty):
- Handoffs (status=pending) → `[N] ● {from} → you: {topic} ({when})`
- Handoffs (status=read) → `[N] ◐ {from} → you: {topic} ({when})`
- Handoffs (status=done) → `    ○ {from} → you: {topic} (done)`. If `response` field is non-null, append on next line: `      "{response truncated to 50 chars}..."`
- Pending questions → `[N] {from} asks about "{topic}" ({when})`
- Answered questions → `    ✓ {name} answered "{topic}"`
- Other handoffs → `    {from} → {to}: {topic} ({when})`
- Numbered items (● and ◐) first, blank line, then ○ + others.

**Sessions**:
- `◦ YOUR SESSIONS` — top 5. Format: `{date}  {topic}`
  - Interleave check-ins from `checkins` (by current user) in chronological order: `{date}  Check-in: {summary}`
- `◦ TEAM` — top 5. Format: `{date}  {name}: {topic}`
  - Interleave check-ins from `checkins` (by others) in chronological order: `{date}  {name}: Check-in: {summary}`
- Blank line between sub-sections.

**Quests & PRs** (skip if both empty):
- `⚑ QUESTS (N active)` — top 5 by score. `{quest-id}` left, `{N} artifacts · {N}d ago` right.
- `→ OPEN PRs` — `#{number}  {title} ({author})`
- Blank line between sub-sections. Omit either if empty.

**Footer** (separated by `├────┤`):
- If orphans.orphanCount > 0: `{N} artifacts unlinked to quests — /quest suggest`
- If knowledge_gap.gapCount > 0: `{N} sessions without captured insights — /reflect to extract`
- Else: `/todo check to review · /ask a question · /quest to see more`
- Always end with: `What's your focus?`

### Date formatting

Today → `Today    ` (9 chars) · Yesterday → `Yesterday` · Older → `Mon DD   ` (9 chars). 2-space gap before topic.

Time ago: <1h `Nm ago` · 1-23h `Nh ago` · 1d `yesterday` · 2-6d `Nd ago` · 7d+ `Mon DD`

### Data freshness

Compare my_sessions for today vs disk.handoffs for today. If disk has more files than graph has sessions for today, show in footer: `{N} sessions on disk not in graph — /save to sync`

## Step 3: Session orientation

Fire AskUserQuestion immediately after the dashboard:

```
header: "Focus"
question: "What would you like to focus on?"
multiSelect: false
```

Generate 2-4 options, prioritized (take first 2-4 that apply):

| Priority | Source | Label | Description |
|----------|--------|-------|-------------|
| 1 | handoffs_to_me **(status=pending only)** | `Read {author}'s handoff` | `{topic} — {when}` |
| 2 | pending_questions | `Answer {asker}'s questions` | `About "{topic}" — {when}` |
| 3-4 | my_sessions (last 3 days) | Work stream name | Cluster recent sessions by theme. Name specifically. Max 2 clusters. Hint at what's next, not what's done. |
| 5 | prs (not by me) | `Review PR #{N}` | `{title} by {author}` |
| 6 | fallback | `Start something new` | `Begin a fresh work stream` |

Minimum 2 options. "Other" is automatic.

Handoffs with status `read` or `done` are excluded from Focus options but inform work stream clustering (priority 3-4). When generating work stream labels, consider topics from recent handoffs you've already seen.

### After selection

| Selection | Action |
|-----------|--------|
| Handoff | Read filePath from data. Display content + entry points. **Immediately** mark as read: `bash bin/graph.sh query "MATCH (s:Session {id: '$sessionId'}) SET s.handoffStatus = 'read', s.handoffReadDate = date() RETURN s.id"`. Then proceed — no follow-up question. Resolution happens automatically at next dashboard load (Q_resolve) or via `/activity done N`. |
| Questions | Load QuestionSet, present via AskUserQuestion. |
| Work stream | Read most recent handoff from cluster. Show Open Threads / Next Steps. Mention relevant knowledge artifacts. |
| PR | `gh pr view #N --json title,body,additions,deletions,files`. Summarize. |
| New / Other | Ask: "What are you working on?" |

## Argument filtering

- `/activity quests` — expand quests, show all with full counts
- `/activity @name` — filter to that person's sessions
- `/activity done [N]` — resolve handoff N. Fetch activity data, map Nth ●/◐ handoff to sessionId, run: `bash bin/graph.sh query "MATCH (s:Session {id: '$sessionId'}) SET s.handoffStatus = 'done' RETURN s.id"`. Output: `✓ Resolved: {topic} from {author}`

## Rules

- `bash bin/activity-data.sh` for ALL data — never call graph.sh directly
- **NEVER read files outside this project directory** — no browsing parent/sibling directories, no looking at other egregore installations. If data is empty, show empty sections.
- No sub-boxes — only outer frame `│` and `├────┤` separators
- DO NOT output reasoning, character counting, or analysis — render directly
