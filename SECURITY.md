# Security Policy

## Supported Versions

Only the latest release receives security fixes. Older releases are not patched.

| Version | Supported |
| ------- | --------- |
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

**Preferred:** Use [GitHub Security Advisories](https://github.com/mrzeszowski/claude-code-keep-alive/security/advisories/new) — open a draft advisory via the Security tab. Reports stay private until a fix is released.

**Fallback:** Email [mrzeszowski@outlook.com](mailto:mrzeszowski@outlook.com) if you cannot use GitHub.

When reporting, please include:

- Affected version (check `.claude-plugin/plugin.json`)
- OS and platform (macOS / Linux / Windows)
- Steps to reproduce
- Potential impact

This project is maintained on a best-effort basis with no committed response timeline.

## Security Scope

**In scope** — please report these:

- Path traversal or symlink attacks on the state file (`~/.cache/claude-code-keep-alive/state`)
- Command injection via user-supplied arguments passed to `caffeinate`, `systemd-inhibit`, or `pwsh`
- Privilege escalation via the plugin's shell execution context
- Lock file race conditions (`state.lock`) exploitable by a local attacker

**Out of scope** — not security issues for this plugin:

- Bugs or CVEs in `caffeinate`, `systemd-inhibit`, `pwsh`, or the OS sleep subsystem itself
- The machine being allowed to sleep (intended behavior when the plugin is inactive)
- Denial-of-service by invoking slash commands repeatedly as an authorized local user

## Coordinated Disclosure

Please do not publicly disclose the issue until a fix is released. We will aim to ship a fix before you go public. If you would like credit, we will acknowledge you in the release notes.
