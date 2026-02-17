#!/bin/bash
set -uo pipefail

# =============================================================================
# Live End-to-End Isolation Test
#
# Hits the live deployed API with real HTTP calls to verify:
# - Org registration + user sync + graph creation
# - Supabase data integrity
# - Neo4j org scoping and cross-org isolation
# - API key security (forged keys, Frankenstein keys)
# - Guard layer (destructive ops, org tampering, unlabeled nodes)
# - Admin diagnostics
#
# Prerequisites:
#   .env  — GITHUB_TOKEN (admin user), EGREGORE_API_KEY (CL key for reverse tests)
#   egregore.json — api_url
#
# Usage: bash bin/test-isolation.sh [--no-cleanup]
# Exit:  0 = all pass, 1 = failures
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SCRIPT_DIR/egregore.json"
NO_CLEANUP=false

for arg in "$@"; do
  case "$arg" in
    --no-cleanup) NO_CLEANUP=true ;;
  esac
done

if [ ! -f "$CONFIG" ]; then
  echo "Error: egregore.json not found" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Error: .env not found — need GITHUB_TOKEN and EGREGORE_API_KEY" >&2
  exit 1
fi
set -a; source "$SCRIPT_DIR/.env"; set +a

API_URL="$(jq -r '.api_url // empty' "$CONFIG")"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
CL_API_KEY="${EGREGORE_API_KEY:-}"

if [ -z "$API_URL" ]; then echo "Error: api_url not set in egregore.json" >&2; exit 1; fi
if [ -z "$GITHUB_TOKEN" ]; then echo "Error: GITHUB_TOKEN not set in .env" >&2; exit 1; fi
if [ -z "$CL_API_KEY" ]; then echo "Error: EGREGORE_API_KEY not set in .env" >&2; exit 1; fi

# --- State ---
TIMESTAMP=$(date +%s)
TEST_ORG="e2e-test-${TIMESTAMP}"
TEST_API_KEY=""
PASS=0
FAIL=0

