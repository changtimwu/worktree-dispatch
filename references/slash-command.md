# Optional: bind the skill to `/feature`, `/bugfix`, and `/pr-sweep`

Slash commands live in `.claude/commands/` (project) or `~/.claude/commands/`
(global) — **not** inside the skill folder. Each is a tiny Markdown file whose body
is the prompt Claude runs, with `$ARGUMENTS` substituted from what you type.

Create `.claude/commands/feature.md`:

```markdown
---
description: Dispatch a new feature worktree session from the control session
---
Use the worktree-dispatch skill to spawn a **feature** session for: $ARGUMENTS
```

Create `.claude/commands/bugfix.md`:

```markdown
---
description: Dispatch a new bugfix worktree session from the control session
---
Use the worktree-dispatch skill to spawn a **bugfix** session for: $ARGUMENTS
```

Create `.claude/commands/pr-sweep.md`:

```markdown
---
description: Triage open PRs — delegate review to /code-review, decide per review-policy.md
---
Use the worktree-dispatch skill, "Sweeping the PRs" mode: run one full sweep pass over
the open PRs. $ARGUMENTS
```

`$ARGUMENTS` is optional here — use it to narrow or tune a pass, e.g.
`/pr-sweep only #412` or `/pr-sweep tear down sessions after merge`.

Then, from the control session:

```
/feature add dark mode toggle
/bugfix login times out after idle
/pr-sweep
```

Each command just hands the request to the skill, so all the branch-naming, worktree,
tmux, and sweep logic stays in one place — and the sweep's anti-gaming rules can't
drift out of sync with a copy pasted into a command file.
