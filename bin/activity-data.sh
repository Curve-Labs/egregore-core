#!/bin/bash
# Fetches all activity dashboard data in parallel.
# Usage: bash bin/activity-data.sh [username]
# Returns a single JSON object with all query results.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GS="$SCRIPT_DIR/bin/graph.sh"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Detect user ---
# Look up Person.name via github username (matches how session-start.sh creates Person nodes)
ME="${1:-}"
if [ -z "$ME" ]; then
  STATE_FILE="$SCRIPT_DIR/.egregore-state.json"
  GH_USER=""
  if [ -f "$STATE_FILE" ]; then
    GH_USER=$(jq -r '.github_username // empty' "$STATE_FILE" 2>/dev/null)
  fi
  if [ -n "$GH_USER" ]; then
    # Look up the Person node name by github field — Person.name may differ from github username
    PERSON_NAME=$(bash "$GS" query "MATCH (p:Person {github: \$gh}) RETURN p.name AS name" "{\"gh\": \"$GH_USER\"}" 2>/dev/null | jq -r '.values[0][0] // empty' 2>/dev/null)
    if [ -n "$PERSON_NAME" ]; then
      ME="$PERSON_NAME"
    else
      ME="$GH_USER"
    fi
  else
    # Fallback: lowercase first word of git config user.name
    FULL_NAME=$(git -C "$SCRIPT_DIR" config user.name 2>/dev/null || echo "unknown")
    ME=$(echo "$FULL_NAME" | tr '[:upper:]' '[:lower:]' | cut -d' ' -f1)
  fi
fi

ORG=$(jq -r '.org_name // "Egregore"' "$SCRIPT_DIR/egregore.json" 2>/dev/null || echo "Egregore")
DATE=$(date '+%b %d')
EMPTY='{"fields":[],"values":[]}'

# --- Fire all queries in parallel ---

# Q1: My sessions (last 10)
bash "$GS" query "MATCH (s:Session)-[:BY]->(p:Person {name: '$ME'}) OPTIONAL MATCH (s)-[:HANDED_TO]->(target:Person) RETURN s.date AS date, s.topic AS topic, s.id AS id, s.filePath AS filePath, target.name AS handedTo ORDER BY s.date DESC, s.id DESC LIMIT 10" > "$TMPDIR/q1.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/q1.json" &

# Q2: Team sessions (7 days)
bash "$GS" query "MATCH (s:Session)-[:BY]->(p:Person) WHERE p.name <> '$ME' AND s.date >= date() - duration('P7D') RETURN s.date AS date, s.topic AS topic, p.name AS by ORDER BY s.date DESC LIMIT 5" > "$TMPDIR/q2.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/q2.json" &

# Q3: Active quests (scored with personal relevance)
bash "$GS" query "MATCH (q:Quest {status: 'active'}) OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q) OPTIONAL MATCH (a)-[:CONTRIBUTED_BY]->(p:Person) WHERE p.name IS NOT NULL AND p.name <> 'external' OPTIONAL MATCH (q)-[:STARTED_BY]->(starter:Person {name: '$ME'}) OPTIONAL MATCH (myArt:Artifact)-[:PART_OF]->(q) WHERE (myArt)-[:CONTRIBUTED_BY]->(:Person {name: '$ME'}) WITH q, count(DISTINCT a) AS artifacts, count(DISTINCT p) AS contributors, CASE WHEN count(a) > 0 THEN duration.inDays(max(a.created), date()).days ELSE duration.inDays(q.started, date()).days END AS daysSince, coalesce(q.priority, 0) AS priority, CASE WHEN starter IS NOT NULL THEN 1 ELSE 0 END AS iStarted, count(DISTINCT myArt) AS myArtifacts WITH q, artifacts, daysSince, round((toFloat(artifacts) + toFloat(contributors)*1.5 + toFloat(priority)*5.0 + 30.0/(1.0+toFloat(daysSince)*0.5) + CASE WHEN iStarted = 1 THEN 15.0 ELSE 0.0 END + toFloat(myArtifacts)*3.0) * 100)/100 AS score ORDER BY score DESC LIMIT 5 RETURN q.id AS quest, q.title AS title, artifacts, daysSince, score" > "$TMPDIR/q3.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/q3.json" &

# Q4: Pending questions for me
bash "$GS" query "MATCH (qs:QuestionSet {status: 'pending'})-[:ASKED_TO]->(p:Person {name: '$ME'}) MATCH (qs)-[:ASKED_BY]->(asker:Person) RETURN qs.id AS setId, qs.topic AS topic, qs.created AS created, asker.name AS from ORDER BY qs.created DESC LIMIT 10" > "$TMPDIR/q4.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/q4.json" &

