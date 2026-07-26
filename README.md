# worktree-dispatch

Kick off a new feature or bugfix in its **own git worktree + Claude session** —
without leaving your control session. Run it from the session you use for
review/merge, which must be inside **tmux**. It creates the worktree off your
current branch (`main`, `develop`, or whatever you're on — override with
`WT_BASE`), splits a new tmux **pane**, and launches Claude named by the branch.

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

### Optional: `/feature` and `/bugfix` shortcuts

> ⚠️ **These commands do not exist until you create them.** Typing `/feature` or
> `/bugfix` before setting them up will do nothing — use the plain-English way
> above, or add these one-line wrappers first.

If you want a shorter trigger, drop two tiny wrapper files into `.claude/commands/`
(full instructions in `references/slash-command.md`). Once created:

| Command             | What it does                                                                  |
| ------------------- | ----------------------------------------------------------------------------- |
| `/feature <desc>`   | Dispatch a new session on branch `feature/<slug>`, cut from your base branch. |
| `/bugfix <desc>`    | Dispatch a new session on branch `bugfix/<slug>`, cut from your base branch.  |

Example: `/feature add dark mode toggle` → branch `feature/add-dark-mode`, new pane,
Claude launched there.

> The commands are thin wrappers that just hand the request to this skill — the same
> thing the plain-English trigger does. All the real logic (naming, worktree, tmux)
> stays in one place.

## What happens under the hood

The skill runs the scripts in `scripts/`. You can also call them directly:

| Script                    | Purpose                                                            |
| ------------------------- | ------------------------------------------------------------------ |
| `spawn.sh <kind> <desc>`  | Create worktree off your current branch (or `WT_BASE`), split a pane, launch Claude. Prints `TARGET BRANCH DIR BASE`. |
| `peek.sh <target>`        | Read the other session's screen (local review).                    |
| `drive.sh <target> "…"`   | Type a line into the other session and press Enter.                |
| `teardown.sh <target> <dir>` | Exit Claude, close **only** that pane, `git worktree remove`.   |

`<target>` is a tmux pane address like `mysess:1.2`, printed by `spawn.sh`.

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

## Requirements & notes

- Control session must run **inside tmux**.
- **Remote control isn't handled here.** Put `"remoteControlAtStartup": true` in
  `~/.claude/settings.json` and every session — including spawned worktree sessions —
  starts with it enabled. The local `peek.sh` / `drive.sh` path works either way.
- Worktrees are created with `git worktree add` (not `claude --worktree`) so you get
  clean `feature/*` / `bugfix/*` branches off your chosen base. See SKILL.md for why.

## Changelog

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
