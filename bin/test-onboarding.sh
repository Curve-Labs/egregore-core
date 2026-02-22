#!/bin/bash
set -euo pipefail

# Comprehensive validation for the onboarding seed architecture.
# No mocks — validates real files, real cross-references, real state contracts.
#
# Tests:
#   1.  egregore.md structure
#   2.  onboarding.md state machine completeness
#   3.  State machine transition integrity
#   4.  CLAUDE.md — no orphaned onboarding refs
#   5.  Backward compat — state keys consumed by bin/ scripts
#   6.  Script dependencies exist
#   7.  egregore.md ↔ onboarding.md integration
#   8.  Tutorial ↔ onboarding integration
#   9.  AskUserQuestion spec compliance
#   10. .syncignore includes egregore.md
#   11. CLAUDE.md preserved sections
#   12. State machine HALT conditions have clear messages
#   13. API endpoint consistency
#   14. Cypher query safety (graph.sh usage, no direct curl)
#   15. Consent backward compat contract
#   16. API model ↔ schema ↔ service alignment
#   17. Migration file
#   18. Onboarding COMPLETE → API field pass-through
#   19. CLAUDE.md state format updated
#
# Usage:
#   bash bin/test-onboarding.sh

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

PASS=0
FAIL=0
WARN=0

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
DIM='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

pass() {
  PASS=$((PASS + 1))
  echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo -e "  ${RED}✗ FAIL${NC}: $1"
  [ -n "${2:-}" ] && echo -e "    ${DIM}$2${NC}"
}

warn() {
  WARN=$((WARN + 1))
  echo -e "  ${YELLOW}⚠ WARN${NC}: $1"
  [ -n "${2:-}" ] && echo -e "    ${DIM}$2${NC}"
}

section() {
  echo ""
  echo -e "  ${BOLD}$1${NC}"
}

# ============================================================
# File paths
# ============================================================
EGREGORE_MD="$SCRIPT_DIR/egregore.md"
ONBOARDING_MD="$SCRIPT_DIR/.claude/commands/onboarding.md"
TUTORIAL_MD="$SCRIPT_DIR/.claude/commands/tutorial.md"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
SYNCIGNORE="$SCRIPT_DIR/.syncignore"

echo ""
echo -e "${BOLD}Onboarding Seed Architecture — Validation Suite${NC}"
echo -e "${DIM}────────────────────────────────────────────────${NC}"

# ============================================================
# TEST 1: egregore.md structure
# ============================================================
section "[1/19] egregore.md structure"

if [ ! -f "$EGREGORE_MD" ]; then
  fail "egregore.md does not exist"
else
  pass "egregore.md exists"

  REQUIRED_SECTIONS=("Identity" "Culture" "Members" "Collaboration" "Aspirations" "State")
  for sec in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "^## $sec" "$EGREGORE_MD"; then
      pass "Section '## $sec' present"
    else
      fail "Missing section '## $sec' in egregore.md"
    fi
  done

  # Check non-empty content in key sections
  for sec in "Identity" "Culture" "Collaboration" "Aspirations"; do
    # Extract content between this section and the next ## heading
    CONTENT=$(sed -n "/^## $sec/,/^## /p" "$EGREGORE_MD" | grep -v "^##" | grep -v "^$" | grep -v "^<!--" | head -1)
    if [ -n "$CONTENT" ]; then
      pass "Section '$sec' has content"
    else
      fail "Section '$sec' is empty in egregore.md"
    fi
  done
fi

# ============================================================
# TEST 2: onboarding.md state machine completeness
# ============================================================
section "[2/19] onboarding.md state machine completeness"

if [ ! -f "$ONBOARDING_MD" ]; then
  fail "onboarding.md does not exist"
else
  pass "onboarding.md exists"

  # Check state machine declaration
  if grep -q "VERIFY → WELCOME → HARVEST_IDENTITY → HARVEST_CONNECTION → CONSENT → ORIENT → COMPLETE" "$ONBOARDING_MD"; then
    pass "State machine declaration present"
  else
    fail "State machine declaration missing or malformed"
  fi

  # Check all 7 states are defined as ## headers
  STATES=("VERIFY" "WELCOME" "HARVEST_IDENTITY" "HARVEST_CONNECTION" "CONSENT" "ORIENT" "COMPLETE")
  for state in "${STATES[@]}"; do
    if grep -q "^## State: $state" "$ONBOARDING_MD"; then
      pass "State '$state' defined"
    else
      fail "State '$state' not defined as ## heading"
    fi
  done

  # Check each state has Entry, Actions, Exit/transition
  for state in "${STATES[@]}"; do
    STATE_BLOCK=$(sed -n "/^## State: $state/,/^## /p" "$ONBOARDING_MD")

    if echo "$STATE_BLOCK" | grep -q "Entry:"; then
      pass "$state has Entry condition"
    else
      fail "$state missing Entry condition"
    fi

    if echo "$STATE_BLOCK" | grep -qi "Actions"; then
      pass "$state has Actions"
    else
      fail "$state missing Actions section"
    fi

    if echo "$STATE_BLOCK" | grep -qiE "Exit.*→|→.*COMPLETE|→.*always|HALT|Done"; then
      pass "$state has exit/transition"
    else
      fail "$state missing exit transition"
    fi
  done

  # Resumption section
  if grep -q "^## Resumption" "$ONBOARDING_MD"; then
    pass "Resumption section present"
  else
    fail "Resumption section missing"
  fi
