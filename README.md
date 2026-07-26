# worktree-dispatch

Kick off a new feature or bugfix in its **own git worktree + Claude session** —
without leaving your control session — then sweep the PRs those sessions produce
from the same place. Run it from the session you use for
review/merge, which must be inside **tmux**. It creates the worktree off your
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
| `spawn.sh <kind> <desc>`  | Create worktree off your current branch (or `WT_BASE`), split a pane, launch Claude. Prints `TARGET BRANCH DIR BASE`. |
| `sessions.sh [branch]`    | List dispatched worktrees as `BRANCH DIR TARGET CMD` — the branch → pane join the sweep uses. |
| `peek.sh <target>`        | Read the other session's screen (local review).                    |
| `drive.sh <target> "…"`   | Type a line into the other session and press Enter.                |
| `teardown.sh <target> <dir>` | Exit Claude, close **only** that pane, `git worktree remove`.   |

`<target>` is a tmux pane address like `mysess:1.2`, printed by `spawn.sh` — or
re-derived any time with `sessions.sh`.

## Install

Unzip into one of:

- `~/.claude/skills/` — available in every repo (recommended for a solo dev)
- `<repo>/.claude/skills/` — checked into a specific repo

## Configuration

| Variable    | Default            | Meaning                                                    |
| ----------- | ------------------ | ---------------------------------------------------------- |
| `WT_BASE`   | *(current branch)* | Branch new worktrees are cut from.                         |
| `WT_SPLIT`  | `h`                | `h` = side-by-side (left\|right) panes, `v` = stacked/full-width. |
| `WT_LAYOUT` | *(unset)*          | If set (e.g. `tiled`), re-tile panes after each spawn.     |
| `WT_SWEEP_BASE`  | *(current branch)* | Base branch the sweep's `gh pr list` gate targets. Must match `INTEGRATION_BASE` in the repo's `review-policy.md`. |
| `WT_SWEEP_LABEL` | `ready-for-review` | Label the sweep gate filters on.                      |

Merge criteria live in the swept repo's `review-policy.md`, not in env vars — see
`references/review-policy.md` for the template and its knobs.

## Requirements & notes

- Control session must run **inside tmux**.
- Sweeping needs `gh` authenticated and a **`review-policy.md` in the repo you sweep**.
  No policy file → the sweep stops and asks for one instead of inventing criteria.
- **Remote control isn't handled here.** Put `"remoteControlAtStartup": true` in
  `~/.claude/settings.json` and every session — including spawned worktree sessions —
  starts with it enabled. The local `peek.sh` / `drive.sh` path works either way.
- Worktrees are created with `git worktree add` (not `claude --worktree`) so you get
  clean `feature/*` / `bugfix/*` branches off your chosen base. See SKILL.md for why.

## Changelog

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
