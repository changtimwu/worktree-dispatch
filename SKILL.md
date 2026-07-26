---
name: worktree-dispatch
description: >-
  Run the two halves of a control session: DISPATCH isolated git-worktree Claude
  sessions, and SWEEP the pull requests they produce.
  Use this whenever you are working in your control/review session inside tmux
  and want to (a) kick off a new feature or bugfix in its own worktree + Claude
  session — phrases like "start a feature to…", "spin up a bugfix session for…",
  "new worktree for…", "dispatch a session to work on…" — or (b) triage the open
  PRs those sessions put up — "sweep the PRs", "review the open PRs", "PR sweep",
  "anything ready to merge?". Dispatch names the branch by
  convention (feature/* or bugfix/*), cuts the worktree from your control
  session's current branch (main, develop, or whatever you're on — override with
  WT_BASE), opens a new tmux window in the current session, and launches Claude
  named by the branch. Sweep delegates review to /code-review, decides by the
  target repo's review-policy.md, and routes requested changes back to the live
  worktree session that owns the branch. Trigger it even when the word
  "worktree" isn't said — any request to start parallel work in a fresh session,
  or to triage the resulting PRs, should use this skill.
---

# worktree-dispatch

Kick off a new feature/bugfix in an isolated worktree + Claude session **from the
control session**, without dropping to a shell yourself — then sweep the PRs those
sessions produce from the same place. This skill runs from the
session you use for review/merge — whatever integration branch it sits on
(`main`, `develop`, a release branch, …) — which must be running **inside tmux**.

```
dispatch ──▶ worktree session ──▶ PR
                  ▲                 │
   drive.sh fixes │                 ▼
                  └──── sweep ◀── /code-review
                         │
                merged ──┴──▶ teardown.sh (pane + worktree)
```

**Two modes.** "Start a feature/bugfix…" → [Dispatch](#dispatch). "Sweep the PRs" →
[Sweeping the PRs](#sweeping-the-prs). They share one thing: `scripts/sessions.sh`,
which maps a branch to its worktree dir and live tmux pane.

Remote control is **not** this skill's job: set `"remoteControlAtStartup": true` in
`~/.claude/settings.json` and every session, including the spawned one, comes up with
it already on.

## Dispatch

### What it does, in order

1. Classify the request as **feature** or **bugfix** and derive a kebab-case slug
   from the description. Branch name follows your convention:
   `feature/<slug>` or `bugfix/<slug>`.
2. Create the worktree with `git worktree add`, cut from the control session's
   **current branch** by default (override with the `WT_BASE` env var or a 3rd
   arg), in a sibling folder `../<repo>-worktrees/<label>`.
3. Open a **new tmux pane in the current window** (a split of your control session —
   not a detached `--tmux` session), cwd set to the worktree. Split is side-by-side
   (left|right) by default; set `WT_SPLIT=v` for stacked/full-width.
4. Launch `claude --name '<branch>'` in that window so the session is identifiable
   by branch — locally and in any remote-control list.
5. Hand back the tmux **target** (`session:window.pane`) so you can peek at / drive
   the session locally for the rest of its life.

### Why not just `claude --worktree`?

As of mid-2026, `claude --worktree <name>` (a) prepends `worktree-` to the branch,
(b) always bases it off the **remote default** branch rather than the branch you're
actually on, and (c) places the tree under `.claude/worktrees/`, which has been
reported to break skill and slash-command discovery in the spawned session. Because
you want clean `feature/*` and `bugfix/*` branches cut from your chosen base, this
skill creates the worktree explicitly and launches a plain `claude` inside it. If
Claude Code later fixes the `--worktree` naming/base behavior, you can simplify
step 2.

### Running it

All scripts live in `scripts/` next to this file. Refer to them by their absolute
path when you run them.

**Steps 1–4 — spawn.** Pick `feature` or `bugfix`, pass the user's description
(free text is fine; it gets slugified):

```bash
scripts/spawn.sh feature "Add dark mode toggle"   # cuts from your current branch
# or override the base branch (env var or 3rd arg):
WT_BASE=main scripts/spawn.sh bugfix "login times out after idle"
scripts/spawn.sh bugfix "login times out after idle" release/2.0
```

`spawn.sh` prints exactly one line on stdout — capture it:

```
TARGET=mysess:1.2 BRANCH=feature/add-dark-mode DIR=/path/repo-worktrees/feature-add-dark-mode BASE=main
```

Parse `TARGET`, `BRANCH`, `DIR`, and `BASE` from that line and remember them for this
session. `BASE` tells you which branch it was actually cut from — worth relaying to
the user so there's no surprise. If a branch or worktree dir already exists, or the
control session is in detached HEAD with no base given, `spawn.sh` refuses rather
than clobbering — report the error to the user and stop.

**Step 5 — report.** Tell the user, concisely: the branch, the worktree dir, the
tmux target, and how they'll interact (see below). Do NOT keep the turn open waiting
— they'll come back when there's a PR to review.

### Interacting with the spawned session afterward

From the control session you drive the worktree session over plain tmux:

```bash
scripts/peek.sh  mysess:1.2        # capture the other session's screen (last 40 lines)
scripts/drive.sh mysess:1.2 "run the tests and put up a PR when green"
```

`peek.sh` is how you "review" without switching windows; `drive.sh` types a line and
presses Enter in the target session. If `remoteControlAtStartup` is on, the phone/web
view is the same session — use whichever is convenient.

Lost track of a target? `scripts/sessions.sh` re-derives it from git + tmux — no need
to remember what `spawn.sh` printed:

```bash
scripts/sessions.sh                      # every dispatched worktree
scripts/sessions.sh feature/add-dark-mode   # just this branch; exit 1 if none
# BRANCH=feature/add-dark-mode DIR=/path/repo-worktrees/feature-add-dark-mode TARGET=mysess:1.2 CMD=claude
```

`TARGET=-` means no pane is sitting in that worktree (session torn down, or never
dispatched from here). `CMD` tells you whether the session is still alive: `claude`
= running, `zsh`/`bash` = Claude exited but the pane is open.

## Sweeping the PRs

The other half of the control session: triage the PRs the dispatched sessions put up.
Review is **delegated to `/code-review`** and the merge decision is **delegated to the
target repo's `review-policy.md`** — the sweep itself only routes.

### Preflight (once per sweep, not per PR)

1. `gh auth status` must be authenticated, and the repo must have a remote.
2. The target repo needs a **`review-policy.md`** at its root. If it has none, stop and
   say so — offer `references/review-policy.md` from this skill as a starting template.
   Do not invent merge criteria, and do not fall back to "reasonable defaults".
3. Read that `review-policy.md` **as written**. Its knobs (`INTEGRATION_BASE`,
   `SIZE_CAP`, `ALLOW_NO_CI`, …) govern everything below.

### Gate command (run FIRST every pass; treat the output as the worklist)

```bash
BASE="${WT_SWEEP_BASE:-$(git rev-parse --abbrev-ref HEAD)}"   # default: the branch you're on
gh pr list --label "${WT_SWEEP_LABEL:-ready-for-review}" --base "$BASE" \
  --json number,title,isDraft,reviewDecision,statusCheckRollup,headRefName
```

The base defaults to the control session's **current branch** — the same branch
`spawn.sh` cuts from, so dispatch and sweep agree by construction. It must equal
`INTEGRATION_BASE` in `review-policy.md`; if they disagree, say so and stop rather than
sweeping the wrong queue. Act only on PRs this returns. Skip drafts. Process the delta
since the last pass.

Then join the worklist to the live sessions **once**:

```bash
scripts/sessions.sh          # BRANCH= DIR= TARGET= CMD= per dispatched worktree
```

Match each PR's `headRefName` against `BRANCH` to learn whether a session still owns it.

### Per PR

1. **REVIEW** (delegated — do not hand-review the diff yourself):

   ```
   /code-review <n> --comment
   ```

   Posts the engine's findings as inline comments on the PR **and** returns them here.
   Use the returned findings, with their severity (🔴 Important / 🟡 Nit / 🟣
   Pre-existing), as the review input for step 2.

2. **DECIDE** (apply `review-policy.md` exactly — the only judgment you make). Gather
   the decision inputs it asks for:

   ```bash
   gh pr checks <n>
   gh pr view <n> --json reviewDecision,files,additions,deletions,isDraft,headRefName
   ```

   Then follow the policy's precedence: merge / request-changes / comment-and-stop.

3. **ROUTE the outcome back to the worktree** — this is what the sweep adds over
   plain PR triage:

   - **Changes requested** and the branch has a live session (`TARGET` ≠ `-`, `CMD=claude`):
     after `gh pr review <n> --request-changes`, hand the work back to the session that
     owns the branch instead of fixing it in the control session:

     ```bash
     scripts/drive.sh mysess:1.2 "Review on PR #<n> requested changes: <one-line summary>. Findings are inline on the PR — address the 🔴 Important ones, push, and reply on the PR when done."
     ```

     Keep it to one line — `drive.sh` sends it as a single prompt — and avoid double
     quotes and backticks in the message, since it passes through the shell.
   - **Changes requested** and no live session (`TARGET=-`, or `CMD` is a shell): just
     request changes and note in your log that the session is gone, so the author has
     to pick it up manually. Do **not** re-dispatch a worktree to fix it — that is the
     user's call.
   - **Merged**: report the ready-to-run teardown command with the `TARGET` and `DIR`
     from `sessions.sh` (see [Cleanup](#cleanup-optional)). Only run it yourself if the
     user asked for teardown-on-merge this sweep, or the policy sets
     `TEARDOWN_ON_MERGE=true`. `teardown.sh` refuses on uncommitted changes, but it
     does kill a live pane — so it stays opt-in.
   - **Skipped**: leave the session alone entirely.

### Anti-gaming rules (do not violate)

- Do NOT hand-review in place of `/code-review`, and do NOT suppress, downgrade, or
  ignore its 🔴 Important findings to clear a merge.
- Read `review-policy.md` as written. Do NOT relax, reinterpret, or edit it — editing
  the policy to make a PR mergeable is the failure mode this whole split exists to
  prevent.
- Do NOT modify the gate command, the `/code-review` invocation, or the merge criteria
  to force success.
- "CI still running" is NOT "CI passed." Never treat pending as success.
- Never edit the PR branch, CI config, or repo settings to satisfy a criterion — and
  never `drive.sh` the worktree session into doing it for you.
- If `/code-review` errors or returns no result, comment that review is pending and
  SKIP — never merge an unreviewed PR.
- If you cannot confirm EVERY merge criterion, do not merge — comment and skip.
- If stuck across passes, STOP and report blockers rather than forcing action.

### Output

One status line per PR: number, code-review verdict (e.g. `2🔴 1🟡`), decision, action
taken, and where it was routed (`→ drove mysess:1.2`, `→ teardown pending`, `→ no live
session`). Keep the log scannable.

## Cleanup (optional)

After the PR merges, tear the session down from the control session. Get `TARGET` and
`DIR` from `sessions.sh <branch>` if you no longer have them:

```bash
scripts/teardown.sh mysess:1.2 /path/repo-worktrees/feature-add-dark-mode
# also delete the (merged) branch:
scripts/teardown.sh mysess:1.2 /path/.../feature-add-dark-mode --delete-branch feature/add-dark-mode
```

`teardown.sh` exits Claude, closes only its pane, and runs `git worktree remove`
**without `--force`**, so git refuses if there are uncommitted changes — safe by
design. Branch deletion uses `git branch -d`, which only removes it if already merged.

## Optional: bind to slash commands

If you'd rather type `/feature …`, `/bugfix …`, and `/pr-sweep`, see
`references/slash-command.md` for three one-line command files you can drop into
`.claude/commands/`.

## Preconditions & assumptions

- The control session runs **inside tmux** (`spawn.sh` refuses otherwise).
- The worktree is cut from the control session's **current branch** by default;
  point it elsewhere with `WT_BASE` or a 3rd arg. Whatever the base is, it should be
  freshly synced first — e.g. `git fetch && git switch main && git pull` (or your
  integration branch) — before dispatching.
- Any repo-local skills/commands you want the child session to have must be committed
  (worktrees only check out tracked files); user-level `~/.claude/` always applies.
- Sweeping additionally needs `gh` authenticated and a **`review-policy.md` in the
  repo being swept** — `references/review-policy.md` is the template to copy and tune.
- `sessions.sh` matches panes by working directory, so it only finds sessions whose
  cwd is still the worktree root. A pane the user `cd`'d elsewhere reports `TARGET=-`;
  fall back to asking rather than guessing a target.
