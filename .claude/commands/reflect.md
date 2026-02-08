Capture a decision, finding, or pattern for the knowledge base and knowledge graph.

Topic: $ARGUMENTS

**Auto-saves.** No need to run `/save` after.

## Quick mode

If `$ARGUMENTS` matches the pattern `[category]: [content]` (e.g. `/reflect decision: use stdio for MCP`), skip the interactive flow:

1. Parse category from prefix (decision/finding/pattern)
2. Parse content from everything after the colon
3. Jump directly to Step 3 (auto-suggest relations) with the parsed values
4. No AskUserQuestion needed

## Execution rules

**Neo4j-first.** All queries via `bash bin/graph.sh query "..."`. No MCP. No direct curl to Neo4j.

- 1 Bash call: `git config user.name`
- 3 Neo4j queries for context gathering (run in parallel)
- 1 AskUserQuestion for category (skipped in quick mode)
- 1 AskUserQuestion for content capture
- 1 Neo4j query for Artifact creation
- Auto-save via `/save` flow

## Step 0: Get current user

```bash
git config user.name
```

Map to Person node: "Oguzhan Yayla" -> oz, "Cem Dagdelen" -> cem, "Ali" -> ali

## Step 1: Context gathering (run all 3 queries in parallel)

Execute each with `bash bin/graph.sh query "..." '{"param": "value"}'`.

```cypher
// Query 1: My recent sessions (7 days)
MATCH (s:Session)-[:BY]->(p:Person {name: $me})
WHERE s.date >= date() - duration('P7D')
RETURN s.topic AS topic, s.date AS date
ORDER BY s.date DESC LIMIT 5

// Query 2: Active quests
MATCH (q:Quest {status: 'active'})
RETURN q.id AS quest, q.title AS title

// Query 3: Recent decisions (14 days)
MATCH (a:Artifact {type: 'decision'})
WHERE a.created >= datetime() - duration('P14D')
RETURN a.title AS title, a.filePath AS path
ORDER BY a.created DESC LIMIT 3
```

Show a brief context summary to help the user frame their reflection. Only show sections that have results:

```
Your recent context:
  Sessions: mcp-auth-flow (Feb 07), graph-schema (Feb 05)
  Quests: benchmark-eval, research-agent
  Recent decisions: Use stdio transport for MCP
```

If all queries return empty, skip the context summary entirely. If Neo4j is unavailable, skip context gathering and proceed to Step 2.

## Step 2: Category selection

Use AskUserQuestion:

```
question: "What kind of reflection?"
options: ["Decision", "Finding", "Pattern"]
```

- **Decision** — a choice made with rationale
- **Finding** — a discovery, learning, what worked or didn't
- **Pattern** — a recurring structure, approach, or anti-pattern

Map the answer to lowercase for file path and Neo4j: decision, finding, pattern.

**Skipped in quick mode** — category parsed from `$ARGUMENTS`.

## Step 3: Content capture

Show context hint from Step 1 (if available), then ask for the reflection content.

Use AskUserQuestion:

```
question: "What's the [category]? (Include what led to it and why it matters)"
```

The user's response becomes the reflection content. From it, extract:

- **Title** — a short descriptive title (used for filename and Neo4j)
- **Context** — what led to this (auto-populate from session context if user doesn't provide)
- **Content** — the decision/finding/pattern itself
- **Rationale** — why it matters

**In quick mode**: the content after the colon is the title and content. Ask a single follow-up for rationale if it's not obvious from the content.

## Step 4: Auto-suggest relations

Match keywords from the reflection against quests and projects from Step 1's Neo4j results.

If matches found, show:

```
Connections found:
  -> Quest: benchmark-eval
  -> Project: egregore
Link these? (y/edit/skip)
```

- **y** (default) — link all suggested
- **edit** — let user modify the list
- **skip** — no links

If no matches found, skip this step silently.

Collect quest IDs and project names for Step 5.

## Step 5: Create file + Neo4j Artifact node

### File creation

Generate slug from title: lowercase, hyphens, no special chars, max 50 chars.

File path: `memory/knowledge/{category}s/{YYYY-MM-DD}-{slug}.md`

Note: directories are `decisions/`, `findings/`, `patterns/` (plural).

Write the file using Bash (memory is outside project, avoids permission issues):

```bash
cat > "memory/knowledge/{category}s/{YYYY-MM-DD}-{slug}.md" << 'REFLECTEOF'
# {Title}

**Date**: {YYYY-MM-DD}
**Author**: {author}
**Category**: {category}

## Context

{Context — what led to this}

## Content

{The decision/finding/pattern itself}

## Rationale

{Why this matters}

## Related

- Quest: {quest-id}
- Project: {project-name}
REFLECTEOF
```

Omit the Related section if no links. Omit individual Related lines if only one type is linked.

### Neo4j Artifact creation

Run via `bash bin/graph.sh query "..." '{"param": "value"}'`:

```cypher
MATCH (p:Person {name: $author})
CREATE (a:Artifact {
  id: $artifactId,
  title: $title,
  type: $category,
  filePath: $filePath,
  created: datetime()
})
CREATE (a)-[:CONTRIBUTED_BY]->(p)
WITH a
UNWIND $questIds AS qId
MATCH (q:Quest {id: qId})
CREATE (a)-[:PART_OF]->(q)
RETURN a.id
```

Where:
- `$artifactId` = `{YYYY-MM-DD}-{slug}` (matches filename without extension)
- `$author` = short name (oz, cem, ali)
- `$category` = decision | finding | pattern
- `$filePath` = `knowledge/{category}s/{YYYY-MM-DD}-{slug}.md`
- `$questIds` = array of linked quest IDs (empty array if none)

If no quests to link, use a simpler query without the UNWIND:

```cypher
MATCH (p:Person {name: $author})
CREATE (a:Artifact {
  id: $artifactId,
  title: $title,
  type: $category,
  filePath: $filePath,
  created: datetime()
})
CREATE (a)-[:CONTRIBUTED_BY]->(p)
RETURN a.id
```

If a project was linked, add a second query:

```cypher
MATCH (a:Artifact {id: $artifactId}), (proj:Project {name: $projectName})
CREATE (a)-[:RELATES_TO]->(proj)
```

## Step 6: Auto-save

Run the full `/save` flow:

1. Commit changes in memory repo and push (contribution branch + PR + auto-merge)
2. Commit any egregore changes and push working branch + PR to develop

This is the same flow as `/save`. Follow its logic exactly.

## Step 7: Confirmation TUI

Display the confirmation box. ~72 char width. Sigil: `◎ REFLECTION`.

```
┌────────────────────────────────────────────────────────────────────────┐
│  ◎ REFLECTION                                          author · date  │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Type: Decision                                                        │
│  Title: Use stdio transport for MCP                                    │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Linked to:                                                       │  │
│  │   ◦ Quest: research-agent                                        │  │
│  │   ◦ Project: egregore                                            │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ✓ Saved to knowledge/decisions/2026-02-08-...                         │
│  ✓ Indexed in knowledge graph                                          │
│  ✓ Auto-saved                                                          │
│                                                                        │
│  Visible in /activity.                                                 │
└────────────────────────────────────────────────────────────────────────┘
```

### TUI rules

- Header row: sigil + command name left, author + date right
- `├───┤` separator between header and content
- Sub-box for linked items (only if there are links)
- `◦` for linked quests and projects
- `✓` for confirmation lines
- Omit the "Linked to" sub-box entirely if no relations
- Truncate title at 45 chars with `...` if needed
- File path: show last 2 segments only (e.g. `decisions/2026-02-08-...`)

## Edge cases

| Scenario | Handling |
|----------|----------|
| Neo4j unavailable | Skip context gathering and relation linking. Still create file. Show warning: "Graph offline — file saved, will sync on next /save" |
| No quests/projects | Skip relation step silently |
| Quick mode, ambiguous category | Ask for clarification with AskUserQuestion |
| User says "skip" at any prompt | Save what you have so far |
| Empty content | Don't create anything, tell user "Nothing to reflect on yet" |
| File already exists at path | Append timestamp to slug to avoid collision |
| Memory symlink missing | Error: "Run /setup first — memory not linked" |

## Full interactive example

```
> /reflect

Your recent context:
  Sessions: mcp-auth-flow (Feb 07), graph-schema (Feb 05)
  Quests: benchmark-eval, research-agent
  Recent decisions: Use stdio transport for MCP

What kind of reflection? (Decision / Finding / Pattern)
> Decision

What's the decision? (Include what led to it and why it matters)
> We should use graph-based artifact linking instead of file-path references.
> Neo4j gives us traversal and the ontology can evolve. File paths are brittle
> and don't capture relationships.

Connections found:
  -> Quest: research-agent
  -> Project: egregore
Link these? (y/edit/skip)
> y

Creating reflection...

  [1/3] Writing knowledge/decisions/2026-02-08-graph-based-artifact-linking.md
  [2/3] Creating Artifact node in knowledge graph
  [3/3] Auto-saving...

┌────────────────────────────────────────────────────────────────────────┐
│  ◎ REFLECTION                                          cem · Feb 08   │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Type: Decision                                                        │
│  Title: Graph-based artifact linking                                   │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Linked to:                                                       │  │
│  │   ◦ Quest: research-agent                                        │  │
│  │   ◦ Project: egregore                                            │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ✓ Saved to knowledge/decisions/2026-02-08-...                         │
│  ✓ Indexed in knowledge graph                                          │
│  ✓ Auto-saved                                                          │
│                                                                        │
│  Visible in /activity.                                                 │
└────────────────────────────────────────────────────────────────────────┘
```

## Quick mode example

```
> /reflect finding: Neo4j HTTP API is faster than Bolt for small queries

Your recent context:
  Sessions: graph-perf-testing (Feb 08)
  Quests: benchmark-eval

Connections found:
  -> Quest: benchmark-eval
Link these? (y/edit/skip)
> y

Creating reflection...

┌────────────────────────────────────────────────────────────────────────┐
│  ◎ REFLECTION                                          cem · Feb 08   │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Type: Finding                                                         │
│  Title: Neo4j HTTP API faster than Bolt for small...                   │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Linked to:                                                       │  │
│  │   ◦ Quest: benchmark-eval                                        │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ✓ Saved to knowledge/findings/2026-02-08-...                          │
│  ✓ Indexed in knowledge graph                                          │
│  ✓ Auto-saved                                                          │
│                                                                        │
│  Visible in /activity.                                                 │
└────────────────────────────────────────────────────────────────────────┘
```
