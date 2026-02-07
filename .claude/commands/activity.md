Fast, personal view of what's happening — your projects, your sessions, team activity.

Topic: $ARGUMENTS

**Auto-syncs.** Pulls latest if behind before showing activity.

## Execution rules

**Neo4j-first.** All data comes from Neo4j via `bin/graph.sh`. No MCP. No filesystem access to sibling repos.
- Smart sync: fetch, pull only if behind (runs in parallel with queries)
- 1 Bash call: git config user.name
- 6 Neo4j queries via `bash bin/graph.sh query "..."` (run in parallel)
- File-based fallback only if Neo4j unavailable

## Step 0: Smart sync (parallel with Step 2)

```bash
# Fetch and sync develop
git fetch origin --quiet
CURRENT=$(git branch --show-current)
git checkout develop --quiet && git pull origin develop --quiet && git checkout "$CURRENT" --quiet 2>/dev/null
# If on dev/* branch, rebase onto develop
if [[ "$CURRENT" == dev/* ]]; then
  git rebase develop --quiet 2>/dev/null || (git rebase --abort 2>/dev/null && git merge develop -m "Sync with develop" --quiet 2>/dev/null)
fi

# Memory
git -C memory fetch origin main --quiet 2>/dev/null
LOCAL=$(git -C memory rev-parse HEAD 2>/dev/null)
REMOTE=$(git -C memory rev-parse origin/main 2>/dev/null)
if [ "$LOCAL" != "$REMOTE" ]; then
  git -C memory pull origin main --quiet
fi

# Open PRs to develop (show in activity)
gh pr list --base develop --state open --json number,title,author 2>/dev/null
```

Run this in parallel with Neo4j queries. Don't wait for it unless Neo4j fails.

## Step 1: Get current user

```bash
git config user.name
```

Map to Person node: "Oguzhan Yayla" → oz, "Cem Dagdelen" → cem, "Ali" → ali

## Step 2: Neo4j Queries (run all in parallel via bin/graph.sh)

Execute each query with `bash bin/graph.sh query "..."`. Run all 6 in parallel Bash calls.

```cypher
// Query 1: My projects
MATCH (p:Person {name: $me})-[w:WORKS_ON]->(proj:Project)
RETURN proj.name AS project, proj.domain AS domain, w.role AS role

// Query 2: My recent sessions
MATCH (s:Session)-[:BY]->(p:Person {name: $me})
RETURN s.date AS date, s.topic AS topic, s.summary AS summary
ORDER BY s.date DESC LIMIT 5

// Query 3: Team activity (others, last 7 days)
MATCH (s:Session)-[:BY]->(p:Person)
WHERE p.name <> $me AND s.date >= date() - duration('P7D')
RETURN s.date AS date, s.topic AS topic, p.name AS by
ORDER BY s.date DESC LIMIT 5

// Query 4: Active quests
MATCH (q:Quest {status: 'active'})-[:RELATES_TO]->(proj:Project)
OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q)
RETURN q.id AS quest, q.title AS title, collect(DISTINCT proj.name) AS projects, count(a) AS artifacts

// Query 5: Pending questions for me
MATCH (qs:QuestionSet {status: 'pending'})-[:ASKED_TO]->(p:Person {name: $me})
MATCH (qs)-[:ASKED_BY]->(asker:Person)
RETURN qs.id AS setId, qs.topic AS topic, qs.created AS created, asker.name AS from
ORDER BY qs.created DESC

// Query 6: My answered questions (last 7 days)
MATCH (qs:QuestionSet {status: 'answered'})-[:ASKED_BY]->(p:Person {name: $me})
MATCH (qs)-[:ASKED_TO]->(target:Person)
WHERE qs.created >= datetime() - duration('P7D')
RETURN qs.id AS setId, qs.topic AS topic, target.name AS answeredBy
ORDER BY qs.created DESC
```

## Step 3: File-based fallback

If Neo4j unavailable, use memory/ symlink (doesn't trigger sibling permissions):

```bash
# Active quests
grep -l "status: active" memory/quests/*.md 2>/dev/null | xargs -I{} basename {} | grep -v template

# Recent artifacts
ls -t memory/artifacts/*.md 2>/dev/null | head -10 | xargs -I{} basename {}
```

## Output format

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  EGREGORE ACTIVITY                                            oz · Feb 01  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PENDING FOR YOU                                                            │
│  ┌───────────────────────────────────────────────────────────────────┐      │
│  │ 2 questions from cem about "evaluation criteria" (12 hours ago)   │      │
│  │ 1 question from ali about "MCP transport" (2 days ago)            │      │
│  └───────────────────────────────────────────────────────────────────┘      │
│  Run /ask to answer pending questions.                                      │
│                                                                             │
│  ANSWERS RECEIVED                                                           │
│  ┌───────────────────────────────────────────────────────────────────┐      │
│  │ oz answered your questions about "benchmark approach"             │      │
│  └───────────────────────────────────────────────────────────────────┘      │
│                                                                             │
│  PROJECTS                                                                   │
│  ┌────────────────┬──────────┬────────────────────────────────┐             │
│  │ Project        │ Domain   │ Access                         │             │
│  ├────────────────┼──────────┼────────────────────────────────┤             │
│  │ curve-labs-core│ both     │ (here)                         │             │
│  │ tristero       │ polis    │ cd ../tristero && claude       │             │
│  │ lace           │ psyche   │ cd ../lace && claude           │             │
│  └────────────────┴──────────┴────────────────────────────────┘             │
│                                                                             │
│  YOUR RECENT SESSIONS                                                       │
│  ┌────────────┬─────────────────────────┬───────────────────────────────┐   │
│  │ Date       │ Topic                   │ Summary                       │   │
│  ├────────────┼─────────────────────────┼───────────────────────────────┤   │
│  │ 2026-01-31 │ NLNet grant submitted   │ €30k for open-source Egregore │   │
│  └────────────┴─────────────────────────┴───────────────────────────────┘   │
│                                                                             │
│  TEAM ACTIVITY (last 7 days)                                                │
│  ┌────────────┬─────────────────────────┬──────────┐                        │
│  │ Date       │ Topic                   │ By       │                        │
│  ├────────────┼─────────────────────────┼──────────┤                        │
│  │ 2026-01-30 │ Blog versions reviewed  │ cem      │                        │
│  │ 2026-01-27 │ Bot deployed to Railway │ ali      │                        │
│  └────────────┴─────────────────────────┴──────────┘                        │
│                                                                             │
│  ACTIVE QUESTS                                                              │
│  ┌──────────────────┬─────────────────────┬───────────┬───────────┐         │
│  │ Quest            │ Title               │ Projects  │ Artifacts │         │
│  ├──────────────────┼─────────────────────┼───────────┼───────────┤         │
│  │ nlnet-commons    │ NLNet grant app     │ egregore  │ 4         │         │
│  │ blog-launch      │ V2 blog content     │ egregore  │ 2         │         │
│  └──────────────────┴─────────────────────┴───────────┴───────────┘         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**If sections are empty**, show:
```
│  (none yet — use /quest new to create one)                                  │
```

**For PENDING FOR YOU and ANSWERS RECEIVED**: Only show these sections if there are items. If both are empty, omit both sections entirely (no placeholder text).

## Rules

- **No sibling directory access** — all data from Neo4j or memory/ symlink
- **Use `bash bin/graph.sh query "..."` for all Neo4j queries** — never use MCP
- Projects from Neo4j → show `cd ../[project] && claude`
- Minimize tool calls — run Neo4j queries in parallel
- File-based fallback only if `bin/graph.sh` fails
