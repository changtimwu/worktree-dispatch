#!/usr/bin/env bash
# Spawn an isolated git-worktree + Claude session in a NEW tmux window,
# launched FROM the control ("develop") session, which is itself inside tmux.
#
# Usage: spawn.sh <feature|bugfix> <description-or-slug> [base-branch]
#   base-branch defaults to $WT_BASE, then to "develop".
#
# On success prints ONE machine-readable line on stdout (everything else -> stderr):
#   TARGET=<session:window.pane>  BRANCH=<branch>  DIR=<worktree-path>
set -euo pipefail

die() { echo "spawn.sh: $*" >&2; exit 1; }

KIND="${1:-}"; RAW="${2:-}"; BASE="${3:-${WT_BASE:-develop}}"
[ -n "$KIND" ] && [ -n "$RAW" ] || die "usage: spawn.sh <feature|bugfix> <description> [base]"
case "$KIND" in feature|bugfix) ;; *) die "kind must be 'feature' or 'bugfix' (got '$KIND')" ;; esac
[ -n "${TMUX:-}" ] || die "not inside tmux — start your control session inside tmux first"

# Turn free text into a safe kebab-case slug (so 'Add dark mode!' -> 'add-dark-mode').
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
SLUG="$(slugify "$RAW")"
[ -n "$SLUG" ] || die "could not derive a slug from '$RAW'"

BRANCH="${KIND}/${SLUG}"   # e.g. feature/dark-mode  (kept exact, slash and all)
LABEL="${KIND}-${SLUG}"    # e.g. feature-dark-mode  (tmux window + dir name, no slash)

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
REPO_NAME="$(basename "$REPO_ROOT")"
WT_PARENT="$(dirname "$REPO_ROOT")/${REPO_NAME}-worktrees"
WT_DIR="${WT_PARENT}/${LABEL}"

# Guards — never clobber existing work.
git show-ref --verify --quiet "refs/heads/${BRANCH}" && die "branch '${BRANCH}' already exists"
[ -e "$WT_DIR" ] && die "worktree dir already exists: $WT_DIR"
git rev-parse --verify --quiet "$BASE" >/dev/null || die "base branch '$BASE' not found (set WT_BASE or pass a 3rd arg)"

mkdir -p "$WT_PARENT"
# Create the worktree with the EXACT branch name, cut from the intended base.
git worktree add "$WT_DIR" -b "$BRANCH" "$BASE" >&2

# New tmux PANE in the CURRENT window, cwd = worktree dir; capture its id.
# WT_SPLIT=v (default) stacks panes full-width (better for the Claude TUI); h = side-by-side.
case "${WT_SPLIT:-v}" in h) SPLIT_FLAG="-h" ;; v|*) SPLIT_FLAG="-v" ;; esac
TARGET="$(tmux split-window "$SPLIT_FLAG" -P -F '#{session_name}:#{window_index}.#{pane_index}' -c "$WT_DIR")"
# Title the pane by branch so it's identifiable (harmless if pane titles aren't displayed).
tmux select-pane -t "$TARGET" -T "$LABEL" 2>/dev/null || true
# Optional: normalize the layout when WT_LAYOUT is set (e.g. tiled, even-vertical).
[ -n "${WT_LAYOUT:-}" ] && tmux select-layout "${WT_LAYOUT}" 2>/dev/null || true

# Launch a plain Claude in the worktree, session named by branch so remote control is identifiable.
tmux send-keys -t "$TARGET" "claude --name '${BRANCH}'" Enter

echo "TARGET=${TARGET} BRANCH=${BRANCH} DIR=${WT_DIR}"