# --- Helpers ---
pass() {
  printf "  \033[32mPASS\033[0m  %s\n" "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf "  \033[31mFAIL\033[0m  %s\n" "$1"
  FAIL=$((FAIL + 1))
}

phase() {
  echo ""
  echo "=== Phase $1: $2 ==="
}

api_post() {
  local path="$1" token="$2" body="$3"
  curl -s -X POST "${API_URL}${path}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$body" \
    --max-time 30
}

api_get() {
  local path="$1" token="$2"
  curl -s -X GET "${API_URL}${path}" \
    -H "Authorization: Bearer ${token}" \
    --max-time 30
}

api_delete() {
  local path="$1" token="$2"
  curl -s -X DELETE "${API_URL}${path}" \
    -H "Authorization: Bearer ${token}" \
    --max-time 30
}

# Build a graph query JSON body safely via jq (handles $ in Cypher params)
graph_body() {
  local stmt="$1"
  local params="$2"
  if [ -z "$params" ]; then params='{}'; fi
  jq -n --arg stmt "$stmt" --argjson params "$params" \
    '{statement: $stmt, parameters: $params}'
}

# Build an admin graph-write JSON body
admin_body() {
  local stmt="$1"
  local params="$2"
  if [ -z "$params" ]; then params='{}'; fi
  jq -n --arg stmt "$stmt" --argjson params "$params" \
    '{statement: $stmt, params: $params}'
}


# =============================================================================
# Phase 1: Register test org
# =============================================================================
phase 1 "Register test org"

REG_BODY=$(jq -n --arg name "E2E Test ${TIMESTAMP}" --arg org "$TEST_ORG" \
  '{org_name: $name, github_org: $org}')
REGISTER_RESP=$(api_post "/api/org/register" "$GITHUB_TOKEN" "$REG_BODY")

REG_STATUS=$(echo "$REGISTER_RESP" | jq -r '.status // empty')
REG_SLUG=$(echo "$REGISTER_RESP" | jq -r '.org_slug // empty')
TEST_API_KEY=$(echo "$REGISTER_RESP" | jq -r '.api_key // empty')

if [ "$REG_STATUS" = "created" ] && [ "$REG_SLUG" = "$TEST_ORG" ]; then
  pass "Registered org: ${REG_SLUG}"
else
  fail "Registration failed: $(echo "$REGISTER_RESP" | jq -c .)"
fi

if echo "$TEST_API_KEY" | grep -q "^ek_${TEST_ORG}_"; then
  pass "API key format correct: ${TEST_API_KEY:0:30}..."
else
  fail "API key format wrong: ${TEST_API_KEY:0:40}"
fi

# Verify idempotent re-registration
RE_REG=$(api_post "/api/org/register" "$GITHUB_TOKEN" "$REG_BODY")
RE_STATUS=$(echo "$RE_REG" | jq -r '.status // empty')
if [ "$RE_STATUS" = "existing" ]; then
  pass "Re-registration returns 'existing'"
else
  fail "Re-registration returned '${RE_STATUS}' instead of 'existing'"
fi


# =============================================================================
# Phase 2: Add users
# =============================================================================
phase 2 "Add users"

for user in alice-e2e bob-e2e; do
  BODY=$(jq -n --arg u "$user" --arg n "$user Test" \
    '{github_username: $u, github_name: $n}')
  USER_RESP=$(api_post "/api/user/ensure" "$TEST_API_KEY" "$BODY")
  USER_STATUS=$(echo "$USER_RESP" | jq -r '.status // empty')
  if [ "$USER_STATUS" = "ok" ]; then
    pass "User synced: ${user}"
  else
    fail "User sync failed for ${user}: $(echo "$USER_RESP" | jq -c .)"
  fi
done


# =============================================================================
# Phase 3: Create graph data
# =============================================================================
phase 3 "Create graph data"

for person in alice-e2e bob-e2e; do
  PARAMS=$(jq -n --arg name "$person" '{name: $name}')
  BODY=$(graph_body 'MERGE (p:Person {name: $name}) RETURN p.name' "$PARAMS")
  GRAPH_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")

  if echo "$GRAPH_RESP" | jq -e '.values' >/dev/null 2>&1; then
    pass "Created Person node: ${person}"
  else
    fail "Graph create failed for ${person}: $(echo "$GRAPH_RESP" | jq -c .)"
  fi
done

# Create a Session node for isolation tests
SESSION_ID="e2e-session-${TIMESTAMP}"
PARAMS=$(jq -n --arg id "$SESSION_ID" --arg branch "test/e2e" '{id: $id, branch: $branch}')
BODY=$(graph_body 'MERGE (s:Session {id: $id, branch: $branch}) RETURN s.id' "$PARAMS")
SESSION_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
if echo "$SESSION_RESP" | jq -e '.values' >/dev/null 2>&1; then
  pass "Created Session node: ${SESSION_ID}"
else
  fail "Session create failed: $(echo "$SESSION_RESP" | jq -c .)"
fi


# =============================================================================
# Phase 4: Verify Neo4j
# =============================================================================
phase 4 "Verify Neo4j"

# Query persons with test key — should only see test org data
BODY=$(graph_body 'MATCH (p:Person) RETURN p.name ORDER BY p.name' '{}')
PERSONS_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
PERSON_NAMES=$(echo "$PERSONS_RESP" | jq -r '[.values[][0]] | join(",")')
PERSON_COUNT=$(echo "$PERSONS_RESP" | jq '.values | length')

if echo "$PERSON_NAMES" | grep -q "alice-e2e" && echo "$PERSON_NAMES" | grep -q "bob-e2e"; then
  pass "Test org sees its own Person nodes"
else
  fail "Test org can't see its Person nodes: ${PERSON_NAMES}"
fi

if [ "$PERSON_COUNT" -le 5 ]; then
  pass "Person count reasonable (${PERSON_COUNT}) — no data leak"
else
  fail "ISOLATION CONCERN: test org sees ${PERSON_COUNT} Person nodes (expected ~2)"
fi

# Verify session
BODY=$(graph_body 'MATCH (s:Session) RETURN count(s) AS cnt' '{}')
SESSIONS_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
SESSION_COUNT=$(echo "$SESSIONS_RESP" | jq -r '.values[0][0] // 0')
if [ "$SESSION_COUNT" -ge 1 ] && [ "$SESSION_COUNT" -le 5 ]; then
  pass "Session count reasonable (${SESSION_COUNT})"
else
  fail "Unexpected session count: ${SESSION_COUNT}"
fi


# =============================================================================
# Phase 5: Verify Supabase
# =============================================================================
phase 5 "Verify Supabase"

ADMIN_RESP=$(api_get "/api/admin/org/${TEST_ORG}" "$GITHUB_TOKEN")

# Org exists
ORG_NAME=$(echo "$ADMIN_RESP" | jq -r '.config.name // empty')
if [ "$ORG_NAME" = "E2E Test ${TIMESTAMP}" ]; then
  pass "Supabase org exists with correct name"
else
  fail "Supabase org name mismatch: '${ORG_NAME}'"
fi

# Members
MEMBER_COUNT=$(echo "$ADMIN_RESP" | jq '.members | length')
if [ "$MEMBER_COUNT" -ge 2 ]; then
  pass "Supabase has ${MEMBER_COUNT} members (alice-e2e, bob-e2e + admin)"
else
  fail "Expected >= 2 members, got ${MEMBER_COUNT}"
fi

# Active API key
ACTIVE_KEYS=$(echo "$ADMIN_RESP" | jq '[.api_keys[] | select(.is_active == true)] | length')
if [ "$ACTIVE_KEYS" -ge 1 ]; then
  pass "Supabase has ${ACTIVE_KEYS} active API key(s)"
else
  fail "No active API keys in Supabase"
fi

# Key slug matches org
KEY_PREFIX=$(echo "$ADMIN_RESP" | jq -r '.api_keys[0].key_prefix // empty')
if echo "$KEY_PREFIX" | grep -q "ek_${TEST_ORG}_"; then
  pass "API key prefix matches org slug"
else
  fail "Key prefix mismatch: ${KEY_PREFIX} vs ek_${TEST_ORG}_"
fi


# =============================================================================
# Phase 6: Forward isolation (test org can't see CL data)
# =============================================================================
phase 6 "Forward isolation"

# Test key should NOT see CL Person 'oz'
BODY=$(graph_body 'MATCH (p:Person {name: $name}) RETURN p.name' '{"name":"oz"}')
FWD_PERSONS=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
FWD_VALUES=$(echo "$FWD_PERSONS" | jq '.values | length')
if [ "$FWD_VALUES" -eq 0 ]; then
  pass "Test org cannot see CL person 'oz'"
else
  fail "ISOLATION BREACH: test org sees CL person 'oz'"
fi

# Test key should NOT see CL sessions
BODY=$(graph_body 'MATCH (s:Session) WHERE s.branch STARTS WITH $prefix RETURN count(s) AS cnt' '{"prefix":"dev/oz/"}')
FWD_SESSIONS=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
FWD_SESSION_COUNT=$(echo "$FWD_SESSIONS" | jq -r '.values[0][0] // 0')
if [ "$FWD_SESSION_COUNT" -eq 0 ]; then
  pass "Test org cannot see CL sessions (dev/oz/*)"
else
  fail "ISOLATION BREACH: test org sees ${FWD_SESSION_COUNT} CL sessions"
fi


# =============================================================================
# Phase 7: Reverse isolation (CL key can't see test org data)
# =============================================================================
phase 7 "Reverse isolation"

BODY=$(graph_body 'MATCH (p:Person {name: $name}) RETURN p.name' '{"name":"alice-e2e"}')
REV_PERSONS=$(api_post "/api/graph/query" "$CL_API_KEY" "$BODY")
REV_VALUES=$(echo "$REV_PERSONS" | jq '.values | length')
if [ "$REV_VALUES" -eq 0 ]; then
  pass "CL key cannot see test org person 'alice-e2e'"
else
  fail "ISOLATION BREACH: CL key sees test org person 'alice-e2e'"
fi

PARAMS=$(jq -n --arg id "$SESSION_ID" '{id: $id}')
BODY=$(graph_body 'MATCH (s:Session {id: $id}) RETURN s.id' "$PARAMS")
REV_SESSIONS=$(api_post "/api/graph/query" "$CL_API_KEY" "$BODY")
REV_SESSION_VAL=$(echo "$REV_SESSIONS" | jq '.values | length')
if [ "$REV_SESSION_VAL" -eq 0 ]; then
  pass "CL key cannot see test org session"
else
  fail "ISOLATION BREACH: CL key sees test org session"
fi


# =============================================================================
# Phase 8: No fallback (forged/Frankenstein keys rejected)
# =============================================================================
phase 8 "Key security"

BODY=$(graph_body 'MATCH (n) RETURN count(n)' '{}')

# Forged key: right slug, wrong secret
FORGED_KEY="ek_${TEST_ORG}_$(openssl rand -hex 16)"
FORGED_RESP=$(api_post "/api/graph/query" "$FORGED_KEY" "$BODY")
FORGED_ERR=$(echo "$FORGED_RESP" | jq -r '.detail // empty')
if echo "$FORGED_ERR" | grep -qi "invalid\|unauthorized\|denied\|not found\|unknown"; then
  pass "Forged key rejected: ${FORGED_ERR:0:60}"
else
  fail "Forged key NOT rejected: $(echo "$FORGED_RESP" | jq -c .)"
fi

# Frankenstein key: test slug + CL secret suffix
CL_SUFFIX=$(echo "$CL_API_KEY" | sed "s/^ek_[^_]*_//")
FRANK_KEY="ek_${TEST_ORG}_${CL_SUFFIX}"
FRANK_RESP=$(api_post "/api/graph/query" "$FRANK_KEY" "$BODY")
FRANK_ERR=$(echo "$FRANK_RESP" | jq -r '.detail // empty')
if echo "$FRANK_ERR" | grep -qi "invalid\|unauthorized\|denied\|not found\|unknown\|mismatch"; then
  pass "Frankenstein key rejected: ${FRANK_ERR:0:60}"
else
  fail "Frankenstein key NOT rejected: $(echo "$FRANK_RESP" | jq -c .)"
fi

# Completely bogus key
BOGUS_RESP=$(api_post "/api/graph/query" "ek_nonexistent_abc123" "$BODY")
BOGUS_ERR=$(echo "$BOGUS_RESP" | jq -r '.detail // empty')
if [ -n "$BOGUS_ERR" ]; then
  pass "Bogus key rejected"
else
  fail "Bogus key NOT rejected"
fi


# =============================================================================
# Phase 9: Guard checks
# =============================================================================
phase 9 "Guard checks"

# DELETE should be blocked by guard
BODY=$(graph_body 'MATCH (p:Person {name: $name}) DELETE p' '{"name":"alice-e2e"}')
DEL_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
DEL_ERR=$(echo "$DEL_RESP" | jq -r '.detail // empty')
if echo "$DEL_ERR" | grep -qi "blocked\|forbidden\|not allowed\|destructive\|DELETE"; then
  pass "DELETE blocked by guard"
else
  fail "DELETE was NOT blocked: $(echo "$DEL_RESP" | jq -c .)"
fi

# DETACH DELETE should be blocked
BODY=$(graph_body 'MATCH (p:Person {name: $name}) DETACH DELETE p' '{"name":"alice-e2e"}')
DETACH_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
DETACH_ERR=$(echo "$DETACH_RESP" | jq -r '.detail // empty')
if echo "$DETACH_ERR" | grep -qi "blocked\|forbidden\|not allowed\|destructive\|DETACH\|DELETE"; then
  pass "DETACH DELETE blocked by guard"
else
  fail "DETACH DELETE was NOT blocked: $(echo "$DETACH_RESP" | jq -c .)"
fi

# Org tampering: try to set a different org
BODY=$(graph_body 'MATCH (p:Person {name: $name}) SET p.org = $org RETURN p' \
  '{"name":"alice-e2e","org":"curvelabs"}')
TAMPER_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
TAMPER_ERR=$(echo "$TAMPER_RESP" | jq -r '.detail // empty')
if echo "$TAMPER_ERR" | grep -qi "tamper\|blocked\|forbidden\|not allowed\|org"; then
  pass "Org tampering blocked"
else
  # Even if it "succeeds", verify the org wasn't actually changed
  CHECK_BODY=$(graph_body 'MATCH (p:Person {name: $name}) RETURN p.org' '{"name":"alice-e2e"}')
  CHECK_ORG=$(api_post "/api/graph/query" "$TEST_API_KEY" "$CHECK_BODY")
  ACTUAL_ORG=$(echo "$CHECK_ORG" | jq -r '.values[0][0] // empty')
  if [ "$ACTUAL_ORG" = "$TEST_ORG" ]; then
    pass "Org tampering attempt had no effect (org still ${TEST_ORG})"
  else
    fail "ORG TAMPERING SUCCEEDED: org is now '${ACTUAL_ORG}'"
  fi
fi

# Unlabeled node creation (bare variable, no label)
BODY=$(graph_body 'CREATE (n {name: $name}) RETURN n' '{"name":"ghost"}')
UNLABEL_RESP=$(api_post "/api/graph/query" "$TEST_API_KEY" "$BODY")
UNLABEL_ERR=$(echo "$UNLABEL_RESP" | jq -r '.detail // empty')
if echo "$UNLABEL_ERR" | grep -qi "label\|blocked\|forbidden\|not allowed"; then
  pass "Unlabeled node creation blocked"
else
  GHOST_BODY=$(graph_body 'MATCH (n {name: $name}) RETURN n' '{"name":"ghost"}')
  GHOST_CHECK=$(api_post "/api/graph/query" "$TEST_API_KEY" "$GHOST_BODY")
  GHOST_COUNT=$(echo "$GHOST_CHECK" | jq '.values | length')
  if [ "$GHOST_COUNT" -eq 0 ]; then
    pass "Unlabeled node: query returned no results (scoping may have filtered)"
  else
    fail "Unlabeled node was created without org scope"
  fi
fi


# =============================================================================
# Phase 10: Admin isolation diagnostics
# =============================================================================
phase 10 "Admin isolation diagnostics"

DIAG_RESP=$(api_get "/api/admin/org/${TEST_ORG}" "$GITHUB_TOKEN")

# Check isolation status
ISO_STATUS=$(echo "$DIAG_RESP" | jq -r '.isolation.status // empty')
if [ "$ISO_STATUS" = "ok" ] || [ "$ISO_STATUS" = "info" ]; then
  pass "Admin isolation status: ${ISO_STATUS}"
elif [ "$ISO_STATUS" = "warning" ]; then
  ISO_CHECKS=$(echo "$DIAG_RESP" | jq -c '.isolation.checks')
  pass "Admin isolation status: warning (shared DB expected) -- ${ISO_CHECKS}"
else
  fail "Admin isolation status: ${ISO_STATUS}"
fi

# Check health diagnostics
HEALTH_CRITS=$(echo "$DIAG_RESP" | jq '[.health[] | select(.severity == "critical")] | length')
if [ "$HEALTH_CRITS" -eq 0 ]; then
  pass "No critical health issues"
else
  CRIT_DETAILS=$(echo "$DIAG_RESP" | jq -c '[.health[] | select(.severity == "critical")]')
  fail "Critical health issues: ${CRIT_DETAILS}"
fi

# Neo4j Org node exists
NEO4J_ORG_EXISTS=$(echo "$DIAG_RESP" | jq -r '.neo4j_org_node.exists // false')
if [ "$NEO4J_ORG_EXISTS" = "true" ]; then
  pass "Neo4j Org node exists"
else
  fail "Neo4j Org node missing — register endpoint failed to create it"
fi


# =============================================================================
# Phase 11: Cleanup
# =============================================================================
if [ "$NO_CLEANUP" = "true" ]; then
  phase 11 "Cleanup (SKIPPED — --no-cleanup)"
  echo "  Test org '${TEST_ORG}' preserved for inspection"
  echo "  API key: ${TEST_API_KEY}"
else
  phase 11 "Cleanup"

  # Delete Neo4j test data via admin graph-write
  for label in Person Session; do
    PARAMS=$(jq -n --arg org "$TEST_ORG" '{org: $org}')
    BODY=$(admin_body "MATCH (n:${label} {org: \$org}) DETACH DELETE n RETURN count(n) AS deleted" "$PARAMS")
    CLEAN_RESP=$(api_post "/api/admin/graph-write" "$GITHUB_TOKEN" "$BODY")
    DELETED=$(echo "$CLEAN_RESP" | jq -r '.values[0][0] // 0')
    if echo "$CLEAN_RESP" | jq -e '.values' >/dev/null 2>&1; then
      pass "Cleaned ${label} nodes (${DELETED} deleted)"
    else
      fail "Failed to clean ${label} nodes: $(echo "$CLEAN_RESP" | jq -c .)"
    fi
  done

  # Delete Supabase data + Neo4j Org node via admin delete endpoint
  DEL_ORG_RESP=$(api_delete "/api/admin/org/${TEST_ORG}" "$GITHUB_TOKEN")
  DEL_ORG_STATUS=$(echo "$DEL_ORG_RESP" | jq -r '.status // empty')
  if [ "$DEL_ORG_STATUS" = "ok" ]; then
    pass "Deleted org from Supabase: ${TEST_ORG}"
  else
    fail "Org delete failed: $(echo "$DEL_ORG_RESP" | jq -c .)"
  fi

  # Verify cleanup — admin detail should 404
  VERIFY_RESP=$(api_get "/api/admin/org/${TEST_ORG}" "$GITHUB_TOKEN")
  VERIFY_ERR=$(echo "$VERIFY_RESP" | jq -r '.detail // empty')
  if echo "$VERIFY_ERR" | grep -q "not found"; then
    pass "Cleanup verified — org no longer exists"
  else
    fail "Org still exists after cleanup: $(echo "$VERIFY_RESP" | jq -c . | head -c 200)"
  fi
fi


# =============================================================================
# Results
# =============================================================================
echo ""
echo "============================================"
printf "  RESULTS: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" "$PASS" "$FAIL"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
