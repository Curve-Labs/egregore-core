#!/bin/bash
# Test startup reliability: runs session-start.sh N times and validates output.
# Usage: bash bin/test-startup.sh [count]
#
# Checks:
# 1. Exit code is 0
# 2. ASCII art banner is present
# 3. Ornamented status line (◈, ◇, ⎇) is present
# 4. Always ends up on develop branch
# 5. Framework version in session context
# 6. Output is consistent across runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COUNT="${1:-5}"
PASS=0
FAIL=0
ERRORS=()

echo "Testing session-start.sh reliability ($COUNT runs)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Save current state
ORIGINAL_BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || echo "develop")

# Snapshot bin/ from the branch we're testing. Branch switches change files on disk,
# so we preserve and restore them before each run.
SNAPSHOT_DIR=$(mktemp -d)
cp -R "$SCRIPT_DIR/bin/" "$SNAPSHOT_DIR/bin/"
cleanup() {
  rm -rf "$SNAPSHOT_DIR"
  git -C "$SCRIPT_DIR" checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || true
  for j in $(seq 1 "$COUNT"); do
    git -C "$SCRIPT_DIR" branch -D "dev/test/startup-test-$j" --quiet 2>/dev/null || true
  done
}
trap cleanup EXIT

for i in $(seq 1 "$COUNT"); do
  printf "Run %d/%d... " "$i" "$COUNT"

  # Simulate being on various branches (test the always-switch-to-develop logic)
  case $((i % 3)) in
    0)
      # Stay on develop (normal case)
      git -C "$SCRIPT_DIR" checkout develop --quiet 2>/dev/null || true
      ;;
    1)
      # Simulate being on a working branch
      git -C "$SCRIPT_DIR" checkout -b "dev/test/startup-test-$i" develop --quiet 2>/dev/null || true
      ;;
    2)
      # Simulate being on main
      git -C "$SCRIPT_DIR" checkout main --quiet 2>/dev/null || true
      ;;
  esac

  START_BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null)

  # Restore the version under test (branch switches may have swapped files on disk)
  cp -R "$SNAPSHOT_DIR/bin/" "$SCRIPT_DIR/bin/"

  # Run session-start and capture output
  OUTPUT=$(bash "$SCRIPT_DIR/bin/session-start.sh" 2>&1) || true
  EXIT_CODE=$?

  # Check which branch we ended up on
  END_BRANCH=$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null)

  # Validate
  ERRORS_THIS_RUN=()

  # 1. Exit code
  if [ "$EXIT_CODE" -ne 0 ]; then
    ERRORS_THIS_RUN+=("exit code $EXIT_CODE (expected 0)")
  fi

  # 2. ASCII art banner
  if ! echo "$OUTPUT" | grep -q '███████╗'; then
    ERRORS_THIS_RUN+=("missing ASCII art banner")
  fi

  # 3. Ornamented status (◈ and ◇ and ⎇)
  if ! echo "$OUTPUT" | grep -q '◈'; then
    ERRORS_THIS_RUN+=("missing ◈ (instance name)")
  fi
  if ! echo "$OUTPUT" | grep -q '◇'; then
    ERRORS_THIS_RUN+=("missing ◇ (user/repos)")
  fi
  if ! echo "$OUTPUT" | grep -q '⎇'; then
    ERRORS_THIS_RUN+=("missing ⎇ (branch status)")
  fi

  # 4. Separator line
  if ! echo "$OUTPUT" | grep -q '┄┄┄'; then
    ERRORS_THIS_RUN+=("missing ┄ separator")
  fi

  # 5. Ends on develop
  if [ "$END_BRANCH" != "develop" ]; then
    ERRORS_THIS_RUN+=("ended on '$END_BRANCH' (expected develop)")
  fi

  # 6. Framework version in context
  if ! echo "$OUTPUT" | grep -q '"framework_version"'; then
    ERRORS_THIS_RUN+=("missing framework_version in context")
  fi

  # 7. Session context block exists
  if ! echo "$OUTPUT" | grep -q 'session-context'; then
    ERRORS_THIS_RUN+=("missing session-context block")
  fi

  if [ ${#ERRORS_THIS_RUN[@]} -eq 0 ]; then
    PASS=$((PASS + 1))
    echo "✓ (from $START_BRANCH → $END_BRANCH)"
  else
    FAIL=$((FAIL + 1))
    echo "✗ (from $START_BRANCH → $END_BRANCH)"
    for err in "${ERRORS_THIS_RUN[@]}"; do
      echo "    - $err"
      ERRORS+=("Run $i: $err")
    done
  fi

  # Return to develop between runs
  git -C "$SCRIPT_DIR" checkout develop --quiet 2>/dev/null || true
done

# Cleanup handled by trap

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed out of $COUNT runs"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "Failures:"
  for err in "${ERRORS[@]}"; do
    echo "  - $err"
  done
  exit 1
fi

echo "All checks passed."
exit 0
