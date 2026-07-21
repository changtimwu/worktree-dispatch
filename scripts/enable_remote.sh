#!/usr/bin/env bash
# Enable /remote-control in an already-spawned worktree session, once it has booted.
# Usage: enable_remote.sh <session:window.pane> [timeout_seconds]
#
# Prints the tail of the pane afterwards so the caller can read the pairing URL /
# any "not available" message (remote control is off by default and plan/version gated).
set -euo pipefail

TARGET="${1:-}"; TIMEOUT="${2:-40}"
[ -n "$TARGET" ] || { echo "usage: enable_remote.sh <session:window.pane> [timeout]" >&2; exit 1; }

ready=""
for _ in $(seq 1 "$TIMEOUT"); do
  pane="$(tmux capture-pane -t "$TARGET" -p 2>/dev/null || true)"
  # Claude Code prints this hint near the input box once it is idle and ready for input.
  if printf '%s' "$pane" | grep -q "? for shortcuts"; then ready=1; break; fi
  sleep 1
done

[ -n "$ready" ] || echo "WARN: $TARGET didn't show a ready prompt within ${TIMEOUT}s; sending anyway" >&2

tmux send-keys -t "$TARGET" "/remote-control" Enter
sleep 3
echo "----- pane after enabling remote control ($TARGET) -----"
tmux capture-pane -t "$TARGET" -p 2>/dev/null | tail -n 25
