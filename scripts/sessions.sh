#!/usr/bin/env bash
# Map dispatched worktrees to their live tmux panes: branch -> dir -> target.
# This is the join the PR sweep needs — a PR's head branch tells you which pane
# (if any) is still working on it, so findings can be driven back to that session
# instead of hand-fixed in the control session.
#
# Usage: sessions.sh [branch]
#   (no args)  list every linked worktree of this repo (the main checkout is skipped)
#   <branch>   only that branch; exits 1 if this repo has no worktree for it
#
# Prints one line per worktree, everything else -> stderr:
#   BRANCH=<b> DIR=<dir> TARGET=<session:window.pane|-> CMD=<foreground-cmd|-> ALIVE=<yes|no>
#
# TARGET is '-' when no pane is sitting in that worktree — the session was torn
# down, or was never dispatched from here.
#
# ALIVE=no means the pane is sitting at a shell prompt, i.e. Claude exited. Never drive
# text into one of those: the shell would execute the prompt as a command. ALIVE is
# derived from CMD not being a shell — note that a running Claude reports its version
# as the command name (CMD=2.1.220), not 'claude'. It cannot tell Claude apart from any
# other foreground program, so peek.sh first when it matters.
set -euo pipefail

WANT="${1:-}"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "sessions.sh: not inside a git repository" >&2; exit 1; }

# Canonicalize so /var vs /private/var (macOS) and symlinked paths still compare equal.
canon() { [ -d "$1" ] && (cd "$1" && pwd -P) || printf '%s' "$1"; }

# The main checkout is the parent of the common git dir; every other entry is a worktree.
MAIN="$(canon "$(dirname "$(canon "$(git rev-parse --git-common-dir)")")")"

# Snapshot the panes once: "<target>\t<cwd>\t<foreground command>".
PANES="$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{pane_current_path}	#{pane_current_command}' 2>/dev/null || true)"

# Which pane is sitting in this worktree? Match on cwd — spawn.sh opens the pane
# with -c "$WT_DIR" and Claude stays there, so this survives pane renames and
# re-layouts (pane titles do not).
pane_for() {
  local dir="$1" target="-" cmd="-" t p c
  while IFS=$'\t' read -r t p c; do
    [ -n "${t:-}" ] || continue
    if [ "$(canon "$p")" = "$dir" ]; then target="$t"; cmd="$c"; break; fi
  done <<< "$PANES"
  printf '%s\t%s' "$target" "$cmd"
}

found=""
dir="" branch=""

emit() {
  [ -n "$dir" ] || return 0
  [ "$dir" != "$MAIN" ] || return 0                       # skip the control checkout
  [ -z "$WANT" ] || [ "$branch" = "$WANT" ] || return 0
  IFS=$'\t' read -r target cmd <<< "$(pane_for "$dir")"
  # A shell in the foreground means Claude is gone; anything else is a running program.
  local alive=no
  case "$cmd" in
    -|sh|-sh|bash|-bash|zsh|-zsh|fish|-fish|dash|ksh|tcsh|csh|login) alive=no ;;
    *) alive=yes ;;
  esac
  echo "BRANCH=${branch:--} DIR=${dir} TARGET=${target} CMD=${cmd} ALIVE=${alive}"
  found=1
}

# `git worktree list --porcelain` emits a blank-line-separated record per worktree:
#   worktree <path> / HEAD <sha> / branch refs/heads/<name> (or 'detached')
while IFS= read -r line; do
  case "$line" in
    "worktree "*) emit; dir="$(canon "${line#worktree }")"; branch="" ;;
    "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
    "detached") branch="-" ;;
  esac
done < <(git worktree list --porcelain)
emit   # flush the final record (no trailing blank line to trigger it)

if [ -z "$found" ]; then
  [ -n "$WANT" ] && { echo "sessions.sh: no worktree for branch '$WANT'" >&2; exit 1; }
  echo "sessions.sh: no dispatched worktrees" >&2
fi
