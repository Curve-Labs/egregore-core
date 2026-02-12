End a session with a summary for the next person (or future you). With no arguments, triages open handoffs first.

Topic: $ARGUMENTS

**Auto-saves.** No need to run `/save` after.

## Execution rules

**Neo4j-first.** All queries via `bash bin/graph.sh query "..."`. No MCP. No direct curl to Neo4j.
**Notifications via `bash bin/notify.sh send`**. No direct curl to Telegram.

**CRITICAL: Suppress raw output.** Never show raw JSON to the user. All `bin/graph.sh` and `bin/notify.sh` calls MUST redirect stdout: pipe to `/dev/null` or capture in a variable. Only show formatted progress lines. Example:
```bash
bash bin/graph.sh query "..." > /dev/null 2>&1
```
If you need to parse the result, capture it and only echo a status:
```bash
RESULT=$(bash bin/graph.sh query "..." 2>/dev/null) && echo "OK" || echo "FAILED"
```

- 1 Bash call: `git config user.name`
- 1 Neo4j query: Session creation (with HANDED_TO if recipient)
- 1 Neo4j query: Artifact lookup (today's artifacts by author)
- Auto-save via `/save` flow
- 1 notification via `bin/notify.sh send` (if recipient specified)
- Progress shown incrementally, step by step

## Step 0: Get current user and team members

```bash
git config user.name
```

Derive author handle: lowercase first word of git user.name (e.g. "Oguzhan Yayla" → "oguzhan").

Query all team members from the graph (suppress raw output, parse names):
```bash
MEMBERS=$(bash bin/graph.sh query "MATCH (p:Person) RETURN p.name AS name" 2>/dev/null)
echo "$MEMBERS" | jq -r '.values[][]' 2>/dev/null
```

This returns all Person nodes in the org. Use this list for recipient matching in Step 1.

## Step 0.5: Triage mode (no arguments + open handoffs)

**Trigger:** `$ARGUMENTS` is empty (user ran bare `/handoff`).

Before creating a new handoff, check for open handoffs directed at the current user:

```cypher
MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: $me})
WHERE coalesce(s.handoffStatus, 'pending') IN ['pending', 'read']
  AND s.date >= date() - duration('P14D')
MATCH (s)-[:BY]->(author:Person)
RETURN s.topic AS topic, s.date AS date, author.name AS author,
       s.filePath AS filePath, s.id AS sessionId,
       coalesce(s.handoffStatus, 'pending') AS status
ORDER BY
  CASE coalesce(s.handoffStatus, 'pending')
    WHEN 'pending' THEN 0 ELSE 1
  END,
  s.date DESC
LIMIT 8
```

**If no open handoffs** → skip triage, fall through to Step 1 (normal handoff flow with no-topic handling).

**If open handoffs exist** → enter triage mode. Route by count:

### Route A: Guided walk-through (1-3 handoffs)

Walk through each handoff one at a time, showing context and capturing the user's response.

For each handoff, in order:

**1. Show the handoff content.** Read the file at `filePath` from the query (prepend `memory/` to the path). Display the receiver TUI:

```
  ─── 1 of N ───

  ┌──────────────────────────────────────────────────────────────────────┐
  │  ⇌ HANDOFF FROM {AUTHOR uppercase}                      {when}     │
  ├──────────────────────────────────────────────────────────────────────┤
  │                                                                      │
  │  Topic: {topic}                                                      │
  │                                                                      │
  │  {summary from file, wrapped at ~60 chars}                           │
  │                                                                      │
  └──────────────────────────────────────────────────────────────────────┘
```

**2. Ask for status via AskUserQuestion:**

```
header: "Handoff"
question: "What's the status of {author}'s handoff on {topic}?"
multiSelect: false
options:
  - label: "Done"
    description: "I've addressed this"
  - label: "Still open"
    description: "Keep it visible — I'm still working on it"
  - label: "Not relevant"
    description: "Dismiss without action"
```

**3. Handle response:**

- **"Done" or "Not relevant"** → mark `done`: `bash bin/graph.sh query "MATCH (s:Session {id: '$sessionId'}) SET s.handoffStatus = 'done' RETURN s.id"`. Output: `✓ Resolved: {topic} from {author}`
- **"Still open"** → if currently `pending`, mark `read`: `bash bin/graph.sh query "MATCH (s:Session {id: '$sessionId'}) WHERE s.handoffStatus = 'pending' OR s.handoffStatus IS NULL SET s.handoffStatus = 'read', s.handoffReadDate = date() RETURN s.id"`. Output: `◐ Kept open: {topic} from {author}`
- **Freeform text (user typed something)** → mark `done` AND capture: `bash bin/graph.sh query "MATCH (s:Session {id: '$sessionId'}) SET s.handoffStatus = 'done', s.handoffResponse = '$response' RETURN s.id"`. Output: `✓ Resolved: {topic} from {author}` + `  Captured: "{first 60 chars}..."`

**4. Continue to next handoff**, or if all done:

```
All caught up.

Handing off this session? (topic, or enter to skip)
```

If user provides a topic → fall through to Step 1 with that topic. If empty/enter → exit without creating a new handoff.

### Route B: Batch triage (4+ handoffs)

Show all handoffs as a multiSelect AskUserQuestion for quick resolution.

```
header: "Triage"
question: "Which handoffs have you addressed?"
multiSelect: true
options: (one per handoff, max 4 shown)
  - label: "{author}: {topic}"
    description: "{status_icon} {when}"
```

Where `status_icon` is `●` for pending, `◐` for read.

If more than 4 handoffs, show the top 4 (pending first, then oldest read) and note: `Showing 4 of N — run /handoff again to triage the rest.`

**After selection:**

- Each selected handoff → mark `done`: `bash bin/graph.sh query "MATCH (s:Session {id: '$sessionId'}) SET s.handoffStatus = 'done' RETURN s.id"`
- Unselected handoffs that are `pending` → mark `read`: `bash bin/graph.sh query "MATCH (s:Session {id: '$sessionId'}) WHERE s.handoffStatus = 'pending' OR s.handoffStatus IS NULL SET s.handoffStatus = 'read', s.handoffReadDate = date() RETURN s.id"`
- Output: `✓ Resolved N handoffs` (and `◐ Kept N open` if any unselected)

Then:

```
Handing off this session? (topic, or enter to skip)
```

Same fall-through as Route A.

### Triage examples

**Guided (2 handoffs):**
```
> /handoff

  You have 2 open handoffs.

  ─── 1 of 2 ───

  ┌──────────────────────────────────────────────────────────────────────┐
  │  ⇌ HANDOFF FROM ALI                                   yesterday   │
  ├──────────────────────────────────────────────────────────────────────┤
  │                                                                      │
  │  Topic: Slash Command Testing                                        │
  │                                                                      │
  │  Tested /activity, /reflect, /handoff. Found backtick eval           │
  │  bug in activity command. Provided test results with fixes.          │
  │                                                                      │
  └──────────────────────────────────────────────────────────────────────┘

  What's the status of ali's handoff on Slash Command Testing?
    1. Done
    2. Still open
    3. Not relevant

> "Fixed the backtick bug, activity works. Reflect still needs
   the rubric rewrite."

  ✓ Resolved: Slash Command Testing from ali
    Captured: "Fixed the backtick bug, activity works. Reflect
    still needs the rubric rewrite."

  ─── 2 of 2 ───

  ┌──────────────────────────────────────────────────────────────────────┐
  │  ⇌ HANDOFF FROM OZ                                       2d ago    │
  ├──────────────────────────────────────────────────────────────────────┤
  │  ...                                                                 │
  └──────────────────────────────────────────────────────────────────────┘

  What's the status of oz's handoff on Setup flow?
> 1

  ✓ Resolved: New Egregore setup flow from oz

  All caught up.

  Handing off this session? (topic, or enter to skip)
> implicit handoff resolution to oz

  Creating handoff...
  ...
```

**Batch (5 handoffs):**
```
> /handoff

  You have 5 open handoffs. Which have you addressed?

  ☐ ● ali: Slash Command Testing (yesterday)
  ☐ ◐ oz: New Egregore setup flow (2d ago)
  ☐ ◐ oz: Infra fix after sync (3d ago)
  ☐ ● pali: Animation handoff (4d ago)

  Showing 4 of 5 — run /handoff again to triage the rest.

> [selects ali + oz setup flow]

  ✓ Resolved 2 handoffs
  ◐ Kept 2 open

  Handing off this session? (topic, or enter to skip)
> enter

  Done.
```

---

## Step 1: Parse arguments

**Only reached if `$ARGUMENTS` is non-empty OR user provided a topic after triage.**

Parse `$ARGUMENTS` for topic and recipient.

**Recipient detection** — understand from natural language who the handoff is for:
- "setup flow to oskar" → topic: "setup flow", recipient: oskar
- "mcp auth for oguzhan to pick up" → topic: "mcp auth", recipient: oguzhan
- "handoff blog styling" → topic: "blog styling", recipient: none

Team members: **from the graph query in Step 0** (not hardcoded).

Match recipient names case-insensitively against the Person names from the graph.

If `$ARGUMENTS` has no clear recipient, show a picker using AskUserQuestion:
- List each Person name from the graph (excluding the current user)
- Add a final option: "General (no specific recipient)"

If no recipient detected or user picks "General", the handoff is for the team or future self.

## Step 2: Summarize the session

Analyze the conversation context to produce:

1. **Session summary** — 2-3 sentences on what was accomplished
2. **Key decisions** — any decisions made with rationale
3. **Current state** — what's working, in progress, blocked
4. **Open threads** — unfinished items with enough context to pick up
5. **Next steps** — clear actions with entry points
6. **Project** — which project this relates to (LACE/Tristero/Research/Egregore)

## Step 3: Create handoff file

File path: `memory/handoffs/YYYY-MM/DD-[author]-[topic-slug].md`

Example: `memory/handoffs/2026-02/07-cem-defensibility-architecture.md`

Generate slug from topic: lowercase, hyphens, no special chars, max 50 chars.

Ensure the directory exists:
```bash
mkdir -p memory/handoffs/YYYY-MM
```

Write the file using Bash (memory is outside project, avoids permission issues):

```bash
cat > "memory/handoffs/YYYY-MM/DD-author-topic-slug.md" << 'HANDOFFEOF'
# Handoff: [Topic]

**Date**: YYYY-MM-DD
**Author**: [from git config user.name]
**To**: [recipient, if specified]
**Project**: [LACE/Tristero/Research/Egregore]

## Session Summary

[2-3 sentences on what was accomplished]

## Key Decisions

- **[Decision]**: [Rationale]

## Current State

[What's working, what's in progress, what's blocked]

## Open Threads

- [ ] [Unfinished item with context]

## Session Artifacts

- [Type]: [Title] -> [shortened file path]

## Next Steps

1. [Clear action with entry point]

## Entry Points

For the next session, start by:
- Reading: [specific file]
- Running: [specific command]
HANDOFFEOF
```

Omit the **To** line if no recipient. Omit **Key Decisions** if none. Omit **Session Artifacts** section if the artifact query (Step 5) returns empty. The Session Artifacts section is populated after the Neo4j query in Step 5 — leave a placeholder during file creation, then update the file after the query.

Show progress:
```
[1/5] ✓ Conversation file
```

## Step 4: Update conversation index

Prepend to `memory/handoffs/index.md`:

```markdown
- **YYYY-MM-DD** — [author]: [topic] ([handoff to recipient] | [handoff])
```

Show progress:
```
[2/5] ✓ Index updated
```

## Step 5: Create Session node in Neo4j + query artifacts

### Session creation (with HANDED_TO)

Run via `bash bin/graph.sh query "..." '{"param": "value"}'`:

```cypher
MATCH (p:Person {name: $author})
CREATE (s:Session {
  id: $sessionId,
  date: date($date),
  topic: $topic,
  summary: $summary,
  filePath: $filePath,
  handoffStatus: 'pending'
})
CREATE (s)-[:BY]->(p)
WITH s
OPTIONAL MATCH (proj:Project {name: $project})
FOREACH (_ IN CASE WHEN proj IS NOT NULL THEN [1] ELSE [] END |
  CREATE (s)-[:ABOUT]->(proj)
)
WITH s
OPTIONAL MATCH (target:Person {name: $recipient})
FOREACH (_ IN CASE WHEN target IS NOT NULL THEN [1] ELSE [] END |
  CREATE (s)-[:HANDED_TO]->(target)
)
RETURN s.id
```

After creating the Session node, resolve any `read` handoffs where the user has completed a subsequent session (same criteria as Q_resolve in activity-data.sh):

```cypher
MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: $author})
WHERE s.handoffStatus = 'read' AND s.id <> $sessionId
WITH s, p, coalesce(s.handoffReadDate, s.date) AS sinceDate
MATCH (later:Session)-[:BY]->(p)
WHERE later.date > sinceDate
WITH s, count(later) AS laterSessions WHERE laterSessions > 0
SET s.handoffStatus = 'done'
RETURN s.id AS id, s.topic AS topic
```

If any resolved, include in progress output: `[3/5] ✓ Session -> knowledge graph (resolved N prior handoffs)`

Where:
- `$sessionId` = `YYYY-MM-DD-author-topic-slug` (matches filename without extension)
- `$author` = short name (oz, cem, ali)
- `$date` = `YYYY-MM-DD`
- `$topic` = the topic string
- `$summary` = 1-2 sentence summary
- `$filePath` = `handoffs/YYYY-MM/DD-author-topic-slug.md`
- `$project` = project name if identified (can be empty string if none)
- `$recipient` = recipient short name if specified (can be empty string if none)

If no recipient, pass `$recipient` as empty string — the OPTIONAL MATCH will simply not match and FOREACH won't execute.

**CRITICAL: This step is NOT optional.** Without the Neo4j Session node, the handoff won't appear in `/activity`.

### Artifact query

Query for artifacts created today by the author, excluding tutorial-generated artifacts:

```cypher
MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p:Person {name: $author})
WHERE a.created >= datetime({year: $year, month: $month, day: $day})
  AND NOT 'tutorial-generated' IN coalesce(a.topics, [])
RETURN a.title AS title, a.type AS type, a.filePath AS path, a.topics AS topics
ORDER BY a.created DESC
```

Run this in parallel with the Session creation query.

**Relevance filter:** After fetching, only include artifacts in the TUI whose topics overlap with the session topic. Compare each artifact's `topics` array against keywords extracted from the handoff topic. If no artifacts pass the relevance filter, omit the artifacts section entirely. This prevents unrelated same-day artifacts from leaking into handoffs.

If relevant artifacts are found, update the handoff file's Session Artifacts section with the results. Format each artifact as:
```
- [Type capitalized]: [Title] -> [shortened file path]
```

Show progress:
```
[3/5] ✓ Session -> knowledge graph
```

## Step 6: Auto-save

Run the full `/save` flow:

1. Commit changes in memory repo and push (contribution branch + PR + auto-merge)
2. Commit any egregore changes and push working branch + PR to develop

This is the same flow as `/save`. Follow its logic exactly.

Show progress:
```
[4/5] ✓ Pushed + PR created
```

## Step 7: Notify recipient

**Only if a recipient was specified.**

Send via `bash bin/notify.sh send`:

```bash
bash bin/notify.sh send "$RECIPIENT" "$MESSAGE"
```

**Telegram message format**:

```
Handoff from [Author]: [Topic]

"[1-2 sentence summary from the session]"

[If artifacts found:]
Session included N artifacts:
  - [Type]: [Title]
  - [Type]: [Title]

Entry point: memory/[handoff file path]
```

Example:
```
Handoff from Cem: Defensibility architecture

"Analyzed five-layer moat framework. Server-side intelligence is the biggest gap. Full artifact in knowledge/decisions/."

Session included 2 artifacts:
  - Decision: Defensibility architecture framework
  - Finding: Harvest flywheel as training surface

Entry point: memory/handoffs/2026-02/07-cem-defensibility-architecture.md
```

Show progress:
```
[5/5] ✓ [Recipient] notified
```

**If no recipient**: step 5 becomes "✓ Team sees this on /activity" and no notification is sent (show only 4 progress steps total, renumbered).

## Step 8: Display sender TUI confirmation

~72 char width. Sigil: `⇌ HANDOFF SENT`.

### Boundary handling (CRITICAL)

**No sub-boxes. No inner `┌─┐`/`└─┘` borders.** Sub-boxes break because the model can't count character widths precisely enough.

Only **4 line patterns** exist:

1. **Top**: `┌` + 70×`─` + `┐` (72 chars)
2. **Separator**: `├` + 70×`─` + `┤` (72 chars)
3. **Content**: `│` + 2 spaces + text + pad spaces to 68 chars + `│` (72 chars)
4. **Bottom**: `└` + 70×`─` + `┘` (72 chars)

The separator lines are ALWAYS identical — copy-paste the same 72-char string. Content lines have ONLY the outer frame `│` as borders. Pad every content line with trailing spaces so the closing `│` is at position 72.

### Content priority

The session summary is the primary content — what was actually handed off. The progress checklist is already shown incrementally during execution; repeating it wastes space. Collapse progress to a single status line.

### With recipient and artifacts:

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⇌ HANDOFF SENT                                     cem · Feb 07     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Topic: Defensibility architecture                                   │
│  To: Oz                                                              │
│                                                                      │
│  Analyzed five-layer moat framework for Egregore. Server-side        │
│  intelligence is the biggest gap and biggest opportunity.             │
│  Defined pricing tiers and go-to-market sequence.                    │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  ◉ Decision: Defensibility architecture framework                    │
│  ◉ Finding: Harvest flywheel as training surface                     │
├──────────────────────────────────────────────────────────────────────┤
│  ✓ Saved · graphed · pushed · Oz notified                            │
│  Team sees this on /activity.                                        │
└──────────────────────────────────────────────────────────────────────┘
```

### Without recipient, no artifacts:

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⇌ HANDOFF SENT                                      oz · Feb 07     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Topic: MCP auth flow                                                │
│                                                                      │
│  Implemented OAuth device flow for MCP authentication.               │
│  Token refresh works end-to-end. Needs error handling                │
│  for expired sessions.                                               │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  ✓ Saved · graphed · pushed                                          │
│  Team sees this on /activity.                                        │
└──────────────────────────────────────────────────────────────────────┘
```

### TUI rules

- Header row: `⇌ HANDOFF SENT` left, `author · Mon DD` right — both inside the 72-char frame
- `├───┤` separator between header and content
- Topic always shown
- "To:" line only if recipient specified
- **Session summary** — 2-3 sentences from Step 2, wrapped at ~60 chars. This is the primary content.
- Artifacts section (between `├───┤` dividers): `◉` for each artifact. Omit entirely if no artifacts.
- **Status line** — single line collapsing all progress: `✓ Saved · graphed · pushed` (add `· {Recipient} notified` if recipient)
- Footer: "Team sees this on /activity."
- Truncate topic at 45 chars with `...` if needed
- **No sub-boxes** — only outer frame `│` borders and `├────┤` separators

## Receiver View (for /activity integration)

When a recipient reads a handoff directed at them (e.g., from an `/activity` action item), display this format.

Same boundary rules apply — 4 line patterns only, no sub-boxes, 72-char outer width.

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⇌ HANDOFF FROM CEM                                     Feb 07       │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Topic: Defensibility architecture                                   │
│                                                                      │
│  Analyzed Egregore defensibility — five-layer moat from              │
│  convenience to network effects. Server-side intelligence            │
│  is the biggest gap and biggest opportunity.                         │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  OPEN THREADS                                                        │
│  ○ API proxy architecture — before or after org #2?                  │
│  ○ Person node schema — org-scoped vs platform-level                 │
│  ○ First premium agent design                                        │
├──────────────────────────────────────────────────────────────────────┤
│  ◉ Decision: Defensibility architecture framework                    │
│  ◉ Finding: Harvest flywheel as training surface                     │
├──────────────────────────────────────────────────────────────────────┤
│  → memory/knowledge/decisions/2026-02-07-defensibility-...           │
│  → memory/handoffs/2026-02/07-cem-defensibility-...             │
└──────────────────────────────────────────────────────────────────────┘
```

### Receiver TUI rules

- Header: `⇌ HANDOFF FROM [AUTHOR uppercase]` left, `Mon DD` right
- Summary: wrap at ~60 chars — the primary content
- Open Threads section (between `├───┤` dividers): `○` for each thread. Omit entirely if none.
- Artifacts section: `◉` for each artifact. Omit entirely if none.
- Entry points: `→` for file paths, shortened to last 2-3 segments with `...` if needed
- Omit empty sections entirely
- **No sub-boxes** — only outer frame `│` borders and `├────┤` separators

### When /activity shows handoffs

In `/activity`, handoffs directed at the current user use the three-icon status system:
```
[1] ● oz → you: Infra fix after sync (yesterday)      ← pending (unread)
[2] ◐ ali → you: Slash command testing (2d ago)        ← read but open
    ○ oz → you: Setup flow (done)                      ← resolved (unnumbered)
```

When the user selects a numbered item, display the receiver view above by reading the handoff file from the path in the Session node's `filePath` property.

## Step 9: Reflection prompt

After displaying the TUI confirmation, check if today's sessions produced no non-tutorial artifacts. Query:

```cypher
MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p:Person {name: $me})
WHERE a.created >= datetime({year: $year, month: $month, day: $day})
  AND NOT 'tutorial-generated' IN coalesce(a.topics, [])
