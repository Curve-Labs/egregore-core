End a session with a summary for the next person (or future you).

Topic: $ARGUMENTS

**Auto-saves.** No need to run `/save` after.

## What to do

1. Get author name from `git config user.name`
2. Summarize what was accomplished
3. Note open questions and next steps
4. Create handoff file in memory/conversations/YYYY-MM/
5. Update the conversation index
6. **MUST** create Session node in Neo4j via `bash bin/graph.sh query "..."` (never MCP)
7. **Auto-save**: Run the full `/save` flow (push working branch, PR to develop)

**CRITICAL: Step 6 is NOT optional.** Without the Neo4j Session node, the handoff won't appear in `/activity`. Always run the Cypher query below.

## Neo4j Session creation (via bin/graph.sh)

Run with `bash bin/graph.sh query "..." '{"param": "value"}'`

```cypher
MATCH (p:Person {name: $author})
CREATE (s:Session {
  id: $sessionId,
  date: date($date),
  topic: $topic,
  summary: $summary,
  filePath: $filePath
})
CREATE (s)-[:BY]->(p)
WITH s
OPTIONAL MATCH (proj:Project {name: $project})
FOREACH (_ IN CASE WHEN proj IS NOT NULL THEN [1] ELSE [] END |
  CREATE (s)-[:ABOUT]->(proj)
)
RETURN s.id
```

Where:
- `$sessionId` = `YYYY-MM-DD-author-topic` (matches filename)
- `$author` = short name (oz, cem, ali)
- `$project` = project name if specified

## File naming

`memory/conversations/YYYY-MM/DD-[author]-[topic].md`

Example: `memory/conversations/2026-01/21-oz-mcp-auth.md`

## Handoff file template

```markdown
# Handoff: [Topic]

**Date**: YYYY-MM-DD
**Author**: [from git config user.name]
**Project**: [LACE/Tristero/Research]

## Session Summary

[2-3 sentences on what was accomplished]

## Key Decisions

- **[Decision]**: [Rationale]

## Current State

[What's working, what's in progress, what's blocked]

## Open Threads

- [ ] [Unfinished item with context]

## Next Steps

1. [Clear action with entry point]

## Entry Points

For the next session, start by:
- Reading: [specific file]
- Running: [specific command]
```

## Notifications

If the user indicates the handoff is for someone specific, notify them:

**Detection**: Understand from natural language who the recipient is:
- "handoff to cem" → notify cem
- "for oz to pick up" → notify oz
- "ali should look at this" → notify ali

Team members: oz, ali, cem

**Notification API**:
```bash
bash bin/notify.sh send "cem" "message"
```

**Message format**:
```
Hey Cem, oz handed off: {topic}

"{summary}"

Check it out when you can.
```

**If no recipient**: Don't notify anyone. Not every handoff is directed at a specific person.

## Example

```
> /handoff mcp auth

Creating handoff...

I'll summarize this session. Checking what we did...

Session summary:
- Added MCP authentication (feature branch)
- Created PR #42
- Open question: how to handle key rotation?

Writing to memory/conversations/2026-01/20-oz-mcp-auth.md...
  ✓ Created

Updating memory/conversations/index.md...
  ✓ Added entry

Recording session in knowledge graph...
  ✓ Session node created, linked to oz → infrastructure

Saving...
  ✓ Committed and merged

Done. Team can see this on /activity.
```
