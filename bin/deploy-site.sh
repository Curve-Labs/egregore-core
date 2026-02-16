#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SCRIPT_DIR/egregore.json"

if [ ! -f "$CONFIG" ]; then
  echo "Error: egregore.json not found. Run onboarding first." >&2
  exit 1
fi

# Read token from .env
if [ -f "$SCRIPT_DIR/.env" ]; then
  GITHUB_TOKEN=$(grep '^GITHUB_TOKEN=' "$SCRIPT_DIR/.env" | cut -d'=' -f2-)
else
  echo "Error: .env not found. Run onboarding first." >&2
  exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Error: GITHUB_TOKEN not set in .env" >&2
  exit 1
fi

# Config
SOURCE_REPO="Curve-Labs/egregore"
TARGET_REPO="Curve-Labs/egregore-site"
SOURCE_DIR="site 2"
SOURCE_BRANCH="main"
DRY_RUN=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-branch)
      SOURCE_BRANCH="$2"
      shift 2
      ;;
    --dry-run|dry)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: deploy-site.sh [--source-branch <branch>] [--dry-run|dry]" >&2
      exit 1
      ;;
  esac
done

WORK_DIR="/tmp/egregore-deploy"
SOURCE_PATH="$WORK_DIR/source"
TARGET_PATH="$WORK_DIR/target"

cleanup() {
  rm -rf "$WORK_DIR"
}

# Clone or pull source repo
echo "Fetching source: $SOURCE_REPO ($SOURCE_BRANCH)..." >&2
mkdir -p "$WORK_DIR"

if [ -d "$SOURCE_PATH/.git" ]; then
  git -C "$SOURCE_PATH" fetch origin "$SOURCE_BRANCH" --quiet
  git -C "$SOURCE_PATH" checkout "$SOURCE_BRANCH" --quiet
  git -C "$SOURCE_PATH" pull origin "$SOURCE_BRANCH" --quiet
else
  rm -rf "$SOURCE_PATH"
  git clone --quiet --branch "$SOURCE_BRANCH" --depth 1 \
    "https://$GITHUB_TOKEN@github.com/$SOURCE_REPO.git" "$SOURCE_PATH"
fi

# Verify source dir exists
if [ ! -d "$SOURCE_PATH/$SOURCE_DIR" ]; then
  echo "Error: '$SOURCE_DIR/' not found in $SOURCE_REPO" >&2
  cleanup
  exit 1
fi

# Clone or pull target repo
echo "Fetching target: $TARGET_REPO..." >&2

if [ -d "$TARGET_PATH/.git" ]; then
  git -C "$TARGET_PATH" fetch origin main --quiet
  git -C "$TARGET_PATH" checkout main --quiet
  git -C "$TARGET_PATH" pull origin main --quiet
else
  rm -rf "$TARGET_PATH"
  git clone --quiet --depth 1 \
    "https://$GITHUB_TOKEN@github.com/$TARGET_REPO.git" "$TARGET_PATH"
fi

# Sync site contents (preserve setup flow + auth files that live only in egregore-site)
echo "Syncing files..." >&2
rsync -a --delete \
  --exclude='.git' \
  --exclude='.git/' \
  --exclude='src/components/SetupFlow.jsx' \
  --exclude='src/api.js' \
  --exclude='src/auth.js' \
  --exclude='src/auth.test.js' \
  --exclude='src/test/' \
  "$SOURCE_PATH/$SOURCE_DIR/" "$TARGET_PATH/"

# Ensure setup flow routes exist in main.jsx
if ! grep -q 'SetupFlow' "$TARGET_PATH/src/main.jsx" 2>/dev/null; then
  echo "Injecting setup flow routes into main.jsx..." >&2
  # Add import
  sed -i.bak "s|^import DocsPage|import SetupFlow from './components/SetupFlow.jsx'\nimport DocsPage|" "$TARGET_PATH/src/main.jsx"
  # Add routes before closing </Routes>
  sed -i.bak "s|</Routes>|<Route path=\"/setup\" element={<SetupFlow />} />\n        <Route path=\"/callback\" element={<SetupFlow />} />\n        <Route path=\"/join\" element={<SetupFlow />} />\n      </Routes>|" "$TARGET_PATH/src/main.jsx"
  rm -f "$TARGET_PATH/src/main.jsx.bak"
fi

# Check for changes
cd "$TARGET_PATH"
if [ -z "$(git status --porcelain)" ]; then
  echo "RESULT:no_changes"
  cleanup
  exit 0
fi

# Show what changed
CHANGED=$(git status --porcelain | wc -l | tr -d ' ')
ADDED=$(git status --porcelain | grep -c '^?' || true)
MODIFIED=$(git status --porcelain | grep -c '^ M\|^M' || true)
DELETED=$(git status --porcelain | grep -c '^ D\|^D' || true)

echo "FILES_CHANGED:$CHANGED" >&2
echo "FILES_ADDED:$ADDED" >&2
echo "FILES_MODIFIED:$MODIFIED" >&2
echo "FILES_DELETED:$DELETED" >&2

if [ "$DRY_RUN" = true ]; then
  echo "" >&2
  echo "=== Dry run — changes that would be deployed ===" >&2
  git status --short >&2
  echo "" >&2
  git diff --stat >&2
  echo "RESULT:dry_run"
  cleanup
  exit 0
fi

# Commit and push
DEPLOY_DATE=$(date +%Y-%m-%d)
git add -A
git commit -m "Deploy site: $DEPLOY_DATE" --quiet
git push origin main --quiet

COMMIT_SHA=$(git rev-parse --short HEAD)
echo "RESULT:deployed:$COMMIT_SHA"

cleanup
exit 0