fi

# ============================================================
# TEST 3: State machine transition integrity
# ============================================================
section "[3/19] State machine transition integrity"

if [ -f "$ONBOARDING_MD" ]; then
  # Each state should transition to the next state in sequence
  TRANSITIONS=(
    "VERIFY:WELCOME"
    "WELCOME:HARVEST_IDENTITY"
    "HARVEST_IDENTITY:HARVEST_CONNECTION"
    "HARVEST_CONNECTION:CONSENT"
    "CONSENT:ORIENT"
    "ORIENT:COMPLETE"
  )

  for trans in "${TRANSITIONS[@]}"; do
    FROM="${trans%%:*}"
    TO="${trans##*:}"
    STATE_BLOCK=$(sed -n "/^## State: $FROM/,/^## State:/p" "$ONBOARDING_MD" | sed '$d')

    if echo "$STATE_BLOCK" | grep -q "→ $TO"; then
      pass "$FROM → $TO transition found"
    else
      fail "$FROM → $TO transition missing" "State $FROM doesn't reference $TO"
    fi
  done

  # COMPLETE should NOT transition to another state (terminal)
  COMPLETE_BLOCK=$(sed -n "/^## State: COMPLETE/,\$p" "$ONBOARDING_MD")
  if echo "$COMPLETE_BLOCK" | grep -qE "→ (VERIFY|WELCOME|HARVEST|CONSENT|ORIENT)"; then
    fail "COMPLETE has unexpected forward transition"
  else
    pass "COMPLETE is terminal state"
  fi

  # Check no transition targets a state that doesn't exist
  # HALT is a valid stop condition, not a state — exclude it
  ALL_TRANSITIONS=$(grep -oE '→ [A-Z_]+' "$ONBOARDING_MD" | sort -u | sed 's/→ //' | grep -v '^HALT$')
  DEFINED_STATES="VERIFY WELCOME HARVEST_IDENTITY HARVEST_CONNECTION CONSENT ORIENT COMPLETE"
  DANGLING=false
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    if ! echo "$DEFINED_STATES" | grep -qw "$target"; then
      fail "Transition to undefined state: $target"
      DANGLING=true
    fi
  done <<< "$ALL_TRANSITIONS"
  $DANGLING || pass "No dangling transitions"
fi

# ============================================================
# TEST 4: CLAUDE.md — no orphaned onboarding references
# ============================================================
section "[4/19] CLAUDE.md — no orphaned onboarding refs"

if [ -f "$CLAUDE_MD" ]; then
  # Old onboarding section markers that should be gone
  OLD_REFS=(
    "### Step 0: Organization Setup"
    "### Step 1: Name"
    "### Step 2: GitHub Auth"
    "### Step 3: Workspace Setup"
    "### Step 4: Shell alias"
    "### Step 5: Complete"
    "#### Path A: Founder"
    "#### Path B: Joiner"
    "Founder path"
    "Joiner path"
    "Run these steps in order"
  )

  ALL_CLEAN=true
  for ref in "${OLD_REFS[@]}"; do
    if grep -qF "$ref" "$CLAUDE_MD"; then
      fail "Orphaned reference: '$ref'" "Old onboarding section not fully removed"
      ALL_CLEAN=false
    fi
  done
  $ALL_CLEAN && pass "No orphaned old onboarding references"

  # New onboarding pointer exists
  if grep -q "invoke.*\`/onboarding\`\|invoke.*/onboarding" "$CLAUDE_MD"; then
    pass "CLAUDE.md has /onboarding pointer"
  else
    fail "CLAUDE.md missing /onboarding pointer"
  fi

  # Exception: Onboarding needed — should route to /onboarding, not "Steps below"
  if grep -q "Onboarding Steps below" "$CLAUDE_MD"; then
    fail "Exception section still says 'Onboarding Steps below'" "Should route to /onboarding"
  else
    pass "Exception section routes to /onboarding"
  fi

  # The Onboarding section should be short (< 10 lines)
  ONBOARDING_SECTION=$(sed -n '/^## Onboarding$/,/^## /p' "$CLAUDE_MD" | sed '$d')
  LINE_COUNT=$(echo "$ONBOARDING_SECTION" | wc -l | tr -d ' ')
  if [ "$LINE_COUNT" -le 10 ]; then
    pass "Onboarding section is concise ($LINE_COUNT lines)"
  else
    warn "Onboarding section is $LINE_COUNT lines (expected < 10)"
  fi
