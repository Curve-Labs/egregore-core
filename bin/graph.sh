#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SCRIPT_DIR/egregore.json"

if [ ! -f "$CONFIG" ]; then
  echo "Error: egregore.json not found. Run onboarding first." >&2
  exit 1
fi

# Env vars override egregore.json
NEO4J_HOST="${NEO4J_HOST:-$(jq -r '.neo4j_host' "$CONFIG")}"
NEO4J_USER="${NEO4J_USER:-$(jq -r '.neo4j_user // "neo4j"' "$CONFIG")}"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-$(jq -r '.neo4j_password' "$CONFIG")}"

# Source .env if it exists (for local overrides)
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

if [ -z "$NEO4J_HOST" ] || [ "$NEO4J_HOST" = "null" ]; then
  echo "Error: neo4j_host not set in egregore.json" >&2
  exit 1
fi

URL="https://${NEO4J_HOST}/db/neo4j/query/v2"
AUTH=$(printf '%s:%s' "$NEO4J_USER" "$NEO4J_PASSWORD" | base64)

run_query() {
  local cypher="$1"
  local params
  if [ -n "${2:-}" ]; then
    params="$2"
  else
    params="{}"
  fi

  local body
  body=$(jq -n --arg stmt "$cypher" --argjson params "$params" \
    '{statement: $stmt, parameters: $params}')

  local response
  response=$(curl -s -X POST "$URL" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    -d "$body" \
    --max-time 30)

  # Check for errors
  local errors
  errors=$(echo "$response" | jq -r '.errors // empty')
  if [ -n "$errors" ] && [ "$errors" != "null" ] && [ "$errors" != "[]" ]; then
    echo "Neo4j error:" >&2
    echo "$response" | jq '.errors' >&2
    exit 1
  fi

  echo "$response" | jq '.data'
}

get_schema() {
  local response
  response=$(curl -s -X POST "$URL" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    -d '{"statement":"CALL db.schema.visualization()"}' \
    --max-time 30)

  local nodes rels
  nodes=$(echo "$response" | jq -r '[.data.values[0][0][] | {label: .labels[0], properties: .properties.constraints}]')
  rels=$(echo "$response" | jq -r '[.data.values[0][1][] | .type] | unique')

  echo "Node labels:"
  echo "$nodes" | jq -r '.[] | "  - \(.label)"'
  echo ""
  echo "Relationship types:"
  echo "$rels" | jq -r '.[] | "  - \(.)"'
}

test_connection() {
  local response
  response=$(curl -s -X POST "$URL" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    -d '{"statement":"RETURN 1 AS ok"}' \
    --max-time 10)

  if echo "$response" | jq -e '.data.values[0][0] == 1' >/dev/null 2>&1; then
    echo "Connected to Neo4j at $NEO4J_HOST"
  else
    echo "Failed to connect to Neo4j at $NEO4J_HOST" >&2
    echo "$response" >&2
    exit 1
  fi
}

case "${1:-help}" in
  query)
    shift
    run_query "$@"
    ;;
  schema)
    get_schema
    ;;
  test)
    test_connection
    ;;
  help|*)
    echo "Usage: graph.sh <command>"
    echo ""
    echo "Commands:"
    echo "  query <cypher> [params_json]  Run a Cypher query"
    echo "  schema                        Show graph schema"
    echo "  test                          Test connection"
    ;;
esac
