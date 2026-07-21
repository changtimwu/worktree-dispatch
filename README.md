# worktree-dispatch

Kick off a new feature or bugfix in its **own git worktree + Claude session** —
without leaving your control (`develop`) session. Run it from the session you use
for review/merge, which must be inside **tmux**. It creates the worktree off
`develop`, splits a new tmux **pane**, launches Claude named by the branch, and
enables `/remote-control` so you can also check in from your phone.

## Slash commands

This skill is triggered by natural language ("spin up a bugfix session for…"), so
no slash command is required. For a faster trigger, two optional one-line wrappers
are included — drop them into `.claude/commands/` (see
`references/slash-command.md`):

| Command             | What it does                                                            |
| ------------------- | ----------------------------------------------------------------------- |
| `/feature <desc>`   | Dispatch a new session on branch `feature/<slug>`, cut from `develop`.  |
| `/bugfix <desc>`    | Dispatch a new session on branch `bugfix/<slug>`, cut from `develop`.   |

Example: `/feature add dark mode toggle` → branch `feature/add-dark-mode`, new pane,
Claude launched there, remote control enabled.

> These commands are thin wrappers that just hand the request to this skill; all the
> real logic (naming, worktree, tmux, remote control) stays in one place.

## What happens under the hood

The skill runs the scripts in `scripts/`. You can also call them directly:

| Script                    | Purpose                                                            |
| ------------------------- | ------------------------------------------------------------------ |
| `spawn.sh <kind> <desc>`  | Create worktree off `develop`, split a pane, launch Claude. Prints `TARGET BRANCH DIR`. |
| `enable_remote.sh <target>` | Wait for the new session to boot, then enable `/remote-control`. |
| `peek.sh <target>`        | Read the other session's screen (local review, always works).      |
| `drive.sh <target> "…"`   | Type a line into the other session and press Enter.                |
| `teardown.sh <target> <dir>` | Exit Claude, close **only** that pane, `git worktree remove`.   |

`<target>` is a tmux pane address like `mysess:1.2`, printed by `spawn.sh`.

## Install

Unzip into one of:

- `~/.claude/skills/` — available in every repo (recommended for a solo dev)
- `<repo>/.claude/skills/` — checked into a specific repo

## Configuration

| Variable    | Default   | Meaning                                                    |
| ----------- | --------- | ---------------------------------------------------------- |
| `WT_BASE`   | `develop` | Branch new worktrees are cut from.                         |
| `WT_SPLIT`  | `v`       | `v` = stacked/full-width panes, `h` = side-by-side.        |
| `WT_LAYOUT` | *(unset)* | If set (e.g. `tiled`), re-tile panes after each spawn.     |

## Requirements & notes

- Control session must run **inside tmux**.
- `/remote-control` is **off by default** and gated to Pro/Max/Team/Enterprise on
  CLI v2.1.51+. If it's unavailable, the local `peek.sh` / `drive.sh` path still
  works fully.
- Worktrees are created with `git worktree add` (not `claude --worktree`) so you get
  clean `feature/*` / `bugfix/*` branches off `develop`. See SKILL.md for why.