fi

# ============================================================
# TEST 5: Backward compat — state keys consumed by bin/ scripts
# ============================================================
section "[5/19] Backward compatibility — state key contracts"

# telemetry.sh reads .telemetry (flat key)
if grep -q '\.telemetry' "$SCRIPT_DIR/bin/telemetry.sh"; then
  # Verify onboarding writes flat telemetry key
  if grep -q '"telemetry":' "$ONBOARDING_MD"; then
    pass "telemetry.sh ↔ onboarding: flat 'telemetry' key written"
  else
    fail "onboarding.md doesn't write flat 'telemetry' key" "bin/telemetry.sh reads .telemetry from state"
  fi
fi

# transcript-archive.sh reads .transcript_sharing (flat key)
if grep -q 'transcript_sharing' "$SCRIPT_DIR/bin/transcript-archive.sh"; then
  if grep -q '"transcript_sharing":' "$ONBOARDING_MD"; then
    pass "transcript-archive.sh ↔ onboarding: flat 'transcript_sharing' key"
  else
    fail "onboarding.md doesn't write flat 'transcript_sharing' key" "bin/transcript-archive.sh reads .transcript_sharing"
  fi
fi

# session-start.sh reads .onboarding_complete
if grep -q 'onboarding_complete' "$SCRIPT_DIR/bin/session-start.sh"; then
  if grep -q '"onboarding_complete":' "$ONBOARDING_MD"; then
    pass "session-start.sh ↔ onboarding: 'onboarding_complete' key"
  else
    fail "onboarding.md doesn't write 'onboarding_complete' key"
  fi
fi

# session-start.sh reads .github_username, .display_name, .usage_type
STATE_KEYS_IN_SESSION=("github_username" "display_name" "usage_type")
for key in "${STATE_KEYS_IN_SESSION[@]}"; do
  if grep -q "$key" "$SCRIPT_DIR/bin/session-start.sh"; then
    if grep -q "\"$key\":" "$ONBOARDING_MD" || grep -q "'$key'" "$ONBOARDING_MD" || grep -q "$key" "$ONBOARDING_MD"; then
      pass "session-start.sh ↔ onboarding: '$key' key"
    else
      warn "Key '$key' used by session-start.sh but not clearly written in onboarding.md"
    fi
  fi
done

# Onboarding mentions backward compat explicitly
if grep -qi "backward compat" "$ONBOARDING_MD"; then
  pass "Backward compatibility explicitly documented"
else
  warn "No explicit backward compat note in onboarding.md"
fi

# ============================================================
# TEST 6: Script dependencies exist
# ============================================================
section "[6/19] Script dependencies exist"

# Scripts referenced in onboarding.md
ONBOARDING_SCRIPTS=$(grep -oE 'bin/[a-z_-]+\.sh' "$ONBOARDING_MD" | sort -u)
ALL_FOUND=true
while IFS= read -r script; do
  [ -z "$script" ] && continue
  if [ -f "$SCRIPT_DIR/$script" ]; then
    pass "$script exists"
  else
    fail "Referenced script missing: $script"
    ALL_FOUND=false
  fi
done <<< "$ONBOARDING_SCRIPTS"

# Commands referenced via /command in onboarding.md
COMMANDS=$(grep -oE '/[a-z_-]+' "$ONBOARDING_MD" | grep -v '/api/' | grep -v '/env' | grep -v '/onboarding' | sort -u | head -10)
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  CMD_NAME="${cmd#/}"
  CMD_FILE="$SCRIPT_DIR/.claude/commands/${CMD_NAME}.md"
  if [ -f "$CMD_FILE" ]; then
    pass "Command $cmd → ${CMD_NAME}.md exists"
  elif [ "$CMD_NAME" = "telemetry" ] || [ "$CMD_NAME" = "env" ] || [ "$CMD_NAME" = "me" ] || [ "$CMD_NAME" = "quest" ]; then
    # These are known commands, check they exist
    if [ -f "$CMD_FILE" ]; then
      pass "Command $cmd → ${CMD_NAME}.md exists"
    else
      warn "Command $cmd referenced but ${CMD_NAME}.md not found"
    fi
  fi
