#!/usr/bin/env bash
# Type a line into a worktree session (and press Enter) from the control session.
# Usage: drive.sh <session:window.pane> "<text to send>"
set -euo pipefail
TARGET="${1:?usage: drive.sh <session:window.pane> \"text\"}"; shift
TEXT="$*"
[ -n "$TEXT" ] || { echo "nothing to send" >&2; exit 1; }
tmux send-keys -t "$TARGET" "$TEXT" Enter
