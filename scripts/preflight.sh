#!/usr/bin/env bash
# Check whether this environment and repo are ready for the skill — before any work starts.
# Read-only: a doctor diagnoses, it never prescribes. Every failure names its own fix.
#
# Usage: preflight.sh [dispatch|sweep|all]     (default: all)
#
# Prints one line per check:
#   CHECK=<name> STATUS=ok|warn|fail DETAIL=<one line, ending in the fix when it's not ok>
#
# Exit 0 when nothing for the requested mode failed, 1 when something did. A 'warn' never
# fails the run — it is something the caller should say out loud, not something to fix.
#
# Runs against the CURRENT directory's repo (the one being dispatched from / swept), not
# against wherever this script happens to live.
set -uo pipefail   # deliberately not -e: every check must run, even after one fails

MODE="${1:-all}"
case "$MODE" in
  dispatch|sweep|all) ;;
  *) echo "usage: preflight.sh [dispatch|sweep|all]" >&2; exit 2 ;;
esac
want() { [ "$MODE" = all ] || [ "$MODE" = "$1" ]; }

FAILED=0
report() {  # report <name> <ok|warn|fail> <detail>
  [ "$2" != fail ] || FAILED=1
  echo "CHECK=$1 STATUS=$2 DETAIL=$3"
}

# ---------------------------------------------------------------- shared: is this a repo?

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  report git-repo fail "not inside a git repository — cd to the repo first"
  exit 1
fi
report git-repo ok "$REPO_ROOT"

CURRENT="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
HAS_COMMITS=""; git rev-parse --verify --quiet HEAD >/dev/null 2>&1 && HAS_COMMITS=1
# origin/HEAD only exists if the clone set it up; gh is the fallback (sweep mode only,
# since it costs a network round trip).
LOCAL_DEFAULT="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
LOCAL_DEFAULT="${LOCAL_DEFAULT#origin/}"

# ------------------------------------------------------------------------------- dispatch

if want dispatch; then
  if [ -n "${TMUX:-}" ]; then
    report tmux ok "inside tmux session '$(tmux display-message -p '#S' 2>/dev/null || echo '?')' — the worktree opens as a split of this window"
  elif command -v tmux >/dev/null 2>&1; then
    report tmux warn "not inside tmux — spawn.sh will dispatch into detached session '${WT_SESSION:-wtd}' instead (attach with: tmux attach -t ${WT_SESSION:-wtd}); set WT_NO_DETACH=1 to require tmux"
  else
    report tmux fail "tmux is not installed — brew install tmux"
  fi

  if [ -z "$HAS_COMMITS" ]; then
    report commits fail "repo has no commits yet — 'git worktree add -b' needs a base commit; make one first"
  else
    report commits ok "HEAD resolves"
  fi

  if [ -n "$CURRENT" ]; then
    report head ok "on branch '$CURRENT'"
  else
    report head fail "detached HEAD — no branch to cut from; git switch <branch>, or pass WT_BASE=<branch>"
  fi

  BASE="${WT_BASE:-$CURRENT}"
  if [ -z "$BASE" ]; then
    report base fail "no base branch resolvable — set WT_BASE=<branch>"
  elif ! git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
    report base fail "base branch '$BASE' does not exist here — set WT_BASE to a real branch"
  elif [ -n "$LOCAL_DEFAULT" ] && [ "$BASE" != "$LOCAL_DEFAULT" ]; then
    report base warn "worktrees will be cut from '$BASE', not the default branch '$LOCAL_DEFAULT' — intended? override with WT_BASE"
  else
    report base ok "worktrees will be cut from '$BASE'"
  fi

  if command -v claude >/dev/null 2>&1; then
    report claude-cli ok "$(command -v claude)"
  else
    report claude-cli warn "'claude' is not on PATH — the spawned pane will open but the launch command will fail; fix your PATH before dispatching"
  fi

  WT_PARENT="$(dirname "$REPO_ROOT")"
  if [ -w "$WT_PARENT" ]; then
    report worktree-parent ok "$WT_PARENT/$(basename "$REPO_ROOT")-worktrees"
  else
    report worktree-parent fail "cannot write to $WT_PARENT — worktrees are created in a sibling folder of the repo"
  fi
fi

# ---------------------------------------------------------------------------------- sweep

