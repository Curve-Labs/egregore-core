Save your contributions to Egregore. Pushes working branch, creates PR to develop.

## Execution rules

**CRITICAL: Suppress raw output.** Never show raw JSON to the user. All `bin/graph.sh` calls MUST capture output in a variable and only show formatted status lines (e.g. "Synced 2 sessions, 1 artifact to graph").

## What to do

1. **Sync to Neo4j first** (CRITICAL):
   - Scan memory/handoffs/ for files without Session nodes
   - Scan memory/artifacts/ for files without Artifact nodes
   - Scan memory/knowledge/decisions/ for files without Artifact nodes
   - Scan memory/knowledge/findings/ for files without Artifact nodes
   - Scan memory/knowledge/patterns/ for files without Artifact nodes
   - Scan memory/quests/ for files without Quest nodes
   - Create missing nodes automatically
   - Report: "Synced 2 sessions, 1 artifact to graph"

2. **For memory repo** (artifacts, quests, handoffs):
   - Push directly to main (no PRs — memory is markdown-only, always safe to merge)
   - Pull-rebase-push with retry to handle concurrent pushes from other users
   ```bash
   cd memory
   git add -A
   git commit -m "$COMMIT_MESSAGE"
   # Retry loop: handles concurrent pushes from other users
   for i in 1 2 3; do
     git pull --rebase origin main --quiet && git push origin main --quiet && break
     if [ $i -eq 3 ]; then
       echo "Push failed after 3 attempts. Try /save again."
       exit 1
     fi
     sleep 1
   done
   cd -
   ```
   - User sees: "Memory pushed"

3. **For egregore** (commands, scripts, config):
   - Ensure on a working branch (`dev/*`, `feature/*`, or `bugfix/*`). If not (e.g. still on develop), create one:
     - Derive a topic slug from the changes being saved (look at modified files, commit messages, or conversation context)
     - Create branch: `dev/$AUTHOR/{topic-slug}` from develop
     - If no clear topic, fall back to date: `dev/$AUTHOR/$(date +%Y-%m-%d)`
     ```bash
     git fetch origin develop --quiet
     git checkout -b dev/$AUTHOR/$TOPIC_SLUG origin/develop
     ```
   - Commit all changes to working branch
   - **Rebase onto latest develop before pushing** (prevents stale overwrites):
     ```bash
     git fetch origin develop --quiet
     git rebase origin/develop --quiet
     ```
     If rebase conflicts: abort, try merge instead:
     ```bash
     git rebase --abort
     git merge origin/develop --quiet -m "Sync with develop"
     ```
     If merge also conflicts: stop and tell the user:
     > Your branch conflicts with develop. Run `git status` to see conflicts, resolve them, then `/save` again.
   - Push working branch:
     ```bash
     git push -u origin $BRANCH
     ```
   - **If push fails**: stop here. Do NOT proceed. Tell the user:
     > Push failed. Your commits are safe on your working branch. Check your network and try `/save` again.
   - Create PR to develop:
     ```bash
     gh pr create --base develop --title "..." --body "..."
     ```
   - **If PR creation fails**: stop here. The branch was pushed, so tell the user:
     > PR creation failed, but your branch `{BRANCH}` was pushed.
     > Your commits are safe. Try again with `/save` or create the PR manually.
   - **If PR succeeds**, detect if markdown-only or has code:
     ```bash
     NON_MD=$(git diff develop --name-only | grep -v '\.md$' | head -1)
     ```
     - **Markdown-only** (NON_MD is empty) → `gh pr merge --auto --merge` → auto-merges
     - **Has code/config changes** → run preflight check, then leave PR open for review:
       ```bash
       bash bin/preflight.sh
       ```
       - If preflight **passes** (exit 0) → show `✓ Preflight passed` and create PR normally
       - If preflight **fails** (exit 1) → show violations, still create PR but add `⚠ preflight-failed` label:
         ```bash
         gh pr edit $PR_NUMBER --add-label "preflight-failed"
         ```
         Tell the developer: `⚠ Preflight found issues — fix before merging. See violations above.`
       - Preflight never blocks the save — work is always preserved. It warns.

