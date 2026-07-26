# worktree-dispatch

Kick off a new feature or bugfix in its **own git worktree + Claude session** —
without leaving your control session — then sweep the PRs those sessions produce
from the same place. Run it from the session you use for review/merge, ideally
inside **tmux**. It creates the worktree off your
current branch (`main`, `develop`, or whatever you're on — override with
`WT_BASE`), splits a new tmux **pane**, and launches Claude named by the branch.

```
dispatch ──▶ worktree session ──▶ PR
                  ▲                 │
   drive.sh fixes │                 ▼
                  └──── sweep ◀── /code-review
                         │
                merged ──┴──▶ teardown.sh (pane + worktree)
```

## Requirements

| Tool | Minimum | Why | Tested on |
| --- | --- | --- | --- |
| git | 2.17 | `git worktree add` (2.5) and `git worktree remove` (2.17) | 2.47.1 |
| Claude Code CLI | any | `claude` must be on `PATH` — the spawned pane launches it by name | 2.1.220 |
| tmux | 2.0 | holds the dispatched sessions. The **binary** is required; being *inside* tmux is not — outside, dispatch falls back to a detached session | 3.6a |
| gh | 2.0 | **sweep only** — `gh pr list --json` and friends; dispatch never calls it | 2.96.0 |

`scripts/preflight.sh` verifies all of these in place, so you don't have to check by hand.

## Install

The skill is one directory: `SKILL.md` plus the `scripts/` and `references/` next to it.
Claude finds it by dropping that directory into a skills folder — pick one:

**Personal — every repo on this machine** (recommended for a solo dev):

```bash
git clone https://github.com/changtimwu/worktree-dispatch.git \
  ~/.claude/skills/worktree-dispatch
```

**Personal, but you want to hack on it** — keep the clone wherever you keep code and
symlink it in. Claude follows the symlink, and your edits are live with no re-copy:

```bash
git clone https://github.com/changtimwu/worktree-dispatch.git ~/code/worktree-dispatch
ln -s ~/code/worktree-dispatch ~/.claude/skills/worktree-dispatch
```

**Per-repo — checked in for the whole team:**

```bash
git clone https://github.com/changtimwu/worktree-dispatch.git \
  <repo>/.claude/skills/worktree-dispatch
rm -rf <repo>/.claude/skills/worktree-dispatch/.git    # vendor it, don't nest a repo
git -C <repo> add .claude/skills/worktree-dispatch && git -C <repo> commit -m "Add worktree-dispatch skill"
```

> **Commit it if you install per-repo.** Worktrees only check out *tracked* files, so an
> uncommitted skill is invisible to every session this skill dispatches. A personal
> install under `~/.claude/` always applies and has no such catch.

Keep the directory intact — the skill calls its scripts by path relative to `SKILL.md`.
If you installed from a zip rather than a clone, restore the executable bits that git
tracks for you: `chmod +x scripts/*.sh`.

### Verify

```bash
ls ~/.claude/skills/worktree-dispatch/SKILL.md      # the file Claude reads
cd <the repo you want to work in>                   # preflight checks the CURRENT repo
~/.claude/skills/worktree-dispatch/scripts/preflight.sh
```

Then start a **new** Claude session inside tmux and say *"spin up a feature session for a
dark mode toggle"* — if it runs `spawn.sh` and hands you back a tmux target, you're wired
up. Skills are read at session start, so an already-running session won't see a fresh
install.

### Optional setup

