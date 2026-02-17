#!/bin/bash
set -euo pipefail

# Static analysis for Egregore command and script files.
# Detects known antipatterns: unguarded Cypher date calls, macOS-incompatible bash,
# direct API curl calls, missing null guards.
#
# Usage:
#   bash bin/test-changes.sh                 # scan changed files (git diff develop)
#   bash bin/test-changes.sh --all           # scan all command and script files
#   bash bin/test-changes.sh file1 file2     # scan specific files
#
# Exit 0 = no FAILs, Exit 1 = any FAILs

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
WARN=0

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
DIM='\033[0;90m'
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

# --- Scope detection ---
FILES=()

if [ "${1:-}" = "--all" ]; then
  # Scan all command and script files
  while IFS= read -r f; do
    [ -f "$f" ] && FILES+=("$f")
  done < <(find "$SCRIPT_DIR/.claude/commands" "$SCRIPT_DIR/bin" -type f \( -name "*.md" -o -name "*.sh" \) 2>/dev/null)
elif [ $# -gt 0 ]; then
  # Scan specific files
  for f in "$@"; do
    if [ -f "$f" ]; then
      FILES+=("$f")
    elif [ -f "$SCRIPT_DIR/$f" ]; then
      FILES+=("$SCRIPT_DIR/$f")
    fi
  done
else
  # Scan changed files vs develop
  while IFS= read -r f; do
    [ -f "$SCRIPT_DIR/$f" ] && FILES+=("$SCRIPT_DIR/$f")
  done < <(git -C "$SCRIPT_DIR" diff origin/develop --name-only 2>/dev/null | grep -E '\.(md|sh)$' || true)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "No testable files found."
  echo '{"pass":0,"fail":0,"warn":0}'
  exit 0
fi

echo "Scanning ${#FILES[@]} file(s)..."
echo ""

# Split files by type for targeted checks
MD_FILES=()
SH_FILES=()
MD_COUNT=0
SH_COUNT=0
for f in "${FILES[@]}"; do
  case "$f" in
    *.md) MD_FILES+=("$f"); MD_COUNT=$((MD_COUNT + 1)) ;;
    *.sh) SH_FILES+=("$f"); SH_COUNT=$((SH_COUNT + 1)) ;;
  esac
done

# ============================================================
# CHECK 1: date(x.field) without toString guard
# Severity: FAIL
# ============================================================
echo -e "  ${DIM}[1/8] Unguarded date() calls...${NC}"
CHECK1_CLEAN=true
for f in ${MD_FILES[@]+"${MD_FILES[@]}"}; do
  fname=$(basename "$f")
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Match date(x.field) where field is date/created/started/completed
    # Exclude lines that have toString( before the date call
    if echo "$line" | grep -qE 'date\([a-z]+\.(date|created|started|completed)\)'; then
      if ! echo "$line" | grep -q 'toString('; then
        fail "Unguarded date() call" "$fname:$lineno — use date(left(toString(x.field), 10))"
        CHECK1_CLEAN=false
      fi
    fi
  done < "$f"
done
$CHECK1_CLEAN && pass "No unguarded date() calls"

# ============================================================
# CHECK 2: .year/.month/.day on mixed-type date fields
# Severity: FAIL
# ============================================================
echo -e "  ${DIM}[2/8] Mixed-type .year/.month/.day access...${NC}"
CHECK2_CLEAN=true
for f in ${MD_FILES[@]+"${MD_FILES[@]}"}; do
  fname=$(basename "$f")
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if echo "$line" | grep -qE '[a-z]+\.(date|created)\.(year|month|day)'; then
      # Allow if preceded by a WITH that converts it, or if using a safe alias like sDate
      if ! echo "$line" | grep -qE '(sDate|safeDate|dateVal)\.(year|month|day)'; then
        fail ".year/.month/.day on mixed-type field" "$fname:$lineno — convert with date(left(toString(...), 10)) first"
        CHECK2_CLEAN=false
      fi
    fi
  done < "$f"
