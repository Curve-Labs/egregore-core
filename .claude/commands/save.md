Save your contributions to Egregore. Creates a branch from your work, opens a PR to develop, and resets you to clean.

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
   - You should be on `develop`. If not, warn and stop.
   - Check for uncommitted changes — commit them first (generate a clear commit message)
   - Count commits ahead of origin/develop:
     ```bash
     git fetch origin develop --quiet
     AHEAD=$(git rev-list origin/develop..HEAD --count)
     ```
   - If 0 → "Nothing to save" and stop
   - Generate a short summary from the commit messages:
     ```bash
     SUMMARY=$(git log origin/develop..HEAD --format=%s | head -1 | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | cut -c1-40)
     ```
   - Create branch at current HEAD:
     ```bash
     SAVE_BRANCH="save/$AUTHOR/$(date +%Y-%m-%d)-$SUMMARY"
     git branch "$SAVE_BRANCH"
     ```
   - Push the branch:
     ```bash
     git push -u origin "$SAVE_BRANCH"
     ```
   - Create PR to develop:
     ```bash
     gh pr create --base develop --head "$SAVE_BRANCH" --title "..." --body "..."
     ```
   - Detect if markdown-only or has code:
     ```bash
     NON_MD=$(git diff origin/develop --name-only | grep -v '\.md$' | head -1)
     ```
     - **Markdown-only** (NON_MD is empty) → `gh pr merge --auto --merge` → auto-merges
     - **Has code/config changes** → leave PR open, notify maintainer
   - Reset develop to clean:
     ```bash
     git reset --hard origin/develop
     ```
   - User is back on clean develop, ready for more work

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
  3 commits ahead of develop
  Changes:
    .claude/commands/save.md (modified)
    bin/session-start.sh (modified)

  Creating save branch...
    git branch save/oz/2026-02-08-simplify-git-workflow
    git push -u origin save/oz/2026-02-08-simplify-git-workflow
    gh pr create --base develop

  Has code changes — PR #15 created for review.
  ✓ Reset develop to clean

Done. Team sees your contribution on /activity.
```

## Markdown-only PR (auto-merges)

```
[egregore]
  1 commit ahead of develop
  Changes:
    .claude/commands/onboarding.md (modified)

  Creating save branch...
    git branch save/cem/2026-02-08-update-onboarding
    git push -u origin save/cem/2026-02-08-update-onboarding
    gh pr merge --auto --merge

  ✓ Markdown-only — auto-merged to develop
  ✓ Reset develop to clean
```

## If no changes

```
> /save

No changes to save.
```

## Why this flow?

- Users work on develop — no branch management
- `/save` creates a branch, PR, and resets develop to clean
- Markdown changes auto-merge (flow freely)
- Code/config changes get reviewed before merging
- Each save is a discrete, revertable unit
- `/activity` shows contributions clearly
- `/release` controls what reaches main

## Next

Run `/activity` to see your contribution, or keep working.
