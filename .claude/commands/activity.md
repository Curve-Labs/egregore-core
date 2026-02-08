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

Q1 — My sessions:
```
MATCH (s:Session)-[:BY]->(p:Person {name: '$me'}) RETURN s.date AS date, s.topic AS topic ORDER BY s.date DESC LIMIT 5
```

Q2 — Team (7 days):
```
MATCH (s:Session)-[:BY]->(p:Person) WHERE p.name <> '$me' AND s.date >= date() - duration('P7D') RETURN s.date AS date, s.topic AS topic, p.name AS by ORDER BY s.date DESC LIMIT 5
```

Q3 — Active quests (scored by recency + priority + contributors + artifacts):
```
MATCH (q:Quest {status: 'active'}) OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q) OPTIONAL MATCH (a)-[:CONTRIBUTED_BY]->(p:Person) WHERE p.name IS NOT NULL AND p.name <> 'external' WITH q, count(DISTINCT a) AS artifacts, count(DISTINCT p) AS contributors, CASE WHEN count(a) > 0 THEN duration.inDays(max(a.created), date()).days ELSE duration.inDays(q.started, date()).days END AS daysSince, coalesce(q.priority, 0) AS priority RETURN q.id AS quest, artifacts, daysSince, round((toFloat(artifacts) + toFloat(contributors)*1.5 + toFloat(priority)*5.0 + 30.0/(1.0+toFloat(daysSince)*0.5)) * 100)/100 AS score ORDER BY score DESC
```

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
│  Type a number to act, or keep working.                              │
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
- Command hints: `/ask a question · /quest to see more · /reflect for insights`
- If numbered items exist: `Type a number to act, or keep working.`

## Date formatting

- Today's date → `Today    ` (pad to 9 chars with spaces)
- Yesterday → `Yesterday` (already 9 chars)
- Older → `Mon DD   ` (pad to 9 chars with spaces)

2-space gap after date column before topic text.

## Time ago (action items in Handoffs & Asks)

<1h `Nm ago` · 1-23h `Nh ago` · 1d `yesterday` · 2-6d `Nd ago` · 7d+ `Mon DD`

## Interactive follow-up

If numbered items exist, use AskUserQuestion after the box. One option per numbered item plus "Skip — just looking".

- Handoff → read s.filePath and display
- Pending questions → load QuestionSet, start /ask answer flow
- Answered questions → load QuestionSet and display answers

Zero numbered items → no AskUserQuestion.

## Quest sensemaking (after dashboard)

After displaying the dashboard and handling any numbered action items, check if quest structure has drifted. This runs **once per day** — check the cooldown first.

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
