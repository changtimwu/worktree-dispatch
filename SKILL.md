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

## Preflight — you run this, not the user

**This is your job, not a setup step you ask the user to perform.** Run it at the top of
every dispatch and every sweep, before anything else. The user should never have to run
it by hand or be told to; they only hear about it when a check fails, and then only as
the specific problem plus its fix.

Repos and environments are often not set up for this skill, and the failures are quiet:
a sweep on a repo with no `ready-for-review` label reports "nothing to do" forever,
because `gh pr list --label <missing>` returns `[]` with exit 0. So check first:

```bash
scripts/preflight.sh dispatch     # or: sweep | all (default)
```

Each line is `CHECK=<name> STATUS=ok|warn|fail DETAIL=<one line, ending in the fix>`;
exit 1 means something failed for that mode.

- **`fail`** — stop. Relay the `DETAIL` (it already names the fix) and let the user
  decide. Never work around a fail: don't widen the sweep gate, don't invent merge
  criteria, don't pick a different base than the one that failed the check.
- **`warn`** — proceed, but say it out loud in your report. Warnings are the things the
  user would be surprised by later: cutting from a non-default branch, dispatching into
  a detached session, a repo where nothing can ever merge.
- Two `fail`s have a supported recovery path rather than a dead end — the missing
  `ready-for-review` label and the missing `review-policy.md`. Both are covered under
  [Sweeping the PRs](#preflight-once-per-sweep-not-per-pr); both end in a **one-time
  question** whose answer is written into the repo's `review-policy.md`.

## Dispatch

### What it does, in order

0. **`scripts/preflight.sh dispatch`** — always, without being asked. A freshly cloned
   repo passes this clean, so it usually costs one silent command and nothing else.
1. Classify the request as **feature** or **bugfix** and derive a kebab-case slug
   from the description. Branch name follows your convention:
   `feature/<slug>` or `bugfix/<slug>`.
2. Create the worktree with `git worktree add`, cut from the control session's
   **current branch** by default (override with the `WT_BASE` env var or a 3rd
   arg), in a sibling folder `../<repo>-worktrees/<label>`.
3. Open a **new tmux pane in the current window** (a split of your control session —
   not a detached `--tmux` session), cwd set to the worktree. Split is side-by-side
   (left|right) by default; set `WT_SPLIT=v` for stacked/full-width. If the control
   session is **not inside tmux**, the pane goes into a background session instead —
   see [Not inside tmux](#not-inside-tmux).
4. Launch `claude --name '<branch>'` in that window so the session is identifiable
   by branch — locally and in any remote-control list.
5. Clear the **trust prompt** (see below) and hand back the tmux **target**
   (`session:window.pane`) so you can peek at / drive the session for the rest of its life.

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

**Step 0 — preflight.** `scripts/preflight.sh dispatch`. On a clean repo this is one
quiet command; don't narrate it. Only a `fail` or `warn` reaches the user.

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
TARGET=mysess:1.2 BRANCH=feature/add-dark-mode DIR=/path/repo-worktrees/feature-add-dark-mode BASE=main MODE=split SESSION=mysess
```

Parse `TARGET`, `BRANCH`, `DIR`, `BASE`, `MODE`, and `SESSION` from that line and remember
them for this session. `BASE` tells you which branch it was actually cut from — worth
relaying to the user so there's no surprise. If a branch or worktree dir already exists, or
the control session is in detached HEAD with no base given, `spawn.sh` refuses rather than
clobbering — report the error to the user and stop.

#### Not inside tmux

`MODE=detached` means the control session wasn't in tmux, so the worktree went into a
background session (`SESSION`, default `wtd`) instead of a split. Everything else is
identical — `peek.sh`, `drive.sh`, `sessions.sh`, and `teardown.sh` all work on detached
panes, because tmux drives them server-side whether or not anyone is attached. Each
further dispatch gets its own window in that session, and the session disappears on its
own when the last window is torn down.

The one thing that changes is your report: **lead with `tmux attach -t <SESSION>`**,
otherwise the user has a Claude session running that they cannot see. `WT_NO_DETACH=1`
turns this back into a hard failure, and a missing tmux binary always is one.

#### Clear the trust prompt

A brand-new worktree is a directory Claude has never seen, so the spawned session opens
on **"Do you trust the files in this folder?"** and sits there — `drive.sh` input would
go into that dialog, not the prompt. Peek, and if the dialog is up, answer it:

```bash
scripts/peek.sh mysess:1.2 12
scripts/drive.sh mysess:1.2 "1"      # 1 = Yes, I trust this folder
scripts/peek.sh mysess:1.2 8         # confirm it reached the input prompt
```

This is a worktree of the repo the user just dispatched from, cut from their own branch
on their instruction, so trusting it adds no exposure they haven't already accepted. Peek
again afterward: that same peek is what proves Claude actually launched (it also catches
`claude: command not found`, which preflight only warns about).

**Step 5 — report.** Tell the user, concisely: the branch, the worktree dir, the tmux
target (plus the attach command when `MODE=detached`), any preflight warnings, and how
they'll interact (see below). Do NOT keep the turn open waiting — they'll come back when
there's a PR to review.

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
# BRANCH=feature/add-dark-mode DIR=/path/…/feature-add-dark-mode TARGET=mysess:1.2 CMD=2.1.220 ALIVE=yes
```

`TARGET=-` means no pane is sitting in that worktree (session torn down, or never
dispatched from here). `ALIVE=no` means the pane fell back to a shell — Claude exited.
**Never `drive.sh` into `ALIVE=no`**: the shell would run your prompt as a command. Note
a live Claude reports its version as the command name (`CMD=2.1.220`), not `claude`, and
`ALIVE=yes` only means *something* is in the foreground — `peek.sh` when it matters.

## Sweeping the PRs

The other half of the control session: triage the PRs the dispatched sessions put up.
Review is **delegated to `/code-review`** and the merge decision is **delegated to the
target repo's `review-policy.md`** — the sweep itself only routes.

### Preflight (once per sweep, not per PR)

```bash
scripts/preflight.sh sweep
```

Then read the target repo's `review-policy.md` **as written** — its knobs
(`INTEGRATION_BASE`, `SIZE_CAP`, `ALLOW_NO_CI`, `REQUIRE_LABEL`, …) govern everything
below. Three failures have a defined recovery; everything else is a stop-and-report.

**`review-policy` fail — no policy file.** Do not invent merge criteria and do not fall
back to "reasonable defaults". Offer to copy `references/review-policy.md` into the repo
root, and say plainly that its knobs need tuning before the first sweep. Copy it only on
an explicit yes — it is the user's merge policy, not yours.

**`sweep-label` fail — the label doesn't exist.** This is the silent one: the gate would
return `[]` forever while PRs pile up. Stop, quote the open-PR count from the `DETAIL`,
and offer exactly three choices:

1. `gh label create <label>` — keep the gate, start labelling PRs as they become ready.
2. Sweep every non-draft PR targeting the base instead — sets `REQUIRE_LABEL=false`.
   Say what this widens: with no label gate, *every* open PR is a merge candidate and
   `review-policy.md` is the only thing between an unlabelled PR and a squash merge.
3. Abort.

**`ci` warn — no CI and `ALLOW_NO_CI=false`.** Nothing can satisfy the merge criteria, so
the sweep can only ever comment. Offer to set `ALLOW_NO_CI=true` (merges then carry a
`no CI configured` note), or to proceed comment-only.

In all three cases, **write the answer into that repo's `review-policy.md` knobs block**
once the user picks — with their consent, since it changes their merge policy. That is
what makes this a one-time question per repo instead of a prompt every sweep.

### Gate command (run FIRST every pass; treat the output as the worklist)

```bash
BASE="${WT_SWEEP_BASE:-$(git rev-parse --abbrev-ref HEAD)}"   # default: the branch you're on
gh pr list --label "${WT_SWEEP_LABEL:-ready-for-review}" --base "$BASE" \
  --json number,title,isDraft,reviewDecision,statusCheckRollup,headRefName
# REQUIRE_LABEL=false in review-policy.md → drop the --label filter entirely
```

The base defaults to the control session's **current branch** — the same branch
`spawn.sh` cuts from, so dispatch and sweep agree by construction; preflight's
`policy-base` check fails if that disagrees with `INTEGRATION_BASE`. Act only on PRs this
returns. Skip drafts. Process the delta since the last pass.

An empty result means "nothing is ready" **only because preflight already proved the
label exists**. Never treat an unverified empty gate as an empty worklist, and never widen
the gate on your own to make it non-empty.

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

   - **Changes requested** and the branch has a live session (`TARGET` ≠ `-`, `ALIVE=yes`):
     after `gh pr review <n> --request-changes`, hand the work back to the session that
     owns the branch instead of fixing it in the control session:

     ```bash
     scripts/drive.sh mysess:1.2 "Review on PR #<n> requested changes: <one-line summary>. Findings are inline on the PR — address the 🔴 Important ones, push, and reply on the PR when done."
     ```

     Keep it to one line — `drive.sh` sends it as a single prompt — and avoid double
     quotes and backticks in the message, since it passes through the shell.
   - **Changes requested** and no live session (`TARGET=-`, or `ALIVE=no`): just
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
- Never silence a preflight `fail` by working around it: don't drop the label filter
  because the label is missing, don't switch base because `policy-base` disagreed, don't
  write a `review-policy.md` yourself to get past the missing-policy check. Each of those
  is the user's decision, asked once and recorded in their policy file.
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

`scripts/preflight.sh` checks all of the mechanical ones — run it rather than assuming.
What it can't check:

- The base should be **freshly synced** before dispatching — e.g.
  `git fetch && git switch main && git pull`. Preflight tells you *which* branch you'd cut
  from, not whether it's current.
- Any repo-local skills/commands you want the child session to have must be **committed**
  (worktrees only check out tracked files); user-level `~/.claude/` always applies.
- `sessions.sh` matches panes by working directory, so it only finds sessions whose cwd is
  still the worktree root. A pane the user `cd`'d elsewhere reports `TARGET=-`; ask rather
  than guessing a target.
- `review-policy.md` being *present* is checked; whether its knobs suit the repo is not.
  A freshly copied template still needs tuning — say so the first time you use one.
