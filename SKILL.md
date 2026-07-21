---
name: worktree-dispatch
description: >-
  Spawn an isolated git-worktree Claude session from your control ("develop")
  session and wire it for both local tmux driving and phone/web remote control.
  Use this whenever you are working in your develop/review session inside tmux
  and want to kick off a new feature or bugfix in its own worktree + Claude
  session — phrases like "start a feature to…", "spin up a bugfix session for…",
  "new worktree for…", "dispatch a session to work on…". It names the branch by
  convention (feature/* or bugfix/*), cuts the worktree from develop, opens a new
  tmux window in the current session, launches Claude named by the branch, and
  enables /remote-control. Trigger it even when the word "worktree" isn't said —
  any request to start parallel work in a fresh session from the control session
  should use this skill.
---

# worktree-dispatch

Kick off a new feature/bugfix in an isolated worktree + Claude session **from the
control session**, without dropping to a shell yourself. This skill runs from the
session sitting on `develop` (the one you use for review/merge), which must be
running **inside tmux**.

## What it does, in order

1. Classify the request as **feature** or **bugfix** and derive a kebab-case slug
   from the description. Branch name follows your convention:
   `feature/<slug>` or `bugfix/<slug>`.
2. Create the worktree with `git worktree add`, cut from **`develop`** (override
   with the `WT_BASE` env var or a 3rd arg), in a sibling folder
   `../<repo>-worktrees/<label>`.
3. Open a **new tmux pane in the current window** (a split of your control session —
   not a detached `--tmux` session), cwd set to the worktree. Split is stacked/
   full-width by default; set `WT_SPLIT=h` for side-by-side.
4. Launch `claude --name '<branch>'` in that window so the session — and its
   remote-control entry — is identifiable by branch.
5. Enable **`/remote-control`** in the new session once it has booted, then report
   the pairing output.
6. Hand back the tmux **target** (`session:window.pane`) so you can peek at / drive
   the session locally for the rest of its life.

## Why not just `claude --worktree`?

As of mid-2026, `claude --worktree <name>` (a) prepends `worktree-` to the branch,
(b) bases it off the **remote default** branch rather than your `develop`, and
(c) places the tree under `.claude/worktrees/`, which has been reported to break
skill and slash-command discovery in the spawned session. Because you want clean
`feature/*` and `bugfix/*` branches cut from `develop`, this skill creates the
worktree explicitly and launches a plain `claude` inside it. If Claude Code later
fixes the `--worktree` naming/base behavior, you can simplify step 2.

## Running it

All scripts live in `scripts/` next to this file. Refer to them by their absolute
path when you run them.

**Step 1–4 — spawn.** Pick `feature` or `bugfix`, pass the user's description
(free text is fine; it gets slugified):

```bash
scripts/spawn.sh feature "Add dark mode toggle"
# or override the base branch:
WT_BASE=develop scripts/spawn.sh bugfix "login times out after idle"
```

`spawn.sh` prints exactly one line on stdout — capture it:

```
TARGET=mysess:1.2 BRANCH=feature/add-dark-mode DIR=/path/repo-worktrees/feature-add-dark-mode
```

Parse `TARGET`, `BRANCH`, and `DIR` from that line and remember them for this
session. If a branch or worktree dir already exists, `spawn.sh` refuses rather than
clobbering — report the error to the user and stop.

**Step 5 — enable remote control.** Pass the `TARGET` from step 1:

```bash
scripts/enable_remote.sh mysess:1.2
```

It waits for the new Claude to finish booting (detects the idle input prompt), sends
`/remote-control`, then prints the pane so you can relay the pairing URL to the user.
Remote control is **off by default and gated to Pro/Max/Team/Enterprise on CLI
v2.1.51+**. If the pane shows "not available", tell the user that remote control
isn't enabled for their workspace — the **local tmux path (below) still works fully**.

**Step 6 — report.** Tell the user, concisely: the branch, the worktree dir, the
tmux target, and how they'll interact (see below). Do NOT keep the turn open waiting
— they'll come back when there's a PR to review.

## Interacting with the spawned session afterward

From the control session you drive the worktree session over plain tmux — this
always works regardless of remote-control availability:

```bash
scripts/peek.sh  mysess:1.2        # capture the other session's screen (last 40 lines)
scripts/drive.sh mysess:1.2 "run the tests and put up a PR when green"
```

`peek.sh` is how you "review" without switching windows; `drive.sh` types a line and
presses Enter in the target session. The remote-control bridge (if enabled) is the
same session viewed from your phone or the web — use whichever is convenient.

## Cleanup (optional)

After the PR merges, tear the session down from the control session:

```bash
scripts/teardown.sh mysess:1.2 /path/repo-worktrees/feature-add-dark-mode
# also delete the (merged) branch:
scripts/teardown.sh mysess:1.2 /path/.../feature-add-dark-mode --delete-branch feature/add-dark-mode
```

`teardown.sh` exits Claude, closes only its pane, and runs `git worktree remove`
**without `--force`**, so git refuses if there are uncommitted changes — safe by
design. Branch deletion uses `git branch -d`, which only removes it if already merged.

## Optional: bind to slash commands

If you'd rather type `/feature …` and `/bugfix …`, see `references/slash-command.md`
for two one-line command files you can drop into `.claude/commands/`.

## Preconditions & assumptions

- The control session runs **inside tmux** (`spawn.sh` refuses otherwise).
- You're inside a git repo whose integration branch is **`develop`** (override with
  `WT_BASE`). If your repo's `develop` should be freshly synced first, run
  `git fetch && git switch develop && git pull` before dispatching.
- Any repo-local skills/commands you want the child session to have must be committed
  (worktrees only check out tracked files); user-level `~/.claude/` always applies.