- **`/feature`, `/bugfix`, `/pr-sweep` shortcuts** — three one-line wrapper files;
  see [below](#optional-feature-bugfix-pr-sweep-shortcuts).
- **Sweeping a repo** — copy `references/review-policy.md` to that repo's root and tune
  its knobs. The sweep refuses to run without it.
- **Phone/web access to dispatched sessions** — set `"remoteControlAtStartup": true` in
  `~/.claude/settings.json`; this skill deliberately doesn't manage that.

### Update / remove

```bash
git -C ~/.claude/skills/worktree-dispatch pull     # update
rm -rf ~/.claude/skills/worktree-dispatch          # remove (or unlink, if symlinked)
```

Removing the skill leaves your worktrees, branches, and tmux sessions untouched — clean
those up with `scripts/teardown.sh` first if you want them gone.

## First run

Repos differ, and the ways they're *not* ready for this skill are mostly silent. Check
before you start:

```console
$ scripts/preflight.sh          # dispatch | sweep | all (default)
CHECK=git-repo   STATUS=ok   DETAIL=/Users/you/code/myrepo
CHECK=tmux       STATUS=ok   DETAIL=inside tmux session 'work' — the worktree opens as a split of this window
CHECK=base       STATUS=ok   DETAIL=worktrees will be cut from 'main'
CHECK=claude-cli STATUS=ok   DETAIL=/Users/you/.local/bin/claude
...
CHECK=review-policy STATUS=fail DETAIL=no review-policy.md in /Users/you/code/myrepo — the sweep will not
                                       invent merge criteria; copy references/review-policy.md and tune its knobs
CHECK=sweep-label   STATUS=fail DETAIL=this repo has no 'ready-for-review' label, so the gate returns [] no
                                       matter what (3 open non-draft PRs target 'main') — fix: gh label create
                                       ready-for-review, or set REQUIRE_LABEL=false in review-policy.md
CHECK=ci            STATUS=warn DETAIL=no GitHub Actions workflows found and ALLOW_NO_CI=false — no PR can
                                       ever satisfy the merge criteria; set ALLOW_NO_CI=true if that's intended
```

Every `DETAIL` ends in its own fix. `fail` blocks that mode, `warn` is something you
should know but doesn't stop anything. Dispatch works on a bare repo out of the box;
the sweep is what needs setting up, and the skill walks you through it once per repo.

## Usage

**Just ask for it in plain English — no setup, no slash command.** From your
control session (inside tmux), say what you want to work on:

```
spin up a bugfix session for the login timeout
start a feature to add a dark mode toggle
new worktree to refactor the auth module
```

Claude recognizes the intent, picks the branch name (`bugfix/*` or `feature/*`),
cuts the worktree, splits a pane, and launches Claude there. This works out of the
box — the phrasing doesn't have to be exact.

When those sessions have PRs up, sweep them from the same control session:

```
sweep the PRs
anything ready to merge?
```

### Optional: `/feature`, `/bugfix`, `/pr-sweep` shortcuts

> ⚠️ **These commands do not exist until you create them.** Typing `/feature` or
> `/bugfix` before setting them up will do nothing — use the plain-English way
> above, or add these one-line wrappers first.

If you want a shorter trigger, drop three tiny wrapper files into `.claude/commands/`
(full instructions in `references/slash-command.md`). Once created:

| Command             | What it does                                                                  |
| ------------------- | ----------------------------------------------------------------------------- |
| `/feature <desc>`   | Dispatch a new session on branch `feature/<slug>`, cut from your base branch. |
| `/bugfix <desc>`    | Dispatch a new session on branch `bugfix/<slug>`, cut from your base branch.  |
| `/pr-sweep`         | One triage pass over the open PRs: `/code-review` each, decide per `review-policy.md`. |

Example: `/feature add dark mode toggle` → branch `feature/add-dark-mode`, new pane,
Claude launched there.

> The commands are thin wrappers that just hand the request to this skill — the same
> thing the plain-English trigger does. All the real logic (naming, worktree, tmux,
> sweep rules) stays in one place.

## The sweep

`/pr-sweep` (or just "sweep the PRs") is the other half of the loop. Per PR it:

1. **Delegates the review** to `/code-review <n> --comment` — never hand-reviews the diff.
2. **Delegates the decision** to the swept repo's own `review-policy.md` — merge,
   request-changes, or comment-and-skip. Copy `references/review-policy.md` into the
   repo and tune its knobs; without that file the sweep stops instead of guessing.
3. **Routes the outcome back to the worktree.** Requested changes get driven into the
   live session that owns the branch (`drive.sh`) rather than fixed in the control
   session; a merged PR reports the exact `teardown.sh` line for its pane + worktree.

The branch → worktree → pane join comes from `scripts/sessions.sh`, so the sweep works
even after you've forgotten what `spawn.sh` printed. The gate defaults to PRs labelled
`ready-for-review` targeting **your current branch** — override with `WT_SWEEP_LABEL`
and `WT_SWEEP_BASE`.

The anti-gaming rules live in SKILL.md and are part of the deal: 🔴 Important findings
are never downgraded to clear a merge, pending CI is never "passed", and the policy file
is read as written, never edited to fit the PR.

## What happens under the hood

The skill runs the scripts in `scripts/`. You can also call them directly:

| Script                    | Purpose                                                            |
| ------------------------- | ------------------------------------------------------------------ |
| `preflight.sh [mode]`     | Read-only readiness check for `dispatch` / `sweep` / `all`. Every failure names its fix. |
| `spawn.sh <kind> <desc>`  | Create worktree off your current branch (or `WT_BASE`), split a pane, launch Claude. Prints `TARGET BRANCH DIR BASE MODE SESSION`. |
| `sessions.sh [branch]`    | List dispatched worktrees as `BRANCH DIR TARGET CMD ALIVE` — the branch → pane join the sweep uses. |
| `peek.sh <target>`        | Read the other session's screen (local review).                    |
| `drive.sh <target> "…"`   | Type a line into the other session and press Enter.                |
| `teardown.sh <target> <dir>` | Exit Claude, close **only** that pane, `git worktree remove`.   |

`<target>` is a tmux pane address like `mysess:1.2`, printed by `spawn.sh` — or
re-derived any time with `sessions.sh`.

## Configuration

| Variable    | Default            | Meaning                                                    |
| ----------- | ------------------ | ---------------------------------------------------------- |
| `WT_BASE`   | *(current branch)* | Branch new worktrees are cut from.                         |
| `WT_SPLIT`  | `h`                | `h` = side-by-side (left\|right) panes, `v` = stacked/full-width. |
| `WT_LAYOUT` | *(unset)*          | If set (e.g. `tiled`), re-tile panes after each spawn.     |
| `WT_SESSION`     | `wtd`              | Background tmux session used when you're not inside tmux. |
| `WT_NO_DETACH`   | *(unset)*          | Set to `1` to refuse dispatching outside tmux instead of falling back to a detached session. |
| `WT_SWEEP_BASE`  | *(current branch)* | Base branch the sweep's `gh pr list` gate targets. Must match `INTEGRATION_BASE` in the repo's `review-policy.md`. |
| `WT_SWEEP_LABEL` | `ready-for-review` | Label the sweep gate filters on.                      |

Merge criteria live in the swept repo's `review-policy.md`, not in env vars — see
`references/review-policy.md` for the template and its knobs.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Sweep says "nothing to do" but PRs are open | The repo has no `ready-for-review` label. `gh pr list --label <missing>` returns `[]` with exit 0 — identical to "nothing is ready". | `gh label create ready-for-review`, or set `REQUIRE_LABEL=false` in `review-policy.md` to sweep by base alone. `preflight.sh sweep` catches this. |
| Sweep never merges anything, only comments | No CI configured while `ALLOW_NO_CI=false` — the merge criteria can't be satisfied. | Set `ALLOW_NO_CI=true` in `review-policy.md` if the repo genuinely has no CI. |
| Sweep returns nothing on a feature branch | The gate defaults to your **current** branch, and no PRs target it. | `git switch main`, or `WT_SWEEP_BASE=main`. |
| `spawn.sh: not inside tmux` | tmux isn't installed, or `WT_NO_DETACH=1` is set. | `brew install tmux` — otherwise dispatch falls back to a detached session on its own. |
| Dispatched session ignores everything you send it | It's parked on Claude's *"Do you trust the files in this folder?"* dialog — new worktrees are new directories. | `drive.sh <target> "1"`, then `peek.sh <target>`. The skill does this automatically. |
| `sessions.sh` shows `TARGET=-` for a session you know is running | It matches panes by working directory; someone `cd`'d the pane out of the worktree root. | `cd` back, or address the pane by its tmux target directly. |
| Dispatched Claude session you can't see | `MODE=detached` — it went into a background tmux session. | `tmux attach -t wtd` (or `$WT_SESSION`). |

## Notes

- Run `scripts/preflight.sh` when something doesn't behave — it checks every mechanical
  assumption both modes make and names the fix for each failure.
- The control session should run **inside tmux**; if it doesn't, dispatch falls back to a
  detached session and everything except the side-by-side view keeps working.
- Sweeping needs `gh` authenticated and a **`review-policy.md` in the repo you sweep**.
  No policy file → the sweep stops and asks for one instead of inventing criteria.
- **Remote control isn't handled here.** Put `"remoteControlAtStartup": true` in
  `~/.claude/settings.json` and every session — including spawned worktree sessions —
  starts with it enabled. The local `peek.sh` / `drive.sh` path works either way.
- Worktrees are created with `git worktree add` (not `claude --worktree`) so you get
  clean `feature/*` / `bugfix/*` branches off your chosen base. See SKILL.md for why.

## Changelog

### 2026-07-26 (3)

- **New `scripts/preflight.sh`** — one read-only pass that checks everything both modes
  assume, printing `CHECK= STATUS= DETAIL=` lines where every failure names its own fix.
  Run it first; the skill now does.
- **A missing `ready-for-review` label is no longer invisible.** `gh pr list --label
  <missing>` returns `[]` with exit 0, so on any repo without that label the sweep
  reported "nothing to do" forever while PRs piled up. Preflight now verifies the label
  exists and reports how many PRs *would* be in scope, and the skill offers three fixes
  (create the label / `REQUIRE_LABEL=false` / abort), recording the answer in the repo's
  `review-policy.md` so it's asked once per repo.
- **Dispatch works outside tmux.** Instead of refusing, `spawn.sh` puts the worktree in a
  background session (`WT_SESSION`, default `wtd`) and reports `MODE=detached` plus the
  attach command. `peek`/`drive`/`teardown`/`sessions` are unaffected — tmux drives
  detached panes server-side. `WT_NO_DETACH=1` restores the hard failure; a missing tmux
  binary still is one.
- **The trust prompt is handled.** A new worktree is a directory Claude hasn't seen, so
  the spawned session parks on "Do you trust the files in this folder?" and silently
  swallows anything driven into it. The skill now peeks, answers it, and confirms the
  session reached its prompt — which doubles as proof that Claude actually launched.
- **`sessions.sh` gained `ALIVE=yes|no`.** The old advice ("`CMD=claude` means alive") was
  wrong: a running Claude reports its version as the command name (`CMD=2.1.220`). `ALIVE`
  is derived from the foreground command not being a shell — never drive text into
  `ALIVE=no`, where the shell would execute your prompt as a command.
- **`review-policy.md` gained a machine-readable knobs block** (now the authoritative
  copy, read by preflight) plus `REQUIRE_LABEL` / `SWEEP_LABEL` and a solo-repo starter
  note. Policy files without the block still work — preflight warns and uses defaults.
- **Real install instructions.** The old section said "unzip into one of" and listed two
  paths — no requirements, no verification, no update path. There are now version
  minimums, three install layouts (personal, symlinked-for-hacking, per-repo committed),
  a verify step, and the caveat that a per-repo install must be **committed** or the
  worktree sessions this skill spawns can't see it.

### 2026-07-26 (2)

- **The PR sweep is now part of this skill.** `/pr-sweep` used to be a standalone
  command that knew nothing about worktrees; it is now the skill's second mode, wired
  to the dispatch lifecycle. Requested changes are driven back into the live session
  that owns the branch instead of being fixed in the control session, and a merged PR
  reports the exact `teardown.sh` line for its pane + worktree.
- **New `scripts/sessions.sh`** — maps `branch → worktree dir → tmux target → running
  command`, matching panes by working directory (survives renames and re-layouts). It
  is the join the sweep needs, and it means you never have to remember what `spawn.sh`
  printed.
- **New `references/review-policy.md`** — template to copy into each repo you sweep.
  The sweep refuses to run without one rather than inventing merge criteria.
- **Sweep gate no longer hardcodes `--base develop`.** It defaults to the control
  session's current branch — the same default `spawn.sh` uses — so dispatch and sweep
  agree by construction. Override with `WT_SWEEP_BASE` / `WT_SWEEP_LABEL`.
- `/pr-sweep` becomes a thin wrapper like `/feature` and `/bugfix`, so the sweep's
  anti-gaming rules can't drift out of sync with a copy in a command file.

### 2026-07-26

- **Dropped the remote-control step and `scripts/enable_remote.sh`.** Claude Code can
  turn remote control on itself via `"remoteControlAtStartup": true` in
  `~/.claude/settings.json`, which covers spawned sessions too — so poking
  `/remote-control` into the new pane and screen-scraping for a ready prompt was
  redundant (and version-fragile). The skill now stops after launching Claude in the
  new pane.

### 2026-07-21

- **README now leads with the natural-language trigger.** The old layout opened with
  a "Slash commands" table, so first-time users typed `/feature` / `/bugfix` before
  those wrappers existed and nothing happened. The plain-English way is now shown
  first, and the slash commands are clearly marked as optional shortcuts you must
  create yourself.
- **`WT_BASE` now defaults to your current branch** (was hardcoded `develop`).
  Worktrees are cut from whatever branch the control session is on — `main`,
  `develop`, a release branch, anything. Override with `WT_BASE` or a 3rd arg as
  before. `spawn.sh` also refuses in detached HEAD (no branch to default to) and now
  echoes the resolved base to stderr and appends `BASE=<base>` to its stdout line.
- **`WT_SPLIT` now defaults to `h` — side-by-side (left|right) panes** (was `v`,
  stacked/full-width). Set `WT_SPLIT=v` for the old stacked layout.
- **`enable_remote.sh` readiness detection fixed.** It only matched the old
  `? for shortcuts` hint; newer CLIs (2.1.x) show `← for agents` / `auto mode on|off`,
  so it never matched and always waited the full timeout. It now recognizes any of
  these and proceeds as soon as the session is idle-ready.