# Q5: Answered questions (7 days)
bash "$GS" query "MATCH (qs:QuestionSet {status: 'answered'})-[:ASKED_BY]->(p:Person {name: '$ME'}) MATCH (qs)-[:ASKED_TO]->(target:Person) WHERE qs.created >= datetime() - duration('P7D') RETURN qs.id AS setId, qs.topic AS topic, target.name AS answeredBy ORDER BY qs.created DESC LIMIT 10" > "$TMPDIR/q5.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/q5.json" &

# Q_resolve + Q6: Auto-resolve handoffs THEN fetch (sequential to fix race condition)
(
  # First: resolve read handoffs with subsequent sessions
  bash "$GS" query "MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: '$ME'})
WHERE s.handoffStatus = 'read'
WITH s, p, coalesce(s.handoffReadDate, s.date) AS sinceDate
MATCH (later:Session)-[:BY]->(p)
WHERE later.date > sinceDate
WITH s, count(later) AS laterSessions WHERE laterSessions > 0
SET s.handoffStatus = 'done'
RETURN s.id AS resolved" > "$TMPDIR/qresolve.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/qresolve.json"
  # Then: fetch handoffs with accurate status
  bash "$GS" query "MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: '$ME'})
WHERE s.date >= date() - duration('P7D')
MATCH (s)-[:BY]->(author:Person)
RETURN s.topic AS topic, s.date AS date, author.name AS author,
       s.filePath AS filePath, s.id AS sessionId,
       coalesce(s.handoffStatus, 'pending') AS status,
       s.handoffResponse AS response
ORDER BY
  CASE coalesce(s.handoffStatus, 'pending')
    WHEN 'pending' THEN 0
    WHEN 'read' THEN 1
    ELSE 2
  END,
  s.date DESC
LIMIT 8" > "$TMPDIR/q6.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/q6.json"
) &

# Q7: All handoffs (7 days)
bash "$GS" query "MATCH (s:Session)-[:HANDED_TO]->(target:Person) WHERE s.date >= date() - duration('P7D') MATCH (s)-[:BY]->(author:Person) RETURN s.topic AS topic, s.date AS date, author.name AS from, target.name AS to, s.filePath AS filePath ORDER BY s.date DESC LIMIT 5" > "$TMPDIR/q7.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/q7.json" &

# Q_checkins: Recent check-ins (7 days)
bash "$GS" query "MATCH (c:CheckIn)-[:BY]->(p:Person)
WHERE c.date >= date() - duration('P7D')
RETURN c.id AS id, c.summary AS summary, c.date AS date,
       p.name AS by, c.totalItems AS total
ORDER BY c.date DESC LIMIT 5" > "$TMPDIR/qcheckins.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/qcheckins.json" &

# Q_todos_merged: Active todos + stale blockers + last checkin (3 queries → 1)
bash "$GS" query "OPTIONAL MATCH (t:Todo)-[:BY]->(:Person {name: '$ME'})
WHERE t.status IN ['open', 'blocked', 'deferred']
WITH count(t) AS activeTodoCount,
     count(CASE WHEN t.status = 'blocked' THEN 1 END) AS blockedCount,
     count(CASE WHEN t.status = 'deferred' THEN 1 END) AS deferredCount,
     count(CASE WHEN t.status = 'blocked' AND t.lastTransitionDate <= datetime() - duration('P3D') THEN 1 END) AS staleBlockedCount
OPTIONAL MATCH (c:CheckIn)-[:BY]->(:Person {name: '$ME'})
WITH activeTodoCount, blockedCount, deferredCount, staleBlockedCount, c
ORDER BY c.date DESC LIMIT 1
RETURN activeTodoCount, blockedCount, deferredCount, staleBlockedCount, c.date AS lastCheckinDate" > "$TMPDIR/qtodos_merged.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/qtodos_merged.json" &

# Q_gap: Knowledge gap count (sessions without artifacts)
bash "$GS" query "MATCH (s:Session)-[:BY]->(p:Person {name: '$ME'}) WHERE s.date >= date() - duration('P14D') OPTIONAL MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p) WHERE a.created >= datetime({year: s.date.year, month: s.date.month, day: s.date.day}) AND a.created < datetime({year: s.date.year, month: s.date.month, day: s.date.day}) + duration('P1D') WITH s, count(a) AS artifactCount WHERE artifactCount = 0 RETURN count(s) AS gapCount" > "$TMPDIR/qgap.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/qgap.json" &

