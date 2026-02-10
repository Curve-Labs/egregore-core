#!/bin/bash
# Fetches all activity dashboard data in one batch API call + parallel git/disk ops.
# Usage: bash bin/activity-data.sh [username]
# Returns a single JSON object with all query results.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Detect user ---
ME="${1:-}"
if [ -z "$ME" ]; then
  FULL_NAME=$(git -C "$SCRIPT_DIR" config user.name 2>/dev/null || echo "unknown")
  case "$FULL_NAME" in
    "Oguzhan Yayla"|"oz") ME="oz" ;;
    "Cem Dagdelen"|"Cem F"|"cem") ME="cem" ;;
    "Ali"|"ali") ME="ali" ;;
    "Pali"|"pali") ME="pali" ;;
    *) ME=$(echo "$FULL_NAME" | tr '[:upper:]' '[:lower:]' | cut -d' ' -f1) ;;
  esac
fi

ORG=$(jq -r '.org_name // "Egregore"' "$SCRIPT_DIR/egregore.json" 2>/dev/null || echo "Egregore")
DATE=$(date '+%b %d')

# --- Build batch: 14 queries in one API call ---
# Index map:
#  0=my_sessions  1=team_sessions  2=quests  3=pending_questions
#  4=answered_questions  5=resolve_handoffs  6=handoffs_to_me  7=all_handoffs
#  8=checkins  9=stale_blockers  10=todos  11=last_checkin
#  12=knowledge_gap  13=orphans
BATCH=$(cat <<EOF
[
  {"statement": "MATCH (s:Session)-[:BY]->(p:Person {name: '$ME'}) OPTIONAL MATCH (s)-[:HANDED_TO]->(target:Person) RETURN s.date AS date, s.topic AS topic, s.id AS id, s.filePath AS filePath, target.name AS handedTo ORDER BY s.date DESC, s.id DESC LIMIT 10"},
  {"statement": "MATCH (s:Session)-[:BY]->(p:Person) WHERE p.name <> '$ME' AND s.date >= date() - duration('P7D') RETURN s.date AS date, s.topic AS topic, p.name AS by ORDER BY s.date DESC LIMIT 5"},
  {"statement": "MATCH (q:Quest {status: 'active'}) OPTIONAL MATCH (a:Artifact)-[:PART_OF]->(q) OPTIONAL MATCH (a)-[:CONTRIBUTED_BY]->(p:Person) WHERE p.name IS NOT NULL AND p.name <> 'external' OPTIONAL MATCH (q)-[:STARTED_BY]->(starter:Person {name: '$ME'}) OPTIONAL MATCH (myArt:Artifact)-[:PART_OF]->(q) WHERE (myArt)-[:CONTRIBUTED_BY]->(:Person {name: '$ME'}) WITH q, count(DISTINCT a) AS artifacts, count(DISTINCT p) AS contributors, CASE WHEN count(a) > 0 THEN duration.inDays(max(a.created), date()).days ELSE duration.inDays(q.started, date()).days END AS daysSince, coalesce(q.priority, 0) AS priority, CASE WHEN starter IS NOT NULL THEN 1 ELSE 0 END AS iStarted, count(DISTINCT myArt) AS myArtifacts WITH q, artifacts, daysSince, round((toFloat(artifacts) + toFloat(contributors)*1.5 + toFloat(priority)*5.0 + 30.0/(1.0+toFloat(daysSince)*0.5) + CASE WHEN iStarted = 1 THEN 15.0 ELSE 0.0 END + toFloat(myArtifacts)*3.0) * 100)/100 AS score ORDER BY score DESC LIMIT 5 RETURN q.id AS quest, q.title AS title, artifacts, daysSince, score"},
  {"statement": "MATCH (qs:QuestionSet {status: 'pending'})-[:ASKED_TO]->(p:Person {name: '$ME'}) MATCH (qs)-[:ASKED_BY]->(asker:Person) RETURN qs.id AS setId, qs.topic AS topic, qs.created AS created, asker.name AS from ORDER BY qs.created DESC"},
  {"statement": "MATCH (qs:QuestionSet {status: 'answered'})-[:ASKED_BY]->(p:Person {name: '$ME'}) MATCH (qs)-[:ASKED_TO]->(target:Person) WHERE qs.created >= datetime() - duration('P7D') RETURN qs.id AS setId, qs.topic AS topic, target.name AS answeredBy ORDER BY qs.created DESC"},
  {"statement": "MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: '$ME'}) WHERE s.handoffStatus = 'read' WITH s, p, coalesce(s.handoffReadDate, s.date) AS sinceDate MATCH (later:Session)-[:BY]->(p) WHERE later.date > sinceDate WITH s, count(later) AS laterSessions WHERE laterSessions > 0 SET s.handoffStatus = 'done' RETURN s.id AS resolved"},
  {"statement": "MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: '$ME'}) WHERE s.date >= date() - duration('P7D') MATCH (s)-[:BY]->(author:Person) RETURN s.topic AS topic, s.date AS date, author.name AS author, s.filePath AS filePath, s.id AS sessionId, coalesce(s.handoffStatus, 'pending') AS status, s.handoffResponse AS response ORDER BY CASE coalesce(s.handoffStatus, 'pending') WHEN 'pending' THEN 0 WHEN 'read' THEN 1 ELSE 2 END, s.date DESC LIMIT 8"},
  {"statement": "MATCH (s:Session)-[:HANDED_TO]->(target:Person) WHERE s.date >= date() - duration('P7D') MATCH (s)-[:BY]->(author:Person) RETURN s.topic AS topic, s.date AS date, author.name AS from, target.name AS to, s.filePath AS filePath ORDER BY s.date DESC LIMIT 5"},
  {"statement": "MATCH (c:CheckIn)-[:BY]->(p:Person) WHERE c.date >= date() - duration('P7D') RETURN c.id AS id, c.summary AS summary, c.date AS date, p.name AS by, c.totalItems AS total ORDER BY c.date DESC LIMIT 5"},
  {"statement": "MATCH (t:Todo {status: 'blocked'})-[:BY]->(p:Person {name: '$ME'}) WHERE t.lastTransitionDate <= datetime() - duration('P3D') RETURN count(t) AS staleBlockedCount"},
  {"statement": "MATCH (t:Todo)-[:BY]->(p:Person {name: '$ME'}) WHERE t.status IN ['open', 'blocked', 'deferred'] RETURN count(t) AS activeTodoCount, count(CASE WHEN t.status = 'blocked' THEN 1 END) AS blockedCount, count(CASE WHEN t.status = 'deferred' THEN 1 END) AS deferredCount"},
  {"statement": "MATCH (c:CheckIn)-[:BY]->(p:Person {name: '$ME'}) RETURN c.date AS lastDate ORDER BY c.date DESC LIMIT 1"},
  {"statement": "MATCH (s:Session)-[:BY]->(p:Person {name: '$ME'}) WHERE s.date >= date() - duration('P14D') OPTIONAL MATCH (a:Artifact)-[:CONTRIBUTED_BY]->(p) WHERE a.created >= datetime({year: s.date.year, month: s.date.month, day: s.date.day}) AND a.created < datetime({year: s.date.year, month: s.date.month, day: s.date.day}) + duration('P1D') WITH s, count(a) AS artifactCount WHERE artifactCount = 0 RETURN count(s) AS gapCount"},
  {"statement": "OPTIONAL MATCH (a:Artifact) WHERE a.created >= date() - duration('P14D') AND NOT (a)-[:PART_OF]->(:Quest) RETURN count(a) AS orphanCount"}
]
EOF
)

