# review-policy.md (template)

**Copy this file to the root of the repo you sweep** and tune the knobs at the bottom.
It is deliberately per-repo: size caps, CI expectations, and sensitive paths differ
everywhere, and the sweep must not invent them. If the target repo has no
`review-policy.md`, the sweep stops and asks for one rather than guessing.

Merge/reject/skip policy for the PR sweep. The sweep applies this **exactly** — it is the
only judgment step. Keep it mechanical and unambiguous.

Severity taxonomy comes from `/code-review`: **🔴 Important**, **🟡 Nit**, **🟣 Pre-existing**.

Decision inputs the sweep gathers per PR:
- `/code-review <n> --comment` → findings by severity
- `gh pr checks <n>` → CI status
- `gh pr view <n> --json reviewDecision,files,additions,deletions,isDraft,headRefName`
- `scripts/sessions.sh <headRefName>` → whether a live worktree session still owns the branch

## Knobs

`scripts/preflight.sh` reads this block — it is the authoritative copy of these values.
Keep it; the table below only explains what each one means.

```
INTEGRATION_BASE=main
SIZE_CAP=400
ALLOW_NO_CI=false
REQUIRE_HUMAN_APPROVAL=false
REQUIRE_LABEL=true
SWEEP_LABEL=ready-for-review
TEARDOWN_ON_MERGE=false
```

| Knob | Meaning |
|---|---|
| `INTEGRATION_BASE` | The branch PRs must target. Must match the sweep gate's base, which defaults to the control session's current branch; preflight fails on a mismatch rather than sweeping the wrong queue. |
| `SIZE_CAP` | Max `additions + deletions` for auto-merge. |
| `ALLOW_NO_CI` | `true` only if the repo genuinely has no CI; a no-checks PR is then mergeable and the merge comment must say `no CI configured`. While this is `false` in a repo with no CI, **nothing can ever merge** — preflight warns about exactly that. |
| `REQUIRE_HUMAN_APPROVAL` | If `true`, also require `reviewDecision == "APPROVED"` to merge. |
| `REQUIRE_LABEL` | Whether the gate filters on `SWEEP_LABEL`. Set `false` to sweep every non-draft PR targeting the base — appropriate for a solo repo with no label workflow, but it widens auto-merge scope, so decide deliberately. |
| `SWEEP_LABEL` | The label the gate filters on when `REQUIRE_LABEL=true`. It must exist in the repo: `gh pr list --label <missing>` returns `[]` with exit 0, which is indistinguishable from "nothing is ready". Preflight checks this. |
| `TEARDOWN_ON_MERGE` | If `true`, the sweep tears down the merged branch's worktree session without asking. Off by default: teardown kills a live pane. |

**Solo repo starter.** A main-only repo with no CI and no label workflow usually wants
`INTEGRATION_BASE=main`, `ALLOW_NO_CI=true`, `REQUIRE_LABEL=false` — otherwise the sweep
either finds nothing or can never merge what it finds.

## Precedence

Evaluate in this order; first matching outcome wins:
1. **SKIP conditions** (below) → comment one line, stop on this PR.
2. **REJECT criteria** (any hit) → `gh pr review <n> --request-changes`.
3. **MERGE criteria** (all hold) → `gh pr merge <n> --squash`.
4. Anything else → comment one line, stop on this PR.

## SKIP (comment + stop, do not merge)

- `/code-review` errored or returned no findings result (review is not trustworthy).
- CI has any check that is **pending/queued/in-progress** ("running" is never "passed").
- `additions + deletions > SIZE_CAP` — too large for auto-merge; needs a human.
- PR touches any **sensitive path** (knob): `**/.github/workflows/**`, `**/*.env*`,
  `**/settings*.json`, CI config, or repo-config files.
- `isDraft: true` (the gate already filters drafts; this is a backstop).
- The PR is a spike/investigation (label `spike`, or the body says "investigation only").

## REJECT — `--request-changes` (any one)

- **Any 🔴 Important finding** from `/code-review`. (Never downgrade/suppress a 🔴 to clear a merge.)
- CI has any check in a **failure/error/cancelled/timed-out** state.
- `reviewDecision == "CHANGES_REQUESTED"` and the request is unresolved.

Body must cite the criterion + the specific finding refs (file:line or check name).

## MERGE — `--squash` (ALL must hold)

- **Zero 🔴 Important findings.** (🟡 Nits and 🟣 Pre-existing do **not** block.)
- **CI: all checks passing**, OR the repo has **no checks configured at all** and
  `ALLOW_NO_CI=true` (the merge comment must then say `no CI configured`).
  Never treat *pending* as *no checks*.
- `reviewDecision` is **not** `CHANGES_REQUESTED`.
- `isDraft: false`.
- `additions + deletions <= SIZE_CAP`.
- Base branch is `INTEGRATION_BASE`.
- No sensitive paths touched (see SKIP list).
