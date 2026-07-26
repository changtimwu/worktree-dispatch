#!/usr/bin/env bash
# Spawn an isolated git-worktree + Claude session in a NEW tmux window,
# launched FROM the control session, which is itself inside tmux.
#
# Usage: spawn.sh <feature|bugfix> <description-or-slug> [base-branch]
#   base-branch defaults to $WT_BASE, then to the control session's CURRENT branch.
#   (No branch name is assumed — cut from wherever you are: main, develop, etc.)
#
# On success prints ONE machine-readable line on stdout (everything else -> stderr):
#   TARGET=<session:window.pane> BRANCH=<branch> DIR=<worktree-path> BASE=<base-branch>
#     MODE=split|detached SESSION=<tmux session holding the new pane>
#
# MODE=split     the normal path: the worktree opens as a split of the control window.
# MODE=detached  the control session was not inside tmux, so the worktree went into a
#                background session instead — attach with 'tmux attach -t <SESSION>'.
#                Everything else (peek/drive/teardown/sessions) works identically.
set -euo pipefail

die() { echo "spawn.sh: $*" >&2; exit 1; }

KIND="${1:-}"; RAW="${2:-}"
# Base branch: explicit 3rd arg > $WT_BASE > the branch the control session is on now.
BASE="${3:-${WT_BASE:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)}}"
[ -n "$KIND" ] && [ -n "$RAW" ] || die "usage: spawn.sh <feature|bugfix> <description> [base]"
case "$KIND" in feature|bugfix) ;; *) die "kind must be 'feature' or 'bugfix' (got '$KIND')" ;; esac

# Decide WHERE the session will go before creating anything, so a bad environment costs
# nothing. Not being inside tmux is recoverable: tmux drives detached sessions just as
# well as attached ones, so dispatch into a background session rather than refusing.
SESSION="${WT_SESSION:-wtd}"
if [ -n "${TMUX:-}" ]; then
  MODE="split"
  SESSION="$(tmux display-message -p '#S')"
else
  command -v tmux >/dev/null 2>&1 || die "tmux is not installed — brew install tmux"
  [ -z "${WT_NO_DETACH:-}" ] || die "not inside tmux (and WT_NO_DETACH is set) — start one first: tmux new -s work"
  MODE="detached"
  echo "spawn.sh: not inside tmux — dispatching into detached session '${SESSION}'" >&2
fi

# Turn free text into a safe kebab-case slug (so 'Add dark mode!' -> 'add-dark-mode').
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
SLUG="$(slugify "$RAW")"
[ -n "$SLUG" ] || die "could not derive a slug from '$RAW'"

BRANCH="${KIND}/${SLUG}"   # e.g. feature/dark-mode  (kept exact, slash and all)
LABEL="${KIND}-${SLUG}"    # e.g. feature-dark-mode  (tmux window + dir name, no slash)

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
# Detached HEAD gives no branch name to default to — ask for a base explicitly.
[ -n "$BASE" ] && [ "$BASE" != "HEAD" ] || die "no base branch — control session is in detached HEAD; set WT_BASE or pass a 3rd arg"
REPO_NAME="$(basename "$REPO_ROOT")"
WT_PARENT="$(dirname "$REPO_ROOT")/${REPO_NAME}-worktrees"
WT_DIR="${WT_PARENT}/${LABEL}"

# Guards — never clobber existing work.
git show-ref --verify --quiet "refs/heads/${BRANCH}" && die "branch '${BRANCH}' already exists"
[ -e "$WT_DIR" ] && die "worktree dir already exists: $WT_DIR"
git rev-parse --verify --quiet "$BASE" >/dev/null || die "base branch '$BASE' not found (set WT_BASE or pass a 3rd arg)"
echo "spawn.sh: cutting '${BRANCH}' from base '${BASE}'" >&2

mkdir -p "$WT_PARENT"
# Create the worktree with the EXACT branch name, cut from the intended base.
git worktree add "$WT_DIR" -b "$BRANCH" "$BASE" >&2

FMT='#{session_name}:#{window_index}.#{pane_index}'
if [ "$MODE" = split ]; then
  # New tmux PANE in the CURRENT window, cwd = worktree dir; capture its id.
  # WT_SPLIT=h (default) puts panes side-by-side (left|right); v = stacked full-width.
  case "${WT_SPLIT:-h}" in v) SPLIT_FLAG="-v" ;; h|*) SPLIT_FLAG="-h" ;; esac
  TARGET="$(tmux split-window "$SPLIT_FLAG" -P -F "$FMT" -c "$WT_DIR")"
  # Optional: normalize the layout when WT_LAYOUT is set (e.g. tiled, even-vertical).
  [ -n "${WT_LAYOUT:-}" ] && tmux select-layout "${WT_LAYOUT}" 2>/dev/null || true
elif tmux has-session -t "=$SESSION" 2>/dev/null; then
  # Background session already exists — give this worktree its own window in it.
  TARGET="$(tmux new-window -t "=$SESSION" -P -F "$FMT" -c "$WT_DIR")"
else
  TARGET="$(tmux new-session -d -s "$SESSION" -P -F "$FMT" -c "$WT_DIR")"
fi
# Title the pane by branch so it's identifiable (harmless if pane titles aren't displayed).
tmux select-pane -t "$TARGET" -T "$LABEL" 2>/dev/null || true

# Launch a plain Claude in the worktree, session named by branch so it's identifiable.
tmux send-keys -t "$TARGET" "claude --name '${BRANCH}'" Enter

[ "$MODE" = split ] || echo "spawn.sh: attach with: tmux attach -t ${SESSION}" >&2

echo "TARGET=${TARGET} BRANCH=${BRANCH} DIR=${WT_DIR} BASE=${BASE} MODE=${MODE} SESSION=${SESSION}"
