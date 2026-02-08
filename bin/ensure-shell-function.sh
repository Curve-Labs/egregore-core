#!/bin/bash
# Ensure egregore shell aliases are installed.
# Called by session-start.sh — failures here must not block session start.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SCRIPT_DIR/egregore.json"

if [ ! -f "$CONFIG" ]; then exit 0; fi

# Derive alias suffix from org slug
SLUG=$(jq -r '.github_org // empty' "$CONFIG" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '-' | tr -d ' ')
if [ -z "$SLUG" ]; then exit 0; fi

# Find shell profile
PROFILE=""
for p in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  if [ -f "$p" ]; then
    PROFILE="$p"
    break
  fi
done
if [ -z "$PROFILE" ]; then exit 0; fi

ALIAS_CMD="cd \"$SCRIPT_DIR\" && claude start"

# Clean up old function if we installed one previously
if grep -q '^egregore()' "$PROFILE" 2>/dev/null; then
  sed '/^egregore()/,/^}/d' "$PROFILE" > "$PROFILE.tmp" && mv "$PROFILE.tmp" "$PROFILE"
fi
if grep -q '^# Egregore$' "$PROFILE" 2>/dev/null; then
  sed '/^# Egregore$/d' "$PROFILE" > "$PROFILE.tmp" && mv "$PROFILE.tmp" "$PROFILE"
fi

# Check if egregore-{slug} already exists but points elsewhere (slug collision)
ALIAS_NAME="egregore-${SLUG}"
EXISTING=$(grep "^alias egregore-${SLUG}=" "$PROFILE" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  # Check if it already points to this directory
  if echo "$EXISTING" | grep -q "$SCRIPT_DIR"; then
    # Already registered correctly, nothing to do for named alias
    :
  else
    # Collision — another instance uses this slug. Use directory basename instead.
    DIR_NAME=$(basename "$SCRIPT_DIR")
    ALIAS_NAME="$DIR_NAME"
  fi
fi

# Ensure this instance has a named alias
if ! grep -q "^alias ${ALIAS_NAME}=" "$PROFILE" 2>/dev/null; then
  echo "" >> "$PROFILE"
  echo "alias ${ALIAS_NAME}='${ALIAS_CMD}'" >> "$PROFILE"
fi

# If no generic 'egregore' alias exists, also set that as default
if ! grep -q "^alias egregore=" "$PROFILE" 2>/dev/null; then
  echo "alias egregore='${ALIAS_CMD}'" >> "$PROFILE"
fi
