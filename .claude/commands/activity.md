Activity dashboard. Display it immediately — no preamble, no narration. Output the box and nothing else.

Topic: $ARGUMENTS

## Data collection

Run ALL of these in parallel (one Bash call each):

**Call 1 — sync + user + org + PRs:**
```bash
git fetch origin --quiet 2>/dev/null
CURRENT=$(git branch --show-current)
git checkout develop --quiet 2>/dev/null && git pull origin develop --quiet 2>/dev/null && git checkout "$CURRENT" --quiet 2>/dev/null
[[ "$CURRENT" == dev/* ]] && (git rebase develop --quiet 2>/dev/null || git rebase --abort 2>/dev/null)
git -C memory fetch origin main --quiet 2>/dev/null
LOCAL=$(git -C memory rev-parse HEAD 2>/dev/null); REMOTE=$(git -C memory rev-parse origin/main 2>/dev/null)
[ "$LOCAL" != "$REMOTE" ] && git -C memory pull origin main --quiet 2>/dev/null
echo "---USER---"; git config user.name
echo "---ORG---"; jq -r '.org_name' egregore.json
echo "---PRS---"; gh pr list --base develop --state open --json number,title,author 2>/dev/null || echo "[]"
```

Map git username → short name: "Oguzhan Yayla" → oz, "Cem Dagdelen" → cem, "Cem F" → cem, "Ali" → ali, etc.

**Calls 2–8 — Neo4j queries via `bash bin/graph.sh query "..."`:**

Q1 — My sessions (with tiebreaker for same-day ordering):
```
MATCH (s:Session)-[:BY]->(p:Person {name: '$me'})
OPTIONAL MATCH (s)-[:HANDED_TO]->(target:Person)
RETURN s.date AS date, s.topic AS topic, s.id AS id, s.filePath AS filePath,
       target.name AS handedTo
ORDER BY s.date DESC, s.id DESC LIMIT 10
```
Note: Returns 10 (not 5) so orientation can pick from more context. Display still shows top 5. The `s.id DESC` tiebreaker ensures most recently created sessions within the same day sort first. `filePath` and `handedTo` are used by the session orientation logic.

Q2 — Team (7 days):
```
MATCH (s:Session)-[:BY]->(p:Person) WHERE p.name <> '$me' AND s.date >= date() - duration('P7D') RETURN s.date AS date, s.topic AS topic, p.name AS by ORDER BY s.date DESC LIMIT 5
```

Q3 — Active quests (scored with personal relevance):
```
MATCH (q:Quest {status: 'active'})
OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q)
OPTIONAL MATCH (a)-[:CONTRIBUTED_BY]->(p:Person) WHERE p.name IS NOT NULL AND p.name <> 'external'
OPTIONAL MATCH (q)-[:STARTED_BY]->(starter:Person {name: '$me'})
OPTIONAL MATCH (myArt:Artifact)-[:PART_OF]->(q) WHERE (myArt)-[:CONTRIBUTED_BY]->(:Person {name: '$me'})
WITH q, count(DISTINCT a) AS artifacts, count(DISTINCT p) AS contributors,
     CASE WHEN count(a) > 0 THEN duration.inDays(max(a.created), date()).days
          ELSE duration.inDays(q.started, date()).days END AS daysSince,
     coalesce(q.priority, 0) AS priority,
     CASE WHEN starter IS NOT NULL THEN 1 ELSE 0 END AS iStarted,
     count(DISTINCT myArt) AS myArtifacts
RETURN q.id AS quest, q.title AS title, artifacts, daysSince, iStarted, myArtifacts,
       starter IS NOT NULL AS iStarted,
       round((toFloat(artifacts) + toFloat(contributors)*1.5
         + toFloat(priority)*5.0
         + 30.0/(1.0+toFloat(daysSince)*0.5)
         + CASE WHEN starter IS NOT NULL THEN 15.0 ELSE 0.0 END
         + toFloat(myArtifacts)*3.0
       ) * 100)/100 AS score
ORDER BY score DESC
```
Personal relevance: +15 if I started the quest, +3 per artifact I contributed. This ensures quests I own always rank above quests where I have zero involvement.