# Q_orphans: Orphan artifact count (14 days)
bash "$GS" query "OPTIONAL MATCH (a:Artifact) WHERE a.created >= date() - duration('P14D') AND NOT (a)-[:PART_OF]->(:Quest) RETURN count(a) AS orphanCount" > "$TMPDIR/qorphans.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/qorphans.json" &

# Q_focus_history: Recent Focus selections (what user chose vs what was shown)
bash "$GS" query "MATCH (s:Session)-[:BY]->(p:Person {name: '$ME'})
WHERE s.focusSelected IS NOT NULL
RETURN s.focusShown AS shown, s.focusSelected AS selected, s.focusDismissed AS dismissed, s.date AS date, s.topic AS topic
ORDER BY s.date DESC LIMIT 5" > "$TMPDIR/qfocus.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/qfocus.json" &

# --- Trend queries (4 lightweight metrics for Insight enrichment) ---

# AM_cadence: My session count per week (4 weeks)
bash "$GS" query "
MATCH (s:Session)-[:BY]->(p:Person {name: '$ME'})
WHERE s.date >= date() - duration('P28D')
WITH duration.inDays(s.date, date()).days / 7 AS weeksAgo, count(s) AS sessions
RETURN weeksAgo, sessions ORDER BY weeksAgo" > "$TMPDIR/am_cadence.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/am_cadence.json" &

# AM_resolution: My handoff resolution stats (30d avg)
bash "$GS" query "
MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: '$ME'})
WHERE s.handoffStatus = 'done' AND s.date >= date() - duration('P30D')
  AND s.handoffReadDate IS NOT NULL
WITH duration.inDays(s.date, s.handoffReadDate).days AS days
RETURN avg(days) AS avgDays, count(*) AS resolved" > "$TMPDIR/am_resolution.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/am_resolution.json" &

# AM_throughput: My todo created vs done (28d)
bash "$GS" query "
MATCH (t:Todo)-[:BY]->(p:Person {name: '$ME'})
WHERE t.created >= datetime() - duration('P28D') OR
      (t.status = 'done' AND t.lastTransitionDate >= datetime() - duration('P28D'))
RETURN count(CASE WHEN t.created >= datetime() - duration('P28D') THEN 1 END) AS created,
       count(CASE WHEN t.status = 'done' AND t.lastTransitionDate >= datetime() - duration('P28D') THEN 1 END) AS completed" > "$TMPDIR/am_throughput.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/am_throughput.json" &

# AM_capture: My knowledge capture ratio (28d)
bash "$GS" query "
MATCH (s:Session)-[:BY]->(p:Person {name: '$ME'})
WHERE s.date >= date() - duration('P28D')
OPTIONAL MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p)
WHERE a.created >= datetime({year: s.date.year, month: s.date.month, day: s.date.day})
  AND a.created < datetime({year: s.date.year, month: s.date.month, day: s.date.day}) + duration('P1D')
WITH s, count(a) AS artifacts
RETURN count(s) AS total,
       count(CASE WHEN artifacts > 0 THEN 1 END) AS captured" > "$TMPDIR/am_capture.json" 2>/dev/null || echo "$EMPTY" > "$TMPDIR/am_capture.json" &