if want sweep; then
  GH_OK=""
  if ! command -v gh >/dev/null 2>&1; then
    report gh-cli fail "gh is not installed — brew install gh"
  else
    report gh-cli ok "$(command -v gh)"
    if gh auth status >/dev/null 2>&1; then
      report gh-auth ok "authenticated"
      GH_OK=1
    else
      report gh-auth fail "gh is not authenticated — gh auth login"
    fi
  fi

  if [ -z "$(git remote 2>/dev/null)" ]; then
    report remote fail "repo has no git remote — nothing to sweep; git remote add origin <url>"
  elif [ -n "$GH_OK" ] && ! gh repo view --json name >/dev/null 2>&1; then
    report remote fail "gh cannot resolve this repo from its remotes — check the remote points at GitHub"
  else
    report remote ok "$(git remote get-url origin 2>/dev/null || git remote | head -1)"
  fi

  # Knob defaults, overridden by the policy file's machine-readable block.
  INTEGRATION_BASE=""; SIZE_CAP=400; ALLOW_NO_CI=false
  REQUIRE_HUMAN_APPROVAL=false; REQUIRE_LABEL=true
  SWEEP_LABEL="ready-for-review"; TEARDOWN_ON_MERGE=false

  POLICY="$REPO_ROOT/review-policy.md"
  if [ ! -f "$POLICY" ]; then
    report review-policy fail "no review-policy.md in $REPO_ROOT — the sweep will not invent merge criteria; copy references/review-policy.md from this skill and tune its knobs"
  else
    report review-policy ok "$POLICY"
    # The fenced knobs block is the authoritative source: bare KNOB=value lines.
    KNOBS="$(grep -E '^[A-Z_]+=[^[:space:]]*$' "$POLICY" 2>/dev/null || true)"
    if [ -z "$KNOBS" ]; then
      report policy-knobs warn "review-policy.md has no machine-readable knobs block — using defaults (REQUIRE_LABEL=$REQUIRE_LABEL SWEEP_LABEL=$SWEEP_LABEL ALLOW_NO_CI=$ALLOW_NO_CI); add the block from references/review-policy.md"
    else
      while IFS='=' read -r k v; do
        case "$k" in
          INTEGRATION_BASE|SIZE_CAP|ALLOW_NO_CI|REQUIRE_HUMAN_APPROVAL|REQUIRE_LABEL|SWEEP_LABEL|TEARDOWN_ON_MERGE)
            printf -v "$k" '%s' "$v" ;;
        esac
      done <<< "$KNOBS"
      report policy-knobs ok "$(printf '%s' "$KNOBS" | tr '\n' ' ')"
    fi
  fi

  # The gate the sweep will actually run.
  BASE="${WT_SWEEP_BASE:-$CURRENT}"
  LABEL="${WT_SWEEP_LABEL:-$SWEEP_LABEL}"

  DEFAULT="$LOCAL_DEFAULT"
  [ -n "$DEFAULT" ] || [ -z "$GH_OK" ] || \
    DEFAULT="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"

  if [ -n "$INTEGRATION_BASE" ] && [ "$INTEGRATION_BASE" != "$BASE" ]; then
    report policy-base fail "gate base '$BASE' != INTEGRATION_BASE '$INTEGRATION_BASE' in review-policy.md — you would sweep the wrong queue; git switch $INTEGRATION_BASE or set WT_SWEEP_BASE=$INTEGRATION_BASE"
  elif [ -n "$INTEGRATION_BASE" ]; then
    report policy-base ok "gate base '$BASE' matches INTEGRATION_BASE"
  fi

  # How many PRs are actually out there — the number that makes an empty gate legible.
  OPEN_ON_BASE="?"
  if [ -n "$GH_OK" ] && [ -n "$BASE" ]; then
    OPEN_ON_BASE="$(gh pr list --base "$BASE" --json isDraft -q '[.[]|select(.isDraft==false)]|length' 2>/dev/null || echo '?')"
  fi

  if [ -z "$BASE" ]; then
    report sweep-base fail "no base to sweep — detached HEAD; set WT_SWEEP_BASE=<branch>"
  elif [ -n "$DEFAULT" ] && [ "$BASE" != "$DEFAULT" ]; then
    OPEN_ON_DEFAULT="?"
    [ -z "$GH_OK" ] || OPEN_ON_DEFAULT="$(gh pr list --base "$DEFAULT" --json isDraft -q '[.[]|select(.isDraft==false)]|length' 2>/dev/null || echo '?')"
    report sweep-base warn "gate targets '$BASE' ($OPEN_ON_BASE open non-draft PRs) but the repo default is '$DEFAULT' ($OPEN_ON_DEFAULT) — set WT_SWEEP_BASE=$DEFAULT if you meant that queue"
  else
    report sweep-base ok "gate targets '$BASE' ($OPEN_ON_BASE open non-draft PRs)"
  fi

  # The silent killer: 'gh pr list --label <missing>' returns [] with exit 0, which is
  # indistinguishable from 'nothing is ready'. Never let that pass as an empty worklist.
  if [ "$REQUIRE_LABEL" != true ]; then
    report sweep-label ok "REQUIRE_LABEL=false — gate is base-only, every non-draft PR on '$BASE' is in scope"
  elif [ -z "$GH_OK" ]; then
    report sweep-label warn "cannot verify the '$LABEL' label without gh — an empty gate may just mean the label does not exist"
  elif gh label list --json name -q '.[].name' 2>/dev/null | grep -qxF "$LABEL"; then
    report sweep-label ok "label '$LABEL' exists"
  else
    report sweep-label fail "this repo has no '$LABEL' label, so the gate returns [] no matter what ($OPEN_ON_BASE open non-draft PRs target '$BASE') — fix: gh label create $LABEL, or set REQUIRE_LABEL=false in review-policy.md to sweep by base alone"
  fi

  if ls "$REPO_ROOT"/.github/workflows/*.y*ml >/dev/null 2>&1; then
    report ci ok "GitHub Actions workflows present"
  elif [ "$ALLOW_NO_CI" = true ]; then
    report ci ok "no GitHub Actions workflows, but ALLOW_NO_CI=true — merges are allowed and must be flagged 'no CI configured'"
  else
    report ci warn "no GitHub Actions workflows found and ALLOW_NO_CI=false — no PR can ever satisfy the merge criteria; set ALLOW_NO_CI=true in review-policy.md if this repo genuinely has no CI"
  fi
fi

exit $FAILED
