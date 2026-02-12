#!/bin/bash
# Named graph operations — clean interface over raw Cypher.
# Keeps implementation details out of the TUI.
#
# Usage: bash bin/graph-op.sh <operation> [args...]
#
# Operations:
#   mark-read <session-id>      Mark a handoff as read
#   mark-done <session-id>      Mark a handoff as done/resolved
#   answer-question <set-id>    Mark a question set as answered
#   resolve-handoffs <user>     Auto-resolve read handoffs with later sessions
#   record-focus <session-id> <shown-json> <selected> [dismissed-json]
#                               Track Focus option selection for adaptive options

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GS="$SCRIPT_DIR/bin/graph.sh"

OP="${1:-}"
shift 2>/dev/null

case "$OP" in

  mark-read)
    SID="$1"
    [ -z "$SID" ] && echo '{"error":"missing session-id"}' && exit 1
    bash "$GS" query "
      MATCH (s:Session {id: \$sid})
      SET s.handoffStatus = 'read', s.handoffReadDate = date()
      RETURN s.id AS id, s.topic AS topic
    " "{\"sid\":\"$SID\"}" 2>/dev/null
    ;;

  mark-done)
    SID="$1"
    [ -z "$SID" ] && echo '{"error":"missing session-id"}' && exit 1
    bash "$GS" query "
      MATCH (s:Session {id: \$sid})
      SET s.handoffStatus = 'done'
      RETURN s.id AS id, s.topic AS topic
    " "{\"sid\":\"$SID\"}" 2>/dev/null
    ;;

  answer-question)
    QID="$1"
    [ -z "$QID" ] && echo '{"error":"missing question-set-id"}' && exit 1
    bash "$GS" query "
      MATCH (qs:QuestionSet {id: \$qid})
      SET qs.status = 'answered'
      RETURN qs.id AS id, qs.topic AS topic
    " "{\"qid\":\"$QID\"}" 2>/dev/null
    ;;

  resolve-handoffs)
    USER="$1"
    [ -z "$USER" ] && echo '{"error":"missing username"}' && exit 1
    bash "$GS" query "
      MATCH (s:Session)-[:HANDED_TO]->(p:Person {name: \$user})
      WHERE s.handoffStatus = 'read'
      WITH s, p, coalesce(s.handoffReadDate, s.date) AS sinceDate
      MATCH (later:Session)-[:BY]->(p)
      WHERE later.date > sinceDate
      WITH s, count(later) AS laterSessions WHERE laterSessions > 0
      SET s.handoffStatus = 'done'
      RETURN s.id AS resolved
    " "{\"user\":\"$USER\"}" 2>/dev/null
    ;;

  record-focus)
    SID="$1"
    SHOWN="$2"
    SELECTED="$3"
    DISMISSED="${4:-[]}"
    [ -z "$SID" ] && echo '{"error":"missing session-id"}' && exit 1
    [ -z "$SHOWN" ] && echo '{"error":"missing shown options"}' && exit 1
    [ -z "$SELECTED" ] && echo '{"error":"missing selected option"}' && exit 1
    bash "$GS" query "
      MATCH (s:Session {id: \$sid})
      SET s.focusShown = \$shown,
          s.focusSelected = \$selected,
          s.focusDismissed = \$dismissed
      RETURN s.id AS id
    " "{\"sid\":\"$SID\",\"shown\":$SHOWN,\"selected\":\"$SELECTED\",\"dismissed\":$DISMISSED}" 2>/dev/null
    ;;

  *)
    echo '{"error":"unknown operation: '"$OP"'","operations":["mark-read","mark-done","answer-question","resolve-handoffs","record-focus"]}'
    exit 1
    ;;

esac
