# Optional: bind the skill to `/feature` and `/bugfix`

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

Then, from the control session:

```
/feature add dark mode toggle
/bugfix login times out after idle
```

Each command just hands the request to the skill, so all the branch-naming,
worktree, and tmux logic stays in one place.