# Git sync + PRs + disk cross-reference
(
  # Sync
  git -C "$SCRIPT_DIR" fetch origin --quiet 2>/dev/null || true
  CURRENT=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || echo "unknown")
  if [ "$CURRENT" != "develop" ]; then
    git -C "$SCRIPT_DIR" fetch origin develop:develop --quiet 2>/dev/null || true
  fi
  if [[ "$CURRENT" == dev/* ]]; then
    git -C "$SCRIPT_DIR" rebase develop --quiet >/dev/null 2>&1 || git -C "$SCRIPT_DIR" rebase --abort >/dev/null 2>&1 || true
  fi

  # Memory sync
  if [ -d "$SCRIPT_DIR/memory/.git" ] || [ -L "$SCRIPT_DIR/memory" ]; then
    git -C "$SCRIPT_DIR/memory" fetch origin main --quiet 2>/dev/null || true
    LOCAL=$(git -C "$SCRIPT_DIR/memory" rev-parse HEAD 2>/dev/null || echo "")
    REMOTE=$(git -C "$SCRIPT_DIR/memory" rev-parse origin/main 2>/dev/null || echo "")
    if [ -n "$LOCAL" ] && [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
      git -C "$SCRIPT_DIR/memory" pull origin main --quiet 2>/dev/null || true
    fi
  fi

  # PRs
  PRS=$(cd "$SCRIPT_DIR" && gh pr list --base develop --state open --json number,title,author 2>/dev/null || echo "[]")
  echo "$PRS" > "$TMPDIR/prs.json"

  # Disk cross-reference
  MONTH=$(date +%Y-%m)
  TODAY=$(date +%d)
  YESTERDAY=$(date -v-1d +%d 2>/dev/null || date -d 'yesterday' +%d 2>/dev/null || echo "00")
  HANDOFFS=$(ls -1 "$SCRIPT_DIR/memory/handoffs/$MONTH/" 2>/dev/null | grep "^${TODAY}-\|^${YESTERDAY}-" 2>/dev/null | head -10 || echo "")
  echo "$HANDOFFS" > "$TMPDIR/disk_handoffs.txt"

  DECISIONS=$(ls -1t "$SCRIPT_DIR/memory/knowledge/decisions/" 2>/dev/null | head -5 || echo "")
  echo "$DECISIONS" > "$TMPDIR/disk_decisions.txt"
) &

# --- Wait for all parallel jobs ---
wait

# --- Validate JSON files ---
for f in q1 q2 q3 q4 q5 q6 q7 qgap qorphans qresolve qcheckins qtodos_merged qfocus am_cadence am_resolution am_throughput am_capture; do
  jq . "$TMPDIR/$f.json" >/dev/null 2>&1 || echo "$EMPTY" > "$TMPDIR/$f.json"
done

# --- Read git/disk results ---
PRS=$(cat "$TMPDIR/prs.json" 2>/dev/null || echo "[]")
echo "$PRS" | jq . >/dev/null 2>&1 || PRS="[]"
DISK_HANDOFFS=$(cat "$TMPDIR/disk_handoffs.txt" 2>/dev/null || echo "")
DISK_DECISIONS=$(cat "$TMPDIR/disk_decisions.txt" 2>/dev/null || echo "")

# --- Assemble single JSON output ---
jq -n \
  --arg me "$ME" \
  --arg org "$ORG" \
  --arg date "$DATE" \
  --slurpfile my_sessions "$TMPDIR/q1.json" \
  --slurpfile team_sessions "$TMPDIR/q2.json" \
  --slurpfile quests "$TMPDIR/q3.json" \
  --slurpfile pending_questions "$TMPDIR/q4.json" \
  --slurpfile answered_questions "$TMPDIR/q5.json" \
  --slurpfile handoffs_to_me "$TMPDIR/q6.json" \
  --slurpfile all_handoffs "$TMPDIR/q7.json" \
  --slurpfile knowledge_gap "$TMPDIR/qgap.json" \
  --slurpfile orphans "$TMPDIR/qorphans.json" \
  --slurpfile checkins "$TMPDIR/qcheckins.json" \
  --slurpfile todos_merged "$TMPDIR/qtodos_merged.json" \
  --slurpfile focus_history "$TMPDIR/qfocus.json" \
  --slurpfile am_cadence "$TMPDIR/am_cadence.json" \
  --slurpfile am_resolution "$TMPDIR/am_resolution.json" \
  --slurpfile am_throughput "$TMPDIR/am_throughput.json" \
  --slurpfile am_capture "$TMPDIR/am_capture.json" \
  --argjson prs "$PRS" \
  --arg disk_handoffs "$DISK_HANDOFFS" \
  --arg disk_decisions "$DISK_DECISIONS" \
  '{
    me: $me,
    org: $org,
    date: $date,
    my_sessions: $my_sessions[0],
    team_sessions: $team_sessions[0],
    quests: $quests[0],
    pending_questions: $pending_questions[0],
    answered_questions: $answered_questions[0],
    handoffs_to_me: $handoffs_to_me[0],
    all_handoffs: $all_handoffs[0],
    knowledge_gap: $knowledge_gap[0],
    orphans: $orphans[0],
    checkins: $checkins[0],
    todos_merged: $todos_merged[0],
    focus_history: $focus_history[0],
    prs: $prs,
    disk: {handoffs: $disk_handoffs, decisions: $disk_decisions},
    trends: {
      cadence: $am_cadence[0],
      resolution: $am_resolution[0],
      throughput: $am_throughput[0],
      capture: $am_capture[0]
    }
  }'