RETURN count(a) AS artifactCount
```

If `artifactCount = 0`, show a one-line suggestion (not a blocker — no AskUserQuestion):

```
This session had insights worth capturing. Quick /reflect?
```

If artifacts exist, skip this step silently.

## Edge cases

| Scenario | Handling |
|----------|----------|
| Neo4j unavailable | Still create handoff file and index. Show warning: "Graph offline — file saved, will sync on next /save". Skip artifact query. |
| No artifacts today | Omit Session Artifacts sub-box from TUI and Telegram message |
| Notification fails | Show warning but don't fail the handoff: "Notification failed — [recipient] can see this on /activity" |
| Memory symlink missing | Error: "Run /setup first — memory not linked" |
| Recipient not a known Person | Warn: "[name] not found in graph — handoff saved but not directed. Create them with /invite?" |
| No topic in $ARGUMENTS | If open handoffs exist → triage mode (Step 0.5). Otherwise, summarize the session and generate a topic from conversation context |
| Empty session (nothing happened) | Ask: "Nothing to hand off yet. Want to leave a note instead?" |
| File already exists at path | Append timestamp to slug to avoid collision |

## Full example: with recipient

```
> /handoff defensibility architecture to oz

Creating handoff...

Summarizing session...

  [1/5] ✓ Conversation file
        → memory/handoffs/2026-02/07-cem-defensibility-architecture.md

  [2/5] ✓ Index updated

  [3/5] ✓ Session -> knowledge graph

  [4/5] ✓ Pushed + PR created

  [5/5] ✓ Oz notified