4. **For project repos** (tristero, lace):
   - Warn user: "You have code changes. Use /push and /pr for review."
   - Code changes require human review

## Neo4j Sync Logic (via bin/graph.sh)

Run each check with `bash bin/graph.sh query "..."`. Never use MCP.

```cypher
// For each file in handoffs/YYYY-MM/*.md, check if Session exists:
MATCH (s:Session {id: $fileId}) RETURN s.id
// If null, parse frontmatter and create Session node

// For each file in artifacts/*.md:
MATCH (a:Artifact {id: $fileId}) RETURN a.id
// If null, parse frontmatter and create Artifact node (include topics)
// If exists, sync topics from frontmatter:
//   MATCH (a:Artifact {id: $fileId}) SET a.topics = $topics RETURN a.id

// For each file in knowledge/{decisions,findings,patterns}/*.md:
MATCH (a:Artifact {id: $fileId}) RETURN a.id
// If null, parse frontmatter and create Artifact node:
//   id = filename without extension
//   type = directory name singularized (decisions → decision, findings → finding, patterns → pattern)
//   filePath = knowledge/{category}s/{filename}
//   title, author, date from frontmatter

// For each file in quests/*.md (not index.md, not _template.md):
MATCH (q:Quest {id: $slug}) RETURN q.id
// If null, parse frontmatter and create Quest node
// If exists, sync priority from frontmatter: SET q.priority = coalesce($priority, 0)
```

Parse frontmatter for: author, date, topic/title, project, quests (for artifacts), topics (for artifacts), priority (for quests, default 0).

### Auto-resolve read handoffs

After all sync queries, resolve any `read` handoffs where the user has completed a subsequent session (same criteria as Q_resolve in activity-data.sh):

```cypher
MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: $me})
WHERE s.handoffStatus = 'read'
WITH s, p, coalesce(s.handoffReadDate, s.date) AS sinceDate
MATCH (later:Session)-[:BY]->(p)
WHERE later.date > sinceDate
WITH s, count(later) AS laterSessions WHERE laterSessions > 0
SET s.handoffStatus = 'done'
RETURN s.id AS id, s.topic AS topic
```

If any resolved, report: `[sync] ✓ Resolved N handoffs (read → done)`

### Topic sync on artifacts

When syncing artifact files, parse `topics` from frontmatter (YAML list) and SET on the node:

```cypher
MATCH (a:Artifact {id: $artifactId})
SET a.topics = $topics
```

### Quest topic derivation

After all artifact syncing is complete, derive quest topic signatures from their linked artifacts:

```cypher
MATCH (q:Quest {status: 'active'})
OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q)
WHERE a.topics IS NOT NULL
UNWIND a.topics AS topic
WITH q, collect(DISTINCT topic) AS derivedTopics
SET q.topics = derivedTopics
```

Run this as the final step of Neo4j sync, after all artifact and quest nodes are synced.

This ensures files and graph stay in sync even if earlier commands skipped Neo4j.

## Example

```
> /save

Saving to Egregore...

[sync] Checking Neo4j...
  handoffs/2026-02/07-oz-infra-fix.md → missing Session
  ✓ Created Session node for oz
  Synced: 1 session

[memory]
  Changes:
    handoffs/2026-02/07-oz-infra-fix.md (new)
    handoffs/index.md (modified)

  Pushing to main...
    git commit -m "Add: handoff for infra fix"
    git pull --rebase origin main
    git push origin main

  ✓ Memory pushed

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

## Markdown-only egregore PR (auto-merges)

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
- Memory pushes directly to main (instant availability, no PR delay)
- Pull-rebase-push retry handles concurrent users safely
- Egregore markdown changes auto-merge to develop via PR
- Code/config changes get reviewed before merging to develop
- `/activity` shows contributions clearly
- `/release` controls what reaches main

## Next

Run `/activity` to see your contribution, or keep working.
