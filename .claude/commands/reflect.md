Capture a decision, finding, or pattern for the knowledge base.

## What to do

1. Prompt for category (decision/finding/pattern)
2. Prompt for content
3. Save to memory/knowledge/
4. Remind to run /save

## Categories

- **decisions/** — Choices made with rationale
- **findings/** — Discoveries, learnings, what worked or didn't
- **patterns/** — Recurring structures, approaches, anti-patterns

## Example

```
> /reflect

What did you notice? (decision / finding / pattern)
> decision

What was decided?
> Use stdio transport for MCP instead of HTTP

Why?
> Simpler auth model, Claude Code expects it, fewer moving parts

Saving to memory/knowledge/decisions/2026-01-20-mcp-stdio-transport.md...
  ✓ Created

Run /save to share with the team.
```

## File format

```markdown
# [Title]

**Date**: YYYY-MM-DD
**Author**: [from git config]
**Category**: decision | finding | pattern

## Context

[What led to this]

## Content

[The decision/finding/pattern itself]

## Rationale

[Why this matters]
```

## Next

Run `/save` to share.