┌──────────────────────────────────────────────────────────────────────┐
│  ⇌ HANDOFF SENT                                     cem · Feb 07     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Topic: Defensibility architecture                                   │
│  To: Oz                                                              │
│                                                                      │
│  Analyzed five-layer moat framework for Egregore. Server-side        │
│  intelligence is the biggest gap and biggest opportunity.             │
│  Defined pricing tiers and go-to-market sequence.                    │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  ◉ Decision: Defensibility architecture framework                    │
│  ◉ Finding: Harvest flywheel as training surface                     │
├──────────────────────────────────────────────────────────────────────┤
│  ✓ Saved · graphed · pushed · Oz notified                            │
│  Team sees this on /activity.                                        │
└──────────────────────────────────────────────────────────────────────┘
```

## Full example: no recipient

```
> /handoff mcp auth flow

Creating handoff...

Summarizing session...

  [1/4] ✓ Conversation file
        → memory/handoffs/2026-02/07-oz-mcp-auth-flow.md

  [2/4] ✓ Index updated

  [3/4] ✓ Session -> knowledge graph

  [4/4] ✓ Pushed + PR created

┌──────────────────────────────────────────────────────────────────────┐
│  ⇌ HANDOFF SENT                                      oz · Feb 07     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Topic: MCP auth flow                                                │
│                                                                      │
│  Implemented OAuth device flow for MCP authentication.               │
│  Token refresh works end-to-end. Needs error handling                │
│  for expired sessions.                                               │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  ✓ Saved · graphed · pushed                                          │
│  Team sees this on /activity.                                        │
└──────────────────────────────────────────────────────────────────────┘
```
