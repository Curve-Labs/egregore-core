#!/bin/bash
# Worktree lifecycle management for Egregore sessions.
# Each session gets an isolated worktree so parallel sessions don't conflict.
#
# Usage:
#   bash bin/worktree.sh setup <worktree-path> <main-project-dir>
#   bash bin/worktree.sh cleanup <worktree-path>
#   bash bin/worktree.sh cleanup-orphans <main-project-dir>
#   bash bin/worktree.sh list

set -o pipefail

CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in

  setup)
    # Setup symlinks so worktree shares state with main project
    # Args: <worktree-path> <main-project-dir>
    WT_PATH="${1:?Usage: worktree.sh setup <worktree-path> <main-project-dir>}"
    MAIN_DIR="${2:?Usage: worktree.sh setup <worktree-path> <main-project-dir>}"

    # Resolve main project's memory symlink target (absolute path)
    if [ -L "$MAIN_DIR/memory" ]; then
      MEMORY_TARGET=$(realpath "$MAIN_DIR/memory" 2>/dev/null)
      if [ -n "$MEMORY_TARGET" ] && [ -d "$MEMORY_TARGET" ]; then
        ln -sfn "$MEMORY_TARGET" "$WT_PATH/memory"
      fi
    fi

    # Symlink .env
    if [ -f "$MAIN_DIR/.env" ]; then
      ln -sfn "$MAIN_DIR/.env" "$WT_PATH/.env"
    fi

    # Symlink .egregore-state.json
    if [ -f "$MAIN_DIR/.egregore-state.json" ]; then
      ln -sfn "$MAIN_DIR/.egregore-state.json" "$WT_PATH/.egregore-state.json"
    fi

    # Symlink .egregore-session-id
    if [ -f "$MAIN_DIR/.egregore-session-id" ]; then
      ln -sfn "$MAIN_DIR/.egregore-session-id" "$WT_PATH/.egregore-session-id"
    fi

    # Symlink egregore.json (needed by bin/ scripts)
    if [ -f "$MAIN_DIR/egregore.json" ] && [ ! -f "$WT_PATH/egregore.json" ]; then
      ln -sfn "$MAIN_DIR/egregore.json" "$WT_PATH/egregore.json"
    fi

    # Walk up process tree to find:
    #   1. Claude Code PID (long-lived) for orphan detection
    #   2. Terminal TTY (unique per tab) for statusline matching
    #
    # BUG FIX: $$ is this script's PID — dies immediately when setup
    # finishes. cleanup-orphans then sees it as dead and deletes the
    # worktree from under a live session. We need the Claude Code
    # process PID (node), which lives as long as the session does.
    _pid=$$
    _cc_pid=""
    _tty=""
    while [ "$_pid" -gt 1 ] 2>/dev/null; do
      # Check if this ancestor is Claude Code (node process)
      if [ -z "$_cc_pid" ]; then
        _cmd=$(ps -o comm= -p "$_pid" 2>/dev/null | tr -d ' ')
        case "$_cmd" in
          node|claude) _cc_pid="$_pid" ;;
        esac
      fi
      # Find first ancestor with a real TTY
      if [ -z "$_tty" ]; then
        _ptty=$(ps -o tty= -p "$_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$_ptty" ] && [ "$_ptty" != "??" ]; then
          _tty="$_ptty"
        fi
      fi
      # Stop if we have both
      [ -n "$_cc_pid" ] && [ -n "$_tty" ] && break
      _pid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
    done

    # Write PID marker for orphan detection (Claude Code PID, not script PID)
    echo "${_cc_pid:-$$}" > "$WT_PATH/.egregore-worktree-pid"

    # Write TTY marker so statusline can match session → worktree
    [ -n "$_tty" ] && echo "$_tty" > "$WT_PATH/.egregore-worktree-tty"

    echo "Worktree setup complete: $WT_PATH"
    ;;

  cleanup)
    # Remove a worktree
    # Args: <worktree-path>
    WT_PATH="${1:?Usage: worktree.sh cleanup <worktree-path>}"

    # Remove from instance registry if accidentally registered
    REGISTRY="$HOME/.egregore/instances.json"
    if [ -f "$REGISTRY" ]; then
      RESOLVED_WT=$(realpath "$WT_PATH" 2>/dev/null || echo "$WT_PATH")
      UPDATED=$(jq --arg p "$RESOLVED_WT" '[.[] | select(.path != $p)]' "$REGISTRY" 2>/dev/null)
      if [ -n "$UPDATED" ]; then
        echo "$UPDATED" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
      fi
    fi

    # Remove the worktree
    git worktree remove "$WT_PATH" --force 2>/dev/null || true
    git worktree prune 2>/dev/null || true

    echo "Worktree cleaned up: $WT_PATH"
    ;;

  cleanup-orphans)
    # Find and clean worktrees with dead PIDs
    # Args: <main-project-dir>
    MAIN_DIR="${1:?Usage: worktree.sh cleanup-orphans <main-project-dir>}"
    WT_BASE="$MAIN_DIR/.claude/worktrees"

    if [ ! -d "$WT_BASE" ]; then
      exit 0
    fi

    CLEANED=0
    for WT_DIR in "$WT_BASE"/*/; do
      [ -d "$WT_DIR" ] || continue
      PID_FILE="$WT_DIR/.egregore-worktree-pid"

      if [ -f "$PID_FILE" ]; then
        STORED_PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$STORED_PID" ] && ! kill -0 "$STORED_PID" 2>/dev/null; then
          # PID is dead — orphaned worktree
          bash "$0" cleanup "$WT_DIR" 2>/dev/null || true
          CLEANED=$((CLEANED + 1))
        fi
      else
        # No PID file — check if it's a stale worktree (no .git file = already broken)
        if [ ! -f "$WT_DIR/.git" ]; then
          rm -rf "$WT_DIR" 2>/dev/null || true
          CLEANED=$((CLEANED + 1))
        fi
      fi
    done

    # Also clean stale entries from instance registry
    REGISTRY="$HOME/.egregore/instances.json"
    if [ -f "$REGISTRY" ]; then
      jq --arg prefix "$WT_BASE" \
        '[.[] | select((.path | startswith($prefix)) | not)]' \
        "$REGISTRY" > "$REGISTRY.tmp" 2>/dev/null && mv "$REGISTRY.tmp" "$REGISTRY"
    fi

    # Prune git's worktree list
    git -C "$MAIN_DIR" worktree prune 2>/dev/null || true

    if [ "$CLEANED" -gt 0 ]; then
      echo "Cleaned $CLEANED orphaned worktree(s)"
    fi
    ;;

  list)
    git worktree list
    ;;

  *)
    echo "Usage: worktree.sh {setup|cleanup|cleanup-orphans|list}" >&2
    exit 1
    ;;
esac
