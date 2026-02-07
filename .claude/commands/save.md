Save your contributions to Egregore. Pushes working branch, creates PR to develop.

## What to do

1. **Sync to Neo4j first** (CRITICAL):
   - Scan memory/conversations/ for files without Session nodes
   - Scan memory/artifacts/ for files without Artifact nodes
   - Scan memory/quests/ for files without Quest nodes
   - Create missing nodes automatically
   - Report: "Synced 2 sessions, 1 artifact to graph"

2. **For memory repo** (artifacts, quests, handoffs):
   - Pull latest from main
   - Create contribution branch: `contrib/YYYY-MM-DD-[author]-[summary]`
   - Commit all changes
   - Create PR with auto-merge
   - PR merges automatically
   - User sees: "Contribution merged"

3. **For egregore** (commands, scripts, config):
   - Ensure on a `dev/*` working branch. If not, create one from develop:
     ```bash
     git fetch origin develop --quiet
     git checkout -b dev/$AUTHOR/$(date +%Y-%m-%d)-session origin/develop
     ```
   - Commit all changes to working branch
   - Push working branch: `git push -u origin $BRANCH`
   - Create PR to develop: `gh pr create --base develop --title "..." --body "..."`
   - Detect if markdown-only or has code:
     ```bash
     NON_MD=$(git diff develop --name-only | grep -v '\.md$' | head -1)
     ```
     - **Markdown-only** (NON_MD is empty) → `gh pr merge --auto --merge` → auto-merges
     - **Has code/config changes** → leave PR open, notify maintainer

4. **For project repos** (tristero, lace):
   - Warn user: "You have code changes. Use /push and /pr for review."
   - Code changes require human review

## Neo4j Sync Logic (via bin/graph.sh)

Run each check with `bash bin/graph.sh query "..."`. Never use MCP.

```cypher
// For each file in conversations/YYYY-MM/*.md, check if Session exists:
MATCH (s:Session {id: $fileId}) RETURN s.id
// If null, parse frontmatter and create Session node

// For each file in artifacts/*.md:
MATCH (a:Artifact {id: $fileId}) RETURN a.id
// If null, parse frontmatter and create Artifact node

// For each file in quests/*.md (not index.md, not _template.md):
MATCH (q:Quest {id: $slug}) RETURN q.id
// If null, parse frontmatter and create Quest node
```

Parse frontmatter for: author, date, topic/title, project, quests (for artifacts).

This ensures files and graph stay in sync even if earlier commands skipped Neo4j.

## Example

```
> /save

Saving to Egregore...

[sync] Checking Neo4j...
  conversations/2026-02/07-oz-infra-fix.md → missing Session
  ✓ Created Session node for oz
  Synced: 1 session

[memory]
  Changes:
    conversations/2026-02/07-oz-infra-fix.md (new)
    conversations/index.md (modified)

  Creating contribution...
    git checkout -b contrib/2026-02-07-oz-infra-fix
    git commit -m "Add: handoff for infra fix"
    gh pr create --title "Add: handoff for infra fix"
    gh pr merge --auto --merge

  ✓ Contribution merged

[egregore]
  On branch: dev/oz/2026-02-07-session
  Changes:
    .claude/commands/save.md (modified)
    bin/session-start.sh (new)

  Pushing and creating PR...
    git push -u origin dev/oz/2026-02-07-session
    gh pr create --base develop --title "Update save command and add session-start"

  Has code changes — PR #15 created for review.
  ✓ Notified oz

Done. Team sees your contribution on /activity.
```

## Markdown-only PR (auto-merges)

```
[egregore]
  On branch: dev/cem/2026-02-08-session
  Changes:
    .claude/commands/onboarding.md (modified)

  Pushing and creating PR...
    gh pr create --base develop
    gh pr merge --auto --merge

  ✓ Markdown-only — auto-merged to develop
```

## If no changes

```
> /save

No uncommitted changes.
```

## Why this flow?

- Non-technical users never see git complexity
- Markdown changes flow freely (auto-merge to develop)
- Code/config changes get reviewed before merging to develop
- Each contribution is a discrete, revertable unit
- `/activity` shows contributions clearly
- `/release` controls what reaches main

## Next

Run `/activity` to see your contribution, or keep working.