done <<< "$COMMANDS"

# ============================================================
# TEST 7: egregore.md ↔ onboarding.md integration
# ============================================================
section "[7/19] egregore.md ↔ onboarding.md integration"

if [ -f "$EGREGORE_MD" ] && [ -f "$ONBOARDING_MD" ]; then
  # Onboarding reads Identity section
  if grep -q "Identity" "$ONBOARDING_MD" && grep -q "^## Identity" "$EGREGORE_MD"; then
    pass "Onboarding reads Identity → section exists"
  else
    fail "Onboarding references Identity but section missing"
  fi

  # Onboarding reads Culture section
  if grep -q "Culture" "$ONBOARDING_MD" && grep -q "^## Culture" "$EGREGORE_MD"; then
    pass "Onboarding reads Culture → section exists"
  else
    fail "Onboarding references Culture but section missing"
  fi

  # Onboarding reads Collaboration section
  if grep -q "Collaboration" "$ONBOARDING_MD" && grep -q "^## Collaboration" "$EGREGORE_MD"; then
    pass "Onboarding reads Collaboration → section exists"
  else
    fail "Onboarding references Collaboration but section missing"
  fi

  # Onboarding updates Members section
  if grep -q "Members" "$ONBOARDING_MD" && grep -q "^## Members" "$EGREGORE_MD"; then
    pass "Onboarding updates Members → section exists"
  else
    fail "Onboarding writes to Members but section missing"
  fi

  # Collaboration section has parseable work areas (at least 2 lines with content)
  COLLAB_LINES=$(sed -n '/^## Collaboration/,/^## /p' "$EGREGORE_MD" | grep -v "^##" | grep -v "^$" | grep -v "^<!--" | grep -v "^Active" | wc -l | tr -d ' ')
  if [ "$COLLAB_LINES" -ge 2 ]; then
    pass "Collaboration has $COLLAB_LINES parseable work areas (need ≥2)"
  else
    fail "Collaboration section has fewer than 2 work areas ($COLLAB_LINES)"
  fi

  # Default fallback mentioned in onboarding
  if grep -q "Building / Exploring / Participating\|defaults:" "$ONBOARDING_MD"; then
    pass "Fallback options documented if Collaboration section too short"
  else
    warn "No fallback options documented for sparse Collaboration sections"
  fi
fi

# ============================================================
# TEST 8: Tutorial ↔ onboarding integration
# ============================================================
section "[8/19] Tutorial ↔ onboarding integration"

if [ -f "$TUTORIAL_MD" ] && [ -f "$ONBOARDING_MD" ]; then
  # Tutorial references harvest_rounds from onboarding
  if grep -q "harvest_rounds" "$TUTORIAL_MD"; then
    pass "Tutorial reads onboarding.harvest_rounds"
  else
    fail "Tutorial doesn't reference harvest_rounds" "Can't skip redundant questions"
  fi

  # Onboarding writes harvest_rounds
  if grep -q "harvest_rounds" "$ONBOARDING_MD"; then
    pass "Onboarding writes harvest_rounds to state"
  else
    fail "Onboarding doesn't write harvest_rounds to state"
  fi

  # Tutorial references onboarding.type for usage_type detection
  if grep -q 'onboarding.type' "$TUTORIAL_MD" || grep -q 'onboarding.*joiner' "$TUTORIAL_MD"; then
    pass "Tutorial detects joiner via onboarding.type"
  else
    warn "Tutorial doesn't reference onboarding.type for usage_type detection"
  fi

  # Tutorial has skip logic for domain
  if grep -qi "skip.*Q1\|skip.*domain\|already.*set.*state\|already exists in state" "$TUTORIAL_MD"; then
    pass "Tutorial has skip logic when domain is pre-set"
  else
    fail "Tutorial missing skip logic for pre-set domain"
  fi

  # Tutorial harvest data mapping documented (role → domain)
  if grep -q "engineering.*software\|role.*domain" "$TUTORIAL_MD"; then
    pass "Role → domain mapping documented"
  else
    warn "Role → domain mapping not explicitly documented in tutorial"
  fi
fi

# ============================================================
# TEST 9: AskUserQuestion spec compliance
# ============================================================
section "[9/19] AskUserQuestion spec compliance"

