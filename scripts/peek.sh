#!/usr/bin/env bash
# Peek at a worktree session's screen from the control session.
# Usage: peek.sh <session:window.pane> [lines]
set -euo pipefail
TARGET="${1:?usage: peek.sh <session:window.pane> [lines]}"; LINES="${2:-40}"
tmux capture-pane -t "$TARGET" -p | tail -n "$LINES"
