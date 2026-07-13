# Contributing to Browse

Thanks for helping improve Browse. This project is a native macOS browser experiment built with SwiftUI, WebKit, and a small number of AI-backed research features.

## Project Status

Browse is experimental. It is not a hardened general-purpose browser distribution yet. Contributions should preserve that honesty: prefer clear behavior, reproducible setup, privacy-conscious defaults, and focused changes over broad rewrites.

## Ways to Contribute

- Fix bugs in browsing, tabs, persistence, private windows, briefings, chat, or settings.
- Add focused tests around existing behavior.
- Improve documentation for setup, privacy, troubleshooting, or architecture.
- Propose small, well-scoped features through an issue before opening a large pull request.

## Development Setup

Requirements:

- macOS 15 or newer.
- Xcode with Swift 6 support.
- Network access for app features that browse the web or call remote services.

Set up and test the package:

```sh
swift package resolve
swift test
```

For interactive app development, open the package in Xcode:

```sh
open Package.swift
```

You can also launch from the command line:

```sh
swift run Browse
```

AI briefings and page chat require user-provided OpenAI and Exa API keys configured through `.env` or process environment variables. Copy `.env.example` to `.env` for local development. Tests should not require live API keys or live network calls.

## Workflow

Before starting:

- Search existing issues and pull requests.
- For larger changes, open an issue first and describe the intended behavior.
- Keep pull requests small enough to review.
- If you use an AI coding agent, it helps to give it this file, `AGENTS.md`, and the relevant README sections as context.

When making changes:

- Follow the existing Swift and SwiftUI style.
- Prefer local helpers and patterns already present in the codebase.
- Avoid unrelated refactors in feature or bug-fix pull requests.
- Add or update tests when behavior changes.
- Keep setup steps reproducible on a clean machine.

## Agent-Assisted Contributions

AI coding agents such as Codex, Claude Code, and similar tools are welcome here. Many contributors will use them, and that is fine. The goal is to make agent-assisted changes easy to understand, review, and maintain.

Agents tend to work best on tasks like:

- Explain an existing flow before making a change.
- Implement a focused bug fix with a clear file boundary.
- Add tests for documented behavior.
- Update docs after a behavior or setup change.
- Inspect diffs for privacy, security, and unrelated churn.

They tend to struggle when a task is too broad or underspecified, for example:

- Broad rewrites without a concrete issue.
- Large style-only refactors mixed with behavior changes.
- Dependency additions without license, maintenance, and necessity checks.
- Live-network tests that require contributor-owned accounts or secrets.
- Generated output that has not been read by a human.

A helpful prompt usually asks the agent to:

- Inspect relevant files before editing.
- Keep the change small and explain the plan.
- Avoid unrelated files.
- Avoid `git add .` and `git add -A`.
- Run the most relevant test command.
- Check `git diff` for secrets, local paths, signing details, and unrelated edits.

Before submitting agent-assisted work, please:

- Read the full diff yourself.
- Verify that tests, docs, and behavior match the pull request description.
- Remove agent scratch files, transcripts, hidden metadata, and generated logs unless they are intentionally part of the change.
- Mention meaningful agent assistance in the pull request notes when it would help reviewers understand the change.

Commit messages should use one of these prefixes:

- `feat: ...`
- `fix: ...`
- `refactor: ...`
- `test: ...`
- `docs: ...`
- `chore: ...`

## Privacy and Public Hygiene

Treat this repository as public at all times.

Do not commit:

- API keys, access tokens, passwords, or secrets.
- Personal emails or private account IDs.
- Local usernames or machine-specific absolute paths.
- Signing identities, certificates, provisioning profiles, or private team IDs.
- Private URLs or data copied from private browsing sessions.
- Generated build products.
- Agent transcripts, prompts, screenshots, or logs that include private context.

Prefer generic configuration, environment variables, documented setup steps, and placeholders over local or personal values.

Before opening a pull request, inspect your diff for accidental secrets or private data:

```sh
git status --short
git diff
```

## Testing

Run the full test suite before opening a pull request:

```sh
swift test
```

Focused examples:

```sh
swift test --filter IntentClassifier
swift test --filter IntentBarViewModel
swift test --filter BrowserPersistenceStore
```

If a test failure appears unrelated to your change, call that out in the pull request and include enough output for maintainers to reproduce it.

## Pull Request Checklist

Before requesting review, confirm:

- The change is focused and does not modify unrelated files.
- Documentation is updated when behavior, setup, or privacy expectations change.
- Tests were added or updated for behavior changes.
- `swift test` passes, or failures are clearly explained.
- The diff does not include secrets, personal data, signing details, or local paths.
- New dependencies are necessary, actively maintained, and license-compatible.
- Any agent-generated code has been read and checked by the contributor.

## Security Issues

Do not report vulnerabilities in public issues. Follow the process in `SECURITY.md`.
