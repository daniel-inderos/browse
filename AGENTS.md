# AGENTS.md

## General workflow

- Keep changes small and focused.
- Before editing, inspect the relevant files and briefly explain the plan.
- Prefer minimal changes over rewrites.
- Do not modify unrelated files.
- After changes, run the most relevant lint/typecheck/test command if available.
- If tests fail because of unrelated existing issues, say so clearly and do not hide it.

## Open-source privacy hygiene

- Treat this repository as a public/open-source project.
- Do not commit personal information, private emails, account IDs, local usernames, machine-specific absolute paths, signing identities, certificates, provisioning profile details, access tokens, API keys, secrets, or private URLs.
- Prefer generic configuration, environment variables, auto-detection, placeholders, and documented setup steps over hard-coded personal or local values.
- Before staging or committing, inspect diffs for accidental personal data or secrets.
- If personal data or a secret is already committed, call it out immediately and rewrite/amend history before pushing when possible.

## Open-source project practices

- Assume changes may be read, reviewed, built, and maintained by outside contributors.
- Keep setup, build, and test steps reproducible on a clean machine; document any new required tools, services, or environment variables.
- Avoid depending on private infrastructure, local-only paths, proprietary assets, or undocumented accounts.
- Preserve license headers and attribution when editing existing files or adding third-party code/assets.
- Favor clear public-facing names, comments, errors, and documentation over shorthand that only makes sense locally.
- When adding dependencies, choose actively maintained packages with compatible licenses and avoid unnecessary supply-chain risk.

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