done
$CHECK2_CLEAN && pass "No .year/.month/.day on mixed-type fields"

# ============================================================
# CHECK 3: MATCH without LIMIT (stateful block parse)
# Severity: WARN
# ============================================================
echo -e "  ${DIM}[3/8] MATCH without LIMIT...${NC}"
CHECK3_CLEAN=true
for f in ${MD_FILES[@]+"${MD_FILES[@]}"}; do
  fname=$(basename "$f")
  in_cypher=false
  has_return=false
  has_limit=false
  has_aggregate=false
  has_nolimit_comment=false
  block_start=0
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Detect cypher block start
    if echo "$line" | grep -qE '^\s*```cypher'; then
      in_cypher=true
      has_return=false
      has_limit=false
      has_aggregate=false
      has_nolimit_comment=false
      block_start=$lineno
      continue
    fi
    # Detect block end
    if $in_cypher && echo "$line" | grep -qE '^\s*```\s*$'; then
      if $has_return && ! $has_limit && ! $has_aggregate && ! $has_nolimit_comment; then
        warn "MATCH without LIMIT in Cypher block" "$fname:$block_start"
        CHECK3_CLEAN=false
      fi
      in_cypher=false
      continue
    fi
    if $in_cypher; then
      echo "$line" | grep -qi 'RETURN' && has_return=true
      echo "$line" | grep -qi 'LIMIT' && has_limit=true
      # Aggregates like count(), sum(), avg() naturally limit results
      echo "$line" | grep -qiE '(count|sum|avg|collect|min|max)\(' && has_aggregate=true
      # Explicit opt-out comment
      echo "$line" | grep -qi 'No LIMIT' && has_nolimit_comment=true
    fi
  done < "$f"
done
$CHECK3_CLEAN && pass "All MATCH blocks have LIMIT or aggregates"

# ============================================================
# CHECK 4: IN x.topics without coalesce null guard
# Severity: WARN
# ============================================================
echo -e "  ${DIM}[4/8] Missing coalesce on collection access...${NC}"
CHECK4_CLEAN=true
for f in ${MD_FILES[@]+"${MD_FILES[@]}"}; do
  fname=$(basename "$f")
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if echo "$line" | grep -qE 'IN [a-z]+\.(topics|tags)'; then
      if ! echo "$line" | grep -q 'coalesce'; then
        warn "IN x.topics without coalesce guard" "$fname:$lineno — use coalesce(x.topics, [])"
        CHECK4_CLEAN=false
      fi
    fi
  done < "$f"
done
$CHECK4_CLEAN && pass "All collection access has coalesce guard"

# ============================================================
# CHECK 5: Hardcoded year-specific fallback dates
# Severity: WARN
# ============================================================
echo -e "  ${DIM}[5/8] Hardcoded year-specific dates...${NC}"
CHECK5_CLEAN=true
for f in "${FILES[@]}"; do
  fname=$(basename "$f")
  lineno=0
  in_frontmatter=false
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # Skip YAML frontmatter
    if [ $lineno -eq 1 ] && echo "$line" | grep -q '^---$'; then
      in_frontmatter=true
      continue
    fi
    if $in_frontmatter; then
      echo "$line" | grep -q '^---$' && in_frontmatter=false
      continue
    fi
    # Skip comments and example sections
    if echo "$line" | grep -qE '^\s*(#|//|<!--)'; then
      continue
    fi
    if echo "$line" | grep -qE '202[5-9]-[0-9]{2}-[0-9]{2}'; then
      # Allow in code examples, markdown examples, and date format patterns
      if ! echo "$line" | grep -qiE '(example|e\.g\.|YYYY-MM-DD|fallback|Joined:|Date.*:)'; then
        warn "Hardcoded date literal" "$fname:$lineno"
        CHECK5_CLEAN=false
      fi
    fi
  done < "$f"