# --- Fire batch API call + git/disk ops in parallel ---
bash "$SCRIPT_DIR/bin/graph-batch.sh" "$BATCH" > "$TMPDIR/batch.json" 2>/dev/null &
BATCH_PID=$!

(
  git -C "$SCRIPT_DIR" fetch origin --quiet 2>/dev/null || true
  CURRENT=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || echo "unknown")
  if [ "$CURRENT" != "develop" ]; then
    git -C "$SCRIPT_DIR" fetch origin develop:develop --quiet 2>/dev/null || true
  fi
  if [[ "$CURRENT" == dev/* ]]; then
    git -C "$SCRIPT_DIR" rebase develop --quiet 2>/dev/null || git -C "$SCRIPT_DIR" rebase --abort 2>/dev/null || true
  fi

  if [ -d "$SCRIPT_DIR/memory/.git" ] || [ -L "$SCRIPT_DIR/memory" ]; then
    git -C "$SCRIPT_DIR/memory" fetch origin main --quiet 2>/dev/null || true
    LOCAL=$(git -C "$SCRIPT_DIR/memory" rev-parse HEAD 2>/dev/null || echo "")
    REMOTE=$(git -C "$SCRIPT_DIR/memory" rev-parse origin/main 2>/dev/null || echo "")
    if [ -n "$LOCAL" ] && [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
      git -C "$SCRIPT_DIR/memory" pull origin main --quiet 2>/dev/null || true
    fi
  fi

  PRS=$(cd "$SCRIPT_DIR" && gh pr list --base develop --state open --json number,title,author 2>/dev/null || echo "[]")
  echo "$PRS" > "$TMPDIR/prs.json"

  MONTH=$(date +%Y-%m)
  TODAY=$(date +%d)
  YESTERDAY=$(date -v-1d +%d 2>/dev/null || date -d 'yesterday' +%d 2>/dev/null || echo "00")
  HANDOFFS=$(ls -1 "$SCRIPT_DIR/memory/handoffs/$MONTH/" 2>/dev/null | grep "^${TODAY}-\|^${YESTERDAY}-" 2>/dev/null | head -10 || echo "")
  echo "$HANDOFFS" > "$TMPDIR/disk_handoffs.txt"

  DECISIONS=$(ls -1t "$SCRIPT_DIR/memory/knowledge/decisions/" 2>/dev/null | head -5 || echo "")
  echo "$DECISIONS" > "$TMPDIR/disk_decisions.txt"
) &
GIT_PID=$!

wait $BATCH_PID $GIT_PID

# --- Validate batch response ---
if ! jq -e '.results' "$TMPDIR/batch.json" >/dev/null 2>&1; then
  echo '{"results":[]}' > "$TMPDIR/batch.json"
fi

# --- Read git/disk results ---
PRS=$(cat "$TMPDIR/prs.json" 2>/dev/null || echo "[]")
echo "$PRS" | jq . >/dev/null 2>&1 || PRS="[]"
DISK_HANDOFFS=$(cat "$TMPDIR/disk_handoffs.txt" 2>/dev/null || echo "")
DISK_DECISIONS=$(cat "$TMPDIR/disk_decisions.txt" 2>/dev/null || echo "")

# --- Assemble single JSON output (one jq call, extract by batch index) ---
E='{"fields":[],"values":[]}'
jq -n \
  --arg me "$ME" \
  --arg org "$ORG" \
  --arg date "$DATE" \
  --slurpfile batch "$TMPDIR/batch.json" \
  --argjson prs "$PRS" \
  --arg disk_handoffs "$DISK_HANDOFFS" \
  --arg disk_decisions "$DISK_DECISIONS" \
  --argjson empty "$E" \
  '{
    me: $me,
    org: $org,
    date: $date,
    my_sessions: ($batch[0].results[0] // $empty),
    team_sessions: ($batch[0].results[1] // $empty),
    quests: ($batch[0].results[2] // $empty),
    pending_questions: ($batch[0].results[3] // $empty),
    answered_questions: ($batch[0].results[4] // $empty),
    handoffs_to_me: ($batch[0].results[6] // $empty),
    all_handoffs: ($batch[0].results[7] // $empty),
    knowledge_gap: ($batch[0].results[12] // $empty),
    orphans: ($batch[0].results[13] // $empty),
    checkins: ($batch[0].results[8] // $empty),
    stale_blockers: ($batch[0].results[9] // $empty),
    todos: ($batch[0].results[10] // $empty),
    last_checkin: ($batch[0].results[11] // $empty),
    prs: $prs,
    disk: {handoffs: $disk_handoffs, decisions: $disk_decisions}
  }'
