#!/usr/bin/env bash
# Tear down a finished worktree session: exit Claude, close the window, remove the worktree.
# Refuses if the worktree has uncommitted changes (no --force). Branch is KEPT unless asked.
# Usage: teardown.sh <session:window.pane> <worktree-dir> [--delete-branch <branch>]
set -euo pipefail
TARGET="${1:?usage: teardown.sh <session:window.pane> <worktree-dir> [--delete-branch <branch>]}"
WT_DIR="${2:?missing worktree dir}"
DEL_BRANCH=""
[ "${3:-}" = "--delete-branch" ] && DEL_BRANCH="${4:-}"

# Ask the session to exit cleanly, then close ONLY that pane (never the whole window —
# the control session lives in another pane of the same window).
tmux send-keys -t "$TARGET" "/exit" Enter 2>/dev/null || true
sleep 2
tmux kill-pane -t "$TARGET" 2>/dev/null || true

# Remove the worktree. No --force, so git refuses if there are uncommitted changes.
git worktree remove "$WT_DIR"
git worktree prune

# -d only deletes the branch if it has been merged (safe after the PR lands).
[ -n "$DEL_BRANCH" ] && git branch -d "$DEL_BRANCH"

echo "removed worktree: $WT_DIR${DEL_BRANCH:+ and branch $DEL_BRANCH}"