if [ -f "$ONBOARDING_MD" ]; then
  # Count options in each question block (2-4 required by tool)
  # Extract all question blocks and check option counts
  QUESTION_BLOCKS=$(grep -c "header:" "$ONBOARDING_MD")
  pass "Found $QUESTION_BLOCKS question specs"

  # Check all headers are ≤12 chars
  LONG_HEADERS=false
  while IFS= read -r line; do
    HEADER_VAL=$(echo "$line" | sed 's/.*header:.*"\(.*\)".*/\1/' | sed "s/.*header: *//")
    # Strip quotes and whitespace
    HEADER_VAL=$(echo "$HEADER_VAL" | tr -d '"' | xargs)
    if [ ${#HEADER_VAL} -gt 12 ] && [ -n "$HEADER_VAL" ]; then
      fail "Header too long (${#HEADER_VAL} chars): '$HEADER_VAL'" "AskUserQuestion max is 12"
      LONG_HEADERS=true
    fi
  done < <(grep "header:" "$ONBOARDING_MD")
  $LONG_HEADERS || pass "All headers ≤12 chars"

  # Check multiSelect only used in CONSENT state
  MULTI_USES=$(grep -n "multiSelect" "$ONBOARDING_MD" | grep -v "false")
  MULTI_COUNT=$(echo "$MULTI_USES" | grep -c "true" || true)
  if [ "$MULTI_COUNT" -eq 1 ]; then
    # Verify it's in the CONSENT section
    MULTI_LINE=$(echo "$MULTI_USES" | grep "true" | cut -d: -f1)
    CONSENT_START=$(grep -n "^## State: CONSENT" "$ONBOARDING_MD" | cut -d: -f1)
    ORIENT_START=$(grep -n "^## State: ORIENT" "$ONBOARDING_MD" | cut -d: -f1)
    if [ "$MULTI_LINE" -gt "$CONSENT_START" ] && [ "$MULTI_LINE" -lt "$ORIENT_START" ]; then
      pass "multiSelect: true only in CONSENT state (correct)"
    else
      fail "multiSelect: true found outside CONSENT state"
    fi
  elif [ "$MULTI_COUNT" -eq 0 ]; then
    fail "No multiSelect: true found" "CONSENT should use multiSelect"
  else
    warn "multiSelect: true used $MULTI_COUNT times (expected 1)"
  fi

  # Check option counts per question (each should have 2-4)
  # Count options under each question by looking for "label:" patterns
  # We check blocks between Q headers
  OPTION_ISSUES=false
  CURRENT_Q=""
  OPTION_COUNT=0
  while IFS= read -r line; do
    if echo "$line" | grep -qE '^\s+Q[0-9]:'; then
      if [ -n "$CURRENT_Q" ] && { [ "$OPTION_COUNT" -lt 2 ] || [ "$OPTION_COUNT" -gt 4 ]; }; then
        fail "$CURRENT_Q has $OPTION_COUNT options (need 2-4)"
        OPTION_ISSUES=true
      fi
      CURRENT_Q=$(echo "$line" | grep -oE 'Q[0-9]')
      OPTION_COUNT=0
    fi
    if echo "$line" | grep -qE '^\s+- label:'; then
      OPTION_COUNT=$((OPTION_COUNT + 1))
    fi
  done < "$ONBOARDING_MD"
  $OPTION_ISSUES || pass "All question option counts within 2-4 range"
fi

# ============================================================
# TEST 10: .syncignore includes egregore.md
# ============================================================
section "[10/19] .syncignore"

if [ -f "$SYNCIGNORE" ]; then
  if grep -q "^egregore\.md$" "$SYNCIGNORE"; then
    pass "egregore.md in .syncignore"
  else
    fail "egregore.md NOT in .syncignore" "Org identity will sync to public repo"
  fi
else
  fail ".syncignore does not exist"
fi

# ============================================================
# TEST 11: CLAUDE.md preserved sections
# ============================================================
section "[11/19] CLAUDE.md preserved sections"

if [ -f "$CLAUDE_MD" ]; then
  PRESERVED_SECTIONS=(
    "## On Launch"
    "## After Greeting"
    "## Config Files"
    "## Knowledge Graph"
    "## Notifications"
    "## Transparency Beat"
    "## State File Format"
    "## Memory"
    "## Git Workflow"
    "## Working Conventions"
    "## Command Awareness"
    "## Socratic Questioning"
    "## Telemetry"
    "## Environment Isolation"
  )

  ALL_PRESERVED=true
  for sec in "${PRESERVED_SECTIONS[@]}"; do
    if grep -qF "$sec" "$CLAUDE_MD"; then
      : # present, good
    else
      fail "Missing preserved section: '$sec'"
      ALL_PRESERVED=false
    fi
  done
  $ALL_PRESERVED && pass "All ${#PRESERVED_SECTIONS[@]} preserved sections intact"
fi

# ============================================================
# TEST 12: HALT conditions have clear messages
# ============================================================
section "[12/19] HALT conditions have clear messages"

if [ -f "$ONBOARDING_MD" ]; then
  # Every HALT should have a user-facing message in quotes
  HALT_COUNT=$(grep -c "HALT:" "$ONBOARDING_MD" || true)
  HALT_WITH_MSG=$(grep "HALT:" "$ONBOARDING_MD" | grep -c '"' || true)

  if [ "$HALT_COUNT" -eq 0 ]; then
    fail "No HALT conditions found" "VERIFY should have HALT for missing tokens/keys"
  elif [ "$HALT_COUNT" -eq "$HALT_WITH_MSG" ]; then
    pass "All $HALT_COUNT HALT conditions have user-facing messages"
  else
    fail "$((HALT_COUNT - HALT_WITH_MSG)) of $HALT_COUNT HALTs missing user message"
  fi

  # VERIFY should have HALTs for missing GITHUB_TOKEN and EGREGORE_API_KEY
  VERIFY_BLOCK=$(sed -n '/^## State: VERIFY/,/^## State: WELCOME/p' "$ONBOARDING_MD")
  if echo "$VERIFY_BLOCK" | grep -q "GITHUB_TOKEN.*HALT\|HALT.*GITHUB_TOKEN\|HALT.*GitHub auth"; then
    pass "VERIFY HALTs on missing GITHUB_TOKEN"
  else
    fail "VERIFY doesn't HALT on missing GITHUB_TOKEN"
  fi

  if echo "$VERIFY_BLOCK" | grep -q "EGREGORE_API_KEY.*HALT\|HALT.*EGREGORE_API_KEY\|HALT.*API key\|HALT.*api key"; then
    pass "VERIFY HALTs on missing EGREGORE_API_KEY"
  else
    fail "VERIFY doesn't HALT on missing EGREGORE_API_KEY"
  fi
fi

# ============================================================
# TEST 13: API endpoint consistency
# ============================================================
section "[13/19] API endpoint consistency"

if [ -f "$ONBOARDING_MD" ]; then
  # All API calls should use /api/ prefix
  API_CALLS=$(grep -oE '/api/[a-z/]+' "$ONBOARDING_MD" | sort -u || true)
  if [ -n "$API_CALLS" ]; then
    pass "API calls use /api/ prefix"
  else
    warn "No API calls with /api/ prefix found"
  fi

  # Should reference /api/user/ensure
  if grep -q "/api/user/ensure" "$ONBOARDING_MD"; then
    pass "References /api/user/ensure"
  else
    fail "Missing /api/user/ensure call" "Should sync user to Supabase"
  fi

  # API calls should use API_URL from egregore.json and API_KEY from .env
  if grep -q 'jq.*api_url.*egregore.json' "$ONBOARDING_MD"; then
    pass "API_URL read from egregore.json"
  else
    warn "API_URL source not explicitly documented"
  fi

  if grep -q "EGREGORE_API_KEY.*\.env\|\.env.*EGREGORE_API_KEY" "$ONBOARDING_MD"; then
    pass "API_KEY read from .env"
  else
    warn "API_KEY source not explicitly documented"
  fi

  # No hardcoded API URLs (excluding GitHub API which is expected)
  HARDCODED_URLS=$(grep -E 'curl.*https?://[a-z]+\.' "$ONBOARDING_MD" | grep -v 'api.github.com' | grep -v 'API_URL' | grep -v '\$' || true)
  if [ -n "$HARDCODED_URLS" ]; then
    fail "Hardcoded API URL found" "Should use \${API_URL} from config"
  else
    pass "No hardcoded API URLs (excluding GitHub)"
  fi
fi

# ============================================================
# TEST 14: Graph queries use bin/graph.sh
# ============================================================
section "[14/19] Graph query safety"

if [ -f "$ONBOARDING_MD" ]; then
  # All Cypher queries should go through bin/graph.sh
  if grep -q "bin/graph.sh query" "$ONBOARDING_MD"; then
    pass "Cypher queries use bin/graph.sh"
  else
    warn "No graph queries found (expected in ORIENT and COMPLETE)"
  fi

  # No direct curl to Neo4j
  if grep -qiE 'curl.*(neo4j|:7474|:7687|graph/query)' "$ONBOARDING_MD" 2>/dev/null; then
    # Check it's not in bin/graph.sh reference
    DIRECT_NEO4J=$(grep -iE 'curl.*(neo4j|:7474|:7687)' "$ONBOARDING_MD" | grep -v 'bin/graph.sh' || true)
    if [ -n "$DIRECT_NEO4J" ]; then
      fail "Direct curl to Neo4j found" "Use bin/graph.sh instead"
    else
      pass "No direct curl to Neo4j"
    fi
  else
    pass "No direct curl to Neo4j"
  fi

  # MERGE query in COMPLETE has proper parameterization ($github, $name, etc.)
  COMPLETE_BLOCK=$(sed -n '/^## State: COMPLETE/,/^$/p' "$ONBOARDING_MD")
  if grep -q 'MERGE.*\$github' "$ONBOARDING_MD"; then
    pass "Person MERGE uses parameterized query (\$github)"
  else
    warn "Person MERGE may not use parameterized query"
  fi
fi

# ============================================================
# TEST 15: Consent backward compat contract
# ============================================================
section "[15/19] Consent backward compatibility"

if [ -f "$ONBOARDING_MD" ]; then
  # Flat keys that downstream scripts depend on
  CONSENT_FLAT_KEYS=("session_tracking" "transcript_sharing" "telemetry" "contact_preference")

  ALL_FLAT=true
  for key in "${CONSENT_FLAT_KEYS[@]}"; do
    # Check the flat key appears in the state JSON example
    if grep -q "\"$key\":" "$ONBOARDING_MD"; then
      : # found
    else
      fail "Flat consent key '$key' not in state output"
      ALL_FLAT=false
    fi
  done
  $ALL_FLAT && pass "All 4 flat consent keys written to state"

  # Nested consent object also exists (for structured access)
  if grep -q '"consent":' "$ONBOARDING_MD"; then
    pass "Nested consent object also written"
  else
    warn "No nested consent object — only flat keys"
  fi

  # Verify the consent AskUserQuestion maps to the right keys
  if grep -q "Session tracking" "$ONBOARDING_MD" && grep -q "session_tracking" "$ONBOARDING_MD"; then
    pass "Session tracking option → session_tracking key mapping"
  fi
  if grep -q "Transcript sharing" "$ONBOARDING_MD" && grep -q "transcript_sharing" "$ONBOARDING_MD"; then
    pass "Transcript sharing option → transcript_sharing key mapping"
  fi
  if grep -q "Anonymous telemetry" "$ONBOARDING_MD" && grep -q '"telemetry":' "$ONBOARDING_MD"; then
    pass "Anonymous telemetry option → telemetry key mapping"
  fi
  if grep -q "Notifications" "$ONBOARDING_MD" && grep -q "contact_preference" "$ONBOARDING_MD"; then
    pass "Notifications option → contact_preference key mapping"
  fi
fi

# ============================================================
# TEST 16: API model ↔ schema ↔ service alignment
# ============================================================
section "[16/19] API model ↔ schema ↔ service alignment"

MODELS_PY="$SCRIPT_DIR/api/models.py"
SUPABASE_PY="$SCRIPT_DIR/api/services/supabase.py"
MAIN_PY="$SCRIPT_DIR/api/main.py"
SCHEMA_SQL="$SCRIPT_DIR/scripts/supabase_schema.sql"

if [ -f "$MODELS_PY" ] && [ -f "$SUPABASE_PY" ] && [ -f "$MAIN_PY" ] && [ -f "$SCHEMA_SQL" ]; then
  # New fields exist in UserEnsure model
  API_FIELDS=("member_role" "focus" "work_style" "consent_session_tracking" "consent_transcript_sharing" "consent_telemetry" "contact_preference")
  MODEL_OK=true
  for field in "${API_FIELDS[@]}"; do
    if grep -q "$field" "$MODELS_PY"; then
      : # found
    else
      fail "Field '$field' missing from UserEnsure model"
      MODEL_OK=false
    fi
  done
  $MODEL_OK && pass "All 7 new fields in UserEnsure model"

  # Same fields exist in add_membership function signature
  SERVICE_OK=true
  for field in "${API_FIELDS[@]}"; do
    if grep -q "$field" "$SUPABASE_PY"; then
      : # found
    else
      fail "Field '$field' missing from add_membership"
      SERVICE_OK=false
    fi
  done
  $SERVICE_OK && pass "All 7 new fields in add_membership service"

  # user_ensure endpoint passes fields to add_membership
  ENDPOINT_OK=true
  for field in "${API_FIELDS[@]}"; do
    if grep -q "body\.$field\|$field=body\.$field" "$MAIN_PY"; then
      : # found
    else
      fail "Field '$field' not passed from endpoint to service"
      ENDPOINT_OK=false
    fi
  done
  $ENDPOINT_OK && pass "All 7 new fields passed from endpoint to service"

  # Same fields exist as columns in memberships schema
  SCHEMA_OK=true
  for field in "${API_FIELDS[@]}"; do
    if grep -q "$field" "$SCHEMA_SQL"; then
      : # found
    else
      fail "Column '$field' missing from memberships schema"
      SCHEMA_OK=false
    fi
  done
  $SCHEMA_OK && pass "All 7 new columns in memberships schema"

  # display_name column exists in schema (was a pre-existing gap)
  if grep -q "display_name" "$SCHEMA_SQL"; then
    pass "display_name column in schema (gap fixed)"
  else
    fail "display_name still missing from memberships schema"
  fi
else
  warn "Skipping API checks — missing files"
fi

# ============================================================
# TEST 17: Migration file exists and is valid
# ============================================================
section "[17/19] Migration file"

MIGRATION="$SCRIPT_DIR/scripts/migrations/002_memberships_onboarding_fields.sql"
if [ -f "$MIGRATION" ]; then
  pass "Migration file exists"

  # Check it adds all expected columns
  MIGRATION_FIELDS=("display_name" "member_role" "focus" "work_style" "consent_session_tracking" "consent_transcript_sharing" "consent_telemetry" "contact_preference")
  MIGRATION_OK=true
  for field in "${MIGRATION_FIELDS[@]}"; do
    if grep -q "$field" "$MIGRATION"; then
      : # found
    else
      fail "Migration missing ALTER for '$field'"
      MIGRATION_OK=false
    fi
  done
  $MIGRATION_OK && pass "All 8 columns in migration (incl. display_name gap fix)"

  # Uses IF NOT EXISTS (safe to re-run)
  if grep -q "IF NOT EXISTS" "$MIGRATION"; then
    pass "Migration uses IF NOT EXISTS (idempotent)"
  else
    warn "Migration may not be idempotent"
  fi
else
  fail "Migration file missing: scripts/migrations/002_memberships_onboarding_fields.sql"
fi

# ============================================================
# TEST 18: onboarding.md COMPLETE state passes new API fields
# ============================================================
section "[18/19] Onboarding COMPLETE → API field pass-through"

if [ -f "$ONBOARDING_MD" ]; then
  COMPLETE_SECTION=$(sed -n '/^## State: COMPLETE/,$p' "$ONBOARDING_MD")

  NEW_API_FIELDS=("member_role" "focus" "work_style" "consent_session_tracking" "consent_transcript_sharing" "consent_telemetry" "contact_preference")
  COMPLETE_API_OK=true
  for field in "${NEW_API_FIELDS[@]}"; do
    if echo "$COMPLETE_SECTION" | grep -q "$field"; then
      : # found
    else
      fail "COMPLETE state missing '$field' in API call"
      COMPLETE_API_OK=false
    fi
  done
  $COMPLETE_API_OK && pass "All 7 new fields in COMPLETE state API call"
fi

# ============================================================
# TEST 19: CLAUDE.md state format shows new structure
# ============================================================
section "[19/19] CLAUDE.md state format updated"

if [ -f "$CLAUDE_MD" ]; then
  STATE_SECTION=$(sed -n '/^## State File Format/,/^## /p' "$CLAUDE_MD")

  if echo "$STATE_SECTION" | grep -q '"onboarding":'; then
    pass "State format shows nested onboarding object"
  else
    fail "State format missing nested onboarding object"
  fi

  if echo "$STATE_SECTION" | grep -q "harvest_rounds"; then
    pass "State format shows harvest_rounds"
  else
    fail "State format missing harvest_rounds"
  fi

  if echo "$STATE_SECTION" | grep -q '"consent":'; then
    pass "State format shows nested consent object"
  else
    fail "State format missing nested consent object"
  fi

  # Flat keys still present for backward compat
  if echo "$STATE_SECTION" | grep -q '"session_tracking":' && echo "$STATE_SECTION" | grep -q '"transcript_sharing":'; then
    pass "State format preserves flat consent keys"
  else
    warn "Flat consent keys not shown in state format example"
  fi
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo -e "${DIM}────────────────────────────────────────────────${NC}"
if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
  echo -e "${GREEN}  ✓ All $PASS checks passed${NC}"
elif [ $FAIL -eq 0 ]; then
  echo -e "${YELLOW}  ⚠ $PASS passed, $WARN warning(s)${NC}"
else
  echo -e "${RED}  ✗ $PASS passed, $FAIL failure(s), $WARN warning(s)${NC}"
fi
echo ""
echo "{\"pass\":$PASS,\"fail\":$FAIL,\"warn\":$WARN}"

[ $FAIL -eq 0 ]
