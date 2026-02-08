#!/bin/bash
# Install egregore shell alias. Called by installers (not session-start).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SCRIPT_DIR/egregore.json"

if [ ! -f "$CONFIG" ]; then exit 0; fi

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
DIR_NAME="$(basename "$SCRIPT_DIR")"

# Already have an alias pointing to this directory? Done.
if grep -q "$SCRIPT_DIR" "$PROFILE" 2>/dev/null; then
  exit 0
fi

# Any egregore alias already exists? Use egregore-{dirname} instead.
if grep -q "alias.*egregore" "$PROFILE" 2>/dev/null; then
  ALIAS_NAME="egregore-${DIR_NAME}"
else
  ALIAS_NAME="egregore"
fi

echo "" >> "$PROFILE"
echo "alias ${ALIAS_NAME}='${ALIAS_CMD}'" >> "$PROFILE"