Q4 — Pending questions for me:
```
MATCH (qs:QuestionSet {status: 'pending'})-[:ASKED_TO]->(p:Person {name: '$me'}) MATCH (qs)-[:ASKED_BY]->(asker:Person) RETURN qs.id AS setId, qs.topic AS topic, qs.created AS created, asker.name AS from ORDER BY qs.created DESC
```

Q5 — Answered questions (7 days):
```
MATCH (qs:QuestionSet {status: 'answered'})-[:ASKED_BY]->(p:Person {name: '$me'}) MATCH (qs)-[:ASKED_TO]->(target:Person) WHERE qs.created >= datetime() - duration('P7D') RETURN qs.id AS setId, qs.topic AS topic, target.name AS answeredBy ORDER BY qs.created DESC
```

Q6 — Handoffs directed to me (7 days):
```
MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: '$me'}) WHERE s.date >= date() - duration('P7D') MATCH (s)-[:BY]->(author:Person) RETURN s.topic, s.date, author.name, s.filePath ORDER BY s.date DESC LIMIT 5
```

Q7 — All recent handoffs (7 days):
```
MATCH (s:Session)-[:HANDED_TO]->(target:Person) WHERE s.date >= date() - duration('P7D') MATCH (s)-[:BY]->(author:Person) RETURN s.topic, s.date, author.name AS from, target.name AS to, s.filePath ORDER BY s.date DESC LIMIT 5
```

Q8 — Orphan ratio + topic clusters (14 days):
```
MATCH (a:Artifact) WHERE a.created >= date() - duration('P14D') WITH count(a) AS totalRecent MATCH (orphan:Artifact) WHERE orphan.created >= date() - duration('P14D') AND NOT (orphan)-[:PART_OF]->(:Quest) WITH totalRecent, collect(orphan) AS orphans, count(orphan) AS orphanCount WITH totalRecent, orphanCount, orphans, CASE WHEN totalRecent > 0 THEN toFloat(orphanCount) / toFloat(totalRecent) ELSE 0.0 END AS orphanRatio UNWIND orphans AS o UNWIND o.topics AS topic WITH orphanRatio, orphanCount, totalRecent, topic, count(DISTINCT o) AS topicCount ORDER BY topicCount DESC RETURN orphanRatio, orphanCount, totalRecent, collect({topic: topic, count: topicCount})[..5] AS topClusters
```

Q9 — Stale high-priority quests (only if Q8 orphanRatio > 0.4):
```
MATCH (q:Quest {status: 'active'}) WHERE q.priority >= 2 OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q) WITH q, CASE WHEN count(a) > 0 THEN duration.inDays(max(a.created), date()).days ELSE duration.inDays(q.started, date()).days END AS daysSince WHERE daysSince >= 10 RETURN q.id AS quest, q.priority AS priority, daysSince
```

Q10 — Quest topic coverage (only if Q8 orphanRatio > 0.4):
```
MATCH (q:Quest {status: 'active'}) WHERE q.topics IS NOT NULL RETURN q.id AS quest, q.topics AS topics
```

**Call 9 — Disk cross-reference (run in parallel with Neo4j calls):**
```bash
# Recent handoff files on disk — catches work not yet synced to graph
ls -1 memory/handoffs/$(date +%Y-%m)/ 2>/dev/null | grep "$(date +%d)-\|$(date -v-1d +%d 2>/dev/null || date -d 'yesterday' +%d)-" | head -10
echo "---KNOWLEDGE---"
ls -1t memory/knowledge/decisions/ 2>/dev/null | head -5
```
This catches today's and yesterday's handoff files + recent knowledge artifacts on disk. Used by the orientation logic to detect graph-vs-disk freshness gaps.

## Data freshness check

After all queries return, compare Q1 session count for today/yesterday against Call 9 disk files. If disk has more handoff files for today than Q1 has sessions for today, the graph is stale. In that case:

1. **For the dashboard display**: Use graph data as-is (it's what we have)
2. **For the orientation options**: Supplement with disk data. Read the titles from the most recent handoff files on disk (parse the `# Handoff: [topic]` header line) to generate "Continue" options even when the graph is behind.
3. **Show a sync hint in the footer**: `{N} sessions on disk not in graph — /save to sync`

## Boundary handling (CRITICAL)

**No sub-boxes. No inner `┌─┐`/`└─┘` borders.** Sub-boxes break because the model can't count character widths precisely enough.

Instead, use a single outer frame with `├────┤` separators between logical groups:

Only **4 line patterns** exist:

1. **Top**: `┌` + 70×`─` + `┐` (72 chars)
2. **Separator**: `├` + 70×`─` + `┤` (72 chars)
3. **Content**: `│` + 2 spaces + text + pad spaces to 68 chars + `│` (72 chars)
4. **Bottom**: `└` + 70×`─` + `┘` (72 chars)

The separator lines are ALWAYS identical — copy-paste the same 72-char string. Content lines have ONLY the outer frame `│` as borders. Pad every content line with trailing spaces so the closing `│` is at position 72.

## Layout

Output the box directly — nothing before it.

```
┌──────────────────────────────────────────────────────────────────────┐
│  CURVE LABS EGREGORE ✦ ACTIVITY DASHBOARD            cem · Feb 08   │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Launch prep is converging — blog styling, command UX, and           │
│  defensibility all moved forward. Game engine quest leads.           │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ⇌ HANDOFFS & ASKS                                                   │
│    [1] oz → you: Infra fix after sync (yesterday)                    │
│    [2] ali asks about "blog layout" (3h ago)                         │
│    [3] ✓ oz answered "evaluation criteria"                           │
│                                                                      │
│    pali → ali: Main page animation (Feb 06)                          │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ◦ YOUR SESSIONS                                                     │
│    Today      New commands ready for testing                         │
│    Today      TUI design system + new commands landed                │
│    Today      Slash command rewrites                                 │
│    Yesterday  Defensibility Architecture                             │
│    Yesterday  Launch strategy documents                              │
│                                                                      │
│  ◦ TEAM                                                              │
│    Yesterday  ali: Main Page Styling & Animation                     │
│    Yesterday  oz: Develop branch workflow + auto-greeting UX         │
│    Yesterday  oz: Infra fix after egregore-core sync                 │
│    Feb 06     ali: Blog Styling Updates                              │
│    Feb 06     pali: Main page animation handoff to Ali               │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ⚑ QUESTS (15 active)                                                │
│    grants                          2 artifacts · 4d ago              │
│    egregore-reliability            2 artifacts · 6d ago              │
│    evaluation-benchmarks           2 artifacts · 8d ago              │
│    nlnet-commons-fund              2 artifacts · 10d ago             │
│    game-engine-multiagent          3 artifacts · 14d ago             │
│                                                                      │
│  → OPEN PRs                                                          │
│    #18  Add MCP config (cem)                                         │
│    #17  Save command improvements (oz)                               │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  8 artifacts unlinked to quests — /quest suggest                     │
│  /ask a question · /quest to see more · /reflect for insights        │
│  What's your focus?                                                  │
└──────────────────────────────────────────────────────────────────────┘
```

## Section groups (separated by `├────┤`)

**Group 1 — Insight** (always shown)
1-2 lines synthesized from the data. Written by you as Egregore — what is the org focused on? What themes are converging? What needs attention? Warm, concise, connective. Not a template.

**Group 2 — Handoffs & Asks** (only if items exist from Q4, Q5, Q6, or Q7)
Combines all handoff and question activity into one inbox section:
- Handoffs directed at current user → numbered `[N]`, format: `[N] {from} → you: {topic} ({time_ago})`
- Pending questions for current user → numbered `[N]`, format: `[N] {from} asks about "{topic}" ({time_ago})`
- Answered questions → numbered `[N]`, format: `[N] ✓ {name} answered "{topic}"`
- Other handoffs (not directed at user) → NOT numbered, format: `{from} → {to}: {topic} ({time_ago})`

Show numbered items first, then other handoffs below with a blank line between them.

**Group 3 — Sessions** (always shown)
- `◦ YOUR SESSIONS` — limit 5. Format: `{date}  Topic`
- `◦ TEAM` — limit 5, 7 days. Format: `{date}  name: Topic`
Separated by a blank line between the two sub-sections.

**Group 4 — Quests & PRs** (only if items exist)
- `⚑ QUESTS (N active)` — top 5 by activity score (recency + priority + contributors + artifacts). Format: quest-id left, `N artifacts · Nd ago` right.
- `→ OPEN PRs` — format: `#NN  Title (author)`
Separated by a blank line between the two sub-sections. Omit either if empty.

**Footer** (always shown, separated by `├────┤`)
- If Q8 orphanCount > 0: `N artifacts unlinked to quests — /quest suggest` (shown before command hints)
- Command hints: `/ask a question · /quest to see more · /reflect for insights` — BUT if Q4 (knowledge gaps from reflect's schema) shows sessions without artifacts, replace the generic `/reflect for insights` with a specific CTA: `N sessions without captured insights — /reflect to extract` (where N = number of gap sessions from Q4-equivalent query below)

**Knowledge gap query** (run in parallel with other queries, only used for footer):
```cypher
MATCH (s:Session)-[:BY]->(p:Person {name: '$me'})
WHERE s.date >= date() - duration('P14D')
OPTIONAL MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p)
WHERE a.created >= datetime({year: s.date.year, month: s.date.month, day: s.date.day})
  AND a.created < datetime({year: s.date.year, month: s.date.month, day: s.date.day}) + duration('P1D')
WITH s, count(a) AS artifactCount
WHERE artifactCount = 0
RETURN count(s) AS gapCount
```

If `gapCount > 0`, the footer line becomes: `{gapCount} sessions without captured insights — /reflect to extract`
If `gapCount = 0`, use the default: `/ask a question · /quest to see more · /reflect for insights`
- Always end with: `What's your focus?`

## Date formatting

- Today's date → `Today    ` (pad to 9 chars with spaces)
- Yesterday → `Yesterday` (already 9 chars)
- Older → `Mon DD   ` (pad to 9 chars with spaces)

2-space gap after date column before topic text.

## Time ago (action items in Handoffs & Asks)

<1h `Nm ago` · 1-23h `Nh ago` · 1d `yesterday` · 2-6d `Nd ago` · 7d+ `Mon DD`

## Session orientation (always runs after dashboard)

**Always fire AskUserQuestion after the dashboard.** This is the session bootstrapper — it turns /activity from a read surface into an active orientation primitive.

### Option generation

Generate 2-4 options from the data already collected (Q1–Q8 + Call 9 + PRs). Rank by priority — the first option should be the highest-signal action. Cap at 4 options total (AskUserQuestion limit). "Other" is provided automatically by the tool.

**Priority ranking** (take the first 2-4 that apply):

| Priority | Source | When it fires | Label | Description |
|----------|--------|---------------|-------|-------------|
| 1 | Q6 (handoffs to me) | Someone directed work at you | `Read {author}'s handoff` | `{topic} — {time_ago}` |
| 2 | Q4 (pending questions) | Someone is waiting for answers | `Answer {asker}'s questions` | `About "{topic}" — {time_ago}` |
| 3–4 | Q1 + Call 9 (work streams) | You have recent work | `{work_stream_name}` | `{specific actionable hint}` |
| 5 | PRs (from Call 1) | Open PRs not by you | `Review PR #{number}` | `{title} by {author}` |
| 6 | — (fallback) | Nothing above applies | `Start something new` | `Begin a fresh work stream` |

**Minimum options**: Always show at least 2. If only 1 real option exists, add "Start something new" as the second.

### Work stream detection (Priority 3–4) — the core logic

This is the most important part of the orientation. The goal is to surface 1-2 **specific, actionable work streams** the user could start right now — not vague themes, not random quests.

**Step A: Gather recent session topics.** Merge Q1 sessions (last 3 days only) with Call 9 handoff files on disk. If a file appears on disk but not in Q1, read its `# Handoff: [topic]` line. Deduplicate by session ID or filename slug.

**Step B: Cluster into work streams.** Group sessions by shared themes in their topics. Look for recurring keywords and concepts. For example:
- "Individual tier strategy", "Individual tier agent prompts", "Pricing strategy" → **Pricing & business model**
- "Slash command rewrites", "Terminal UX experiments", "TUI design" → **Slash command improvements**
- "Memory directory consolidation", "Quest sensemaking" → **Infrastructure**

A work stream needs 2+ sessions to qualify. Single-topic sessions get folded into the closest cluster or dropped.

**Step C: Name each work stream.** The label should be specific and actionable — not a session topic, but a recognizable work stream name. Good: "Individual tier pricing" · "Slash command polish". Bad: "Weekend sprint" · "Continue session" · "Terminal UX experiments".

**Step D: Write the description.** The description should hint at what's next, not what's done. Draw from:
- The most recent session's topic in that cluster (what was last touched)
- If a handoff file is available, scan its "Next Steps" or "Open Threads" for specifics
- Keep it under 60 chars

**Step E: Rank work streams.** Prefer:
1. Streams with more sessions (more momentum)
2. Streams with handoffs to others (implies active collaboration / urgency)
3. Streams with matching knowledge artifacts (decisions/findings)

**Step F: Take top 2.** Offer at most 2 work stream options in the AskUserQuestion. This leaves room for handoff/questions (P1-P2) and still fits in the 4-option limit.

### Handling edge cases

**No recent sessions (last 3 days):** Skip work streams entirely. The user starts fresh — offer "Start something new" directly.

**Only 1 session in last 3 days:** Offer it as a single "Continue: {topic}" option. No clustering needed.

**Graph is stale (disk has files not in Neo4j):** Use disk files as primary source. Read the handoff `# Handoff: [topic]` header for topics. Show a sync hint in the footer: `{N} sessions on disk not in graph — /save to sync`

**Work stream overlaps with a handoff already in P1:** Deduplicate — don't offer "Individual tier strategy" as a work stream if the handoff directed at you is about that topic.

### AskUserQuestion format

```
header: "Focus"
question: "What would you like to focus on?"
multiSelect: false
options: [generated from priority ranking]
```

### After selection — session setup

Each option routes to a setup action that loads context for the chosen work stream:

| Selection | System does |
|-----------|------------|
| **Read handoff** | Read `s.filePath` from Q6 data. Display the handoff receiver TUI (see /handoff spec). Show entry points from the handoff file. |
| **Answer questions** | Load the QuestionSet from Neo4j. Present questions via AskUserQuestion (same as `/ask` Step 9). Store answers, notify asker. |
| **Work stream** | Read the most recent handoff file from that work stream's cluster. Display its "Open Threads" and "Next Steps" sections. If knowledge artifacts (decisions/findings) exist for the topic, mention them as context. If entry points reference files, offer to open them. This bootstraps the session with full context for the chosen work stream. |
| **Review PR** | Run `gh pr view #N --json title,body,additions,deletions,files` and display a summary. Offer to check out the branch. |
| **Start something new** | Ask: "What are you working on?" (free text, mirrors session-start greeting). |
| **Other** (user typed) | Treat as the session topic. Proceed with whatever they typed. |

### Example flows

**Sprint day (8 sessions yesterday):**
```
What would you like to focus on?

> 1. Read Oz's handoff
     New Egregore setup flow — yesterday
  2. Individual tier & pricing
     Phase 1.5 execution — 4 agent prompts pending
  3. Slash command polish
     Activity dashboard, /summon PoC, command testing
  4. Type something.
```

**Quiet day (1 session yesterday):**
```
What would you like to focus on?

> 1. Continue: Defensibility architecture
     Open threads — API proxy, Person node schema
  2. Start something new
     Begin a fresh work stream
  3. Type something.
```

**Handoff + questions waiting:**
```
What would you like to focus on?

> 1. Read Oz's handoff
     New setup flow — yesterday
  2. Answer Ali's questions
     About "blog layout" — 3h ago
  3. Individual tier & pricing
     Phase 1.5 execution — pricing doc needs update
  4. Type something.
```

## Quest sensemaking (after orientation)

After the orientation question is answered and the session is set up, check if quest structure has drifted. This runs **once per day** — check the cooldown first.

### Cooldown check

```cypher
OPTIONAL MATCH (sc:SensemakingCheck)
RETURN sc.lastRun AS lastRun, sc.skippedUntil AS skippedUntil
```

**Skip sensemaking entirely if:**
- `lastRun = date()` — already ran today
- `skippedUntil >= date()` — user chose "skip" within the last 7 days

### Trigger thresholds

Use Q8 results (already fetched). Any of these fires → show sensemaking dialogue:

| Condition | Threshold |
|-----------|-----------|
| Orphan ratio | > 40% of artifacts in last 14d have no quest |
| Stale priority | Q9 returns any results (priority >= 2, no artifacts in 10+ days) |
| Topic gap | 3+ orphaned artifacts share a topic not covered by any active quest (compare Q8 topClusters vs Q10 quest topics) |

If no thresholds crossed, silently update cooldown and move on:

```cypher
MERGE (sc:SensemakingCheck) SET sc.lastRun = date()
```

### Sensemaking dialogue

When drift is detected, compose a `⚑ Quest check-in` observation below the dashboard. Use Q8/Q9/Q10 metrics to generate 2-3 natural language questions about what's shifted.

Available data:
- orphanCount / totalRecent / orphanRatio (from Q8)
- topClusters: [{topic, count}] (from Q8) — what orphaned artifacts cluster around
- staleQuests: [{quest, priority, daysSince}] (from Q9)
- questTopicSets: [{quest, topics}] (from Q10) — what existing quests cover

Use AskUserQuestion with options derived from the analysis:
- "Create new quests for [top cluster topics]"
- "Link orphaned artifacts to existing quests"
- "Pause/reprioritize stale quests" (only if Q9 returned results)
- "Skip — structure is fine"

### Acting on responses

| User says | System does |
|-----------|-------------|
| "Create quests" | Run `/quest new` flow with pre-filled title/slug from cluster topics |
| "Link artifacts" | Run topic overlap query (see below), show batch suggestions, link on confirm |
| "Pause/reprioritize" | Run quest status/priority update for each stale quest |
| "Skip" | Set `skippedUntil = date() + 7d` on SensemakingCheck |

**Topic overlap query** (for "link artifacts" — frequency filter excludes generic topics appearing in >30% of all artifacts):

```cypher
MATCH (all:Artifact) WHERE all.topics IS NOT NULL
WITH count(all) AS totalArtifacts
MATCH (all:Artifact) WHERE all.topics IS NOT NULL
UNWIND all.topics AS t
WITH totalArtifacts, t, count(DISTINCT all) AS freq
WHERE toFloat(freq) / toFloat(totalArtifacts) <= 0.3
WITH collect(t) AS discriminatingTopics

MATCH (a:Artifact)
WHERE NOT (a)-[:PART_OF]->(:Quest)
  AND a.topics IS NOT NULL
WITH a, discriminatingTopics,
     [t IN a.topics WHERE t IN discriminatingTopics] AS filteredTopics
MATCH (q:Quest {status: 'active'})
WHERE q.topics IS NOT NULL
WITH a, q, [t IN filteredTopics WHERE t IN q.topics] AS shared
WHERE size(shared) >= 2
RETURN a.id AS artifact, a.title AS artifactTitle,
       q.id AS quest, q.title AS questTitle,
       shared AS sharedTopics, size(shared) AS overlap
ORDER BY overlap DESC
```

Present as: "I'd link these — look right?" User confirms → batch-create PART_OF relationships and update markdown frontmatter.

### After acting (always)

```cypher
MERGE (sc:SensemakingCheck) SET sc.lastRun = date()
```

If user chose "Skip — structure is fine":

```cypher
MERGE (sc:SensemakingCheck) SET sc.lastRun = date(), sc.skippedUntil = date() + duration('P7D')
```

## Argument filtering

- `/activity quests` — show all quests with full artifact counts
- `/activity @name` — filter to that person's sessions (replace $me in Q1/Q2, skip handoffs & asks)

## Fallback

If Neo4j fails, use `memory/` files. Add `(offline)` after ✦ in header. No handoffs & asks in fallback.

## Rules

- No sibling directory access — Neo4j or memory/ only
- `bash bin/graph.sh query "..."` for Neo4j — never MCP
- `gh pr list --base develop --state open --json number,title,author` for PRs
- Org name from `jq -r '.org_name' egregore.json` — truncate at 20 chars
- Run all queries in parallel
- **No sub-boxes** — only outer frame `│` borders and `├────┤` separators
- Pad every content line with trailing spaces so closing `│` aligns
