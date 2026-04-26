# AGENTS.md

## General workflow

- Keep changes small and focused.
- Before editing, inspect the relevant files and briefly explain the plan.
- Prefer minimal changes over rewrites.
- Do not modify unrelated files.
- After changes, run the most relevant lint/typecheck/test command if available.
- If tests fail because of unrelated existing issues, say so clearly and do not hide it.

## Git rules

- Never run `git add .` or `git add -A` unless I explicitly ask.
- Before committing, run `git status --short` and inspect the diff.
- Stage only files or hunks related to the current task.
- Do not revert, overwrite, or "clean up" unrelated dirty files.
- If other files are modified by another agent/thread, leave them alone.
- Prefer small atomic commits with clear messages.
- Commit message format:
  - `feat: ...`
  - `fix: ...`
  - `refactor: ...`
  - `test: ...`
  - `docs: ...`
  - `chore: ...`

## Completion checklist

Before saying the task is done, report:
- Files changed
- Tests/checks run
- Any risks or follow-up needed