done
$CHECK5_CLEAN && pass "No hardcoded year-specific dates"

# ============================================================
# CHECK 6: macOS-incompatible bash
# Severity: FAIL
# ============================================================
echo -e "  ${DIM}[6/8] macOS-compatible bash...${NC}"
CHECK6_CLEAN=true
for f in ${SH_FILES[@]+"${SH_FILES[@]}"}; do
  fname=$(basename "$f")
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # date +%N (nanoseconds) — not available on macOS date
    if echo "$line" | grep -qE 'date \+.*%[0-9]*N'; then
      if ! echo "$line" | grep -q 'gdate'; then
        fail "macOS-incompatible date +%N" "$fname:$lineno — use gdate or alternative"
        CHECK6_CLEAN=false
      fi
    fi
    # sed -i without '' (GNU vs BSD)
    if echo "$line" | grep -qE "sed -i [^']"; then
      fail "macOS-incompatible sed -i" "$fname:$lineno — use sed -i '' for BSD compatibility"
      CHECK6_CLEAN=false
    fi
  done < "$f"
done
if [ "$SH_COUNT" -eq 0 ]; then
  pass "macOS-compatible bash (no .sh files to check)"
else
  $CHECK6_CLEAN && pass "macOS-compatible bash"
fi

# ============================================================
# CHECK 7: Direct curl to Neo4j/Telegram
# Severity: FAIL
# ============================================================
echo -e "  ${DIM}[7/8] Direct API calls...${NC}"
CHECK7_CLEAN=true
for f in "${FILES[@]}"; do
  fname=$(basename "$f")
  # Skip the wrapper scripts themselves
  case "$fname" in
    graph.sh|notify.sh) continue ;;
  esac
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if echo "$line" | grep -qiE 'curl.*(neo4j|graph/query)'; then
      if ! echo "$line" | grep -q 'bin/graph.sh'; then
        fail "Direct curl to Neo4j" "$fname:$lineno — use bin/graph.sh"
        CHECK7_CLEAN=false
      fi
    fi
    if echo "$line" | grep -qiE 'curl.*(api\.telegram|sendMessage)'; then
      if ! echo "$line" | grep -q 'bin/notify.sh'; then
        fail "Direct curl to Telegram" "$fname:$lineno — use bin/notify.sh"
        CHECK7_CLEAN=false
      fi
    fi
  done < "$f"
done
$CHECK7_CLEAN && pass "No direct API calls (using bin/ wrappers)"

# ============================================================
# CHECK 8: source .env without set -a guard
# Severity: WARN
# ============================================================
echo -e "  ${DIM}[8/8] Safe .env sourcing...${NC}"
CHECK8_CLEAN=true
for f in ${SH_FILES[@]+"${SH_FILES[@]}"}; do
  fname=$(basename "$f")
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if echo "$line" | grep -qE 'source.*\.env'; then
      if ! echo "$line" | grep -q 'set -a'; then
        warn "source .env without set -a guard" "$fname:$lineno"
        CHECK8_CLEAN=false
      fi
    fi
  done < "$f"
done
if [ "$SH_COUNT" -eq 0 ]; then
  pass "Safe .env sourcing (no .sh files to check)"
else
  $CHECK8_CLEAN && pass "Safe .env sourcing"
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
  echo -e "${GREEN}  ✓ All checks passed${NC}"
elif [ $FAIL -eq 0 ]; then
  echo -e "${YELLOW}  ⚠ $PASS passed, $WARN warning(s)${NC}"
else
  echo -e "${RED}  ✗ $PASS passed, $FAIL failure(s), $WARN warning(s)${NC}"
fi

# JSON summary (always last line)
echo "{\"pass\":$PASS,\"fail\":$FAIL,\"warn\":$WARN}"

# Exit 1 if any FAILs
[ $FAIL -eq 0 ]
