# Security Policy

Browse is an experimental macOS browser project. Security reports are welcome, especially when they affect private browsing behavior, local data persistence, API-key handling, WebKit integration, remote content handling, or supply-chain risk.

## Supported Versions

Browse has not published stable releases yet.

| Version | Security Support |
| --- | --- |
| `main` branch | Supported for responsible vulnerability reports |
| Tagged pre-releases | Best effort |
| Old commits or forks | Not supported by this project |

## Reporting a Vulnerability

Please do not open a public issue for a vulnerability.

Use GitHub's private vulnerability reporting for this repository. Maintainers should enable it from the repository's Security settings before public launch.

If private vulnerability reporting is not available, open a public issue only to ask for a private reporting channel. Do not include exploit details, secrets, private URLs, logs with sensitive content, or reproduction steps in that public issue.

Helpful reports include:

- A concise description of the issue and impact.
- Affected commit, branch, tag, or release.
- macOS and Xcode versions used for reproduction.
- Minimal reproduction steps.
- Whether API keys, private browsing state, persisted browser data, or page content can be exposed.
- Any relevant logs with secrets, tokens, personal data, and private URLs removed.
- Whether an AI agent helped discover or reproduce the issue, if that context affects reproducibility.

## What to Report

Security-sensitive areas include:

- API-key storage, migration, access, or logging.
- Private-window data persistence or remote lookup behavior.
- Browser session persistence, page chat persistence, and local storage paths.
- Remote content handling in briefings, citations, favicons, autocomplete, and page chat.
- Dependency or build-system issues that could compromise users or contributors.
- Crashes or denial-of-service issues triggered by untrusted web content or malformed API responses.

General bugs, feature requests, and UI issues can be reported through normal public issues.

## AI Agent Safety

AI coding agents and automated analysis tools are welcome in security research too. They can be useful for tracing data flow, writing small repros, and checking edge cases. Please keep real user data and secrets out of prompts, transcripts, and generated artifacts.

When using an agent for security work, prefer:

- Use synthetic API keys, local fixtures, and redacted logs.
- Review any generated report before sending it to maintainers.
- Remove private URLs, page content, usernames, machine paths, signing details, and tokens.
- Keep exploit details in the private reporting channel.
- Test only local code, your own systems, or systems where you have permission.

## Response Expectations

The maintainers will try to:

- Acknowledge valid reports within 7 days.
- Confirm scope and reproduction details.
- Prioritize fixes based on user impact and exploitability.
- Credit reporters when requested and appropriate.

Because Browse is experimental and maintainer availability can vary, these targets are not service-level guarantees.

## Coordinated Disclosure

Please give maintainers a reasonable opportunity to investigate and fix confirmed vulnerabilities before public disclosure. Avoid sharing exploit details publicly until a fix or mitigation is available.
