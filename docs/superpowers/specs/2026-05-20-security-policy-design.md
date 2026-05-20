# Security Policy Design

**Date:** 2026-05-20
**Status:** Approved

## Goal

Add a `SECURITY.md` to the repository root so that security researchers and users know how to responsibly disclose vulnerabilities and what to expect in return.

## Context

The plugin is ~200 lines of POSIX sh, maintained by a single maintainer. It spawns detached system processes (`caffeinate`, `systemd-inhibit`, `pwsh`) and writes a state file under `~/.cache`. The threat surface is small but real: user-supplied arguments flow into shell commands, and the state file is world-readable by default on most systems.

## Approach

Option B: standard responsible disclosure policy plus a security scope section. Honest about best-effort, no SLA. Avoids over-promising what a single maintainer can deliver.

## Sections

### Supported Versions

A table listing only the latest release as the supported version. Older releases do not receive security patches.

### Reporting a Vulnerability

Two disclosure channels, in order of preference:

1. **GitHub Security Advisories** — private by default; reporters open a draft advisory via the repo's Security tab ("Report a vulnerability" button). This is the preferred channel.
2. **Email** — `mrzeszowski@outlook.com` as a fallback for reporters who cannot use GitHub.

Reporters should include:
- Affected version
- OS and platform (macOS / Linux / Windows)
- Steps to reproduce
- Potential impact

No response timeline is committed to. The maintainer will respond when capacity allows (best-effort).

### Security Scope

**In-scope** (worth reporting):
- Path traversal or symlink attacks on the state file (`~/.cache/claude-code-keep-alive/state`)
- Command injection via user-supplied arguments passed to `caffeinate`, `systemd-inhibit`, or `pwsh`
- Privilege escalation via the plugin's shell execution context
- Lock file race conditions (`state.lock`) exploitable by a local attacker

**Out-of-scope** (not a security issue for this plugin):
- Bugs or CVEs in `caffeinate`, `systemd-inhibit`, `pwsh`, or the OS sleep subsystem
- The machine being allowed to sleep (intended behavior when the plugin is inactive)
- Denial-of-service by invoking the commands repeatedly as an authorized local user

### Coordinated Disclosure

Reporters are asked not to publicly disclose the issue until a fix is released. The maintainer will aim to ship a fix before the reporter goes public. Reporters who want credit will be acknowledged in the release notes.

## Implementation

A single file: `SECURITY.md` at the repository root. No changes to existing files required. Standard GitHub location — GitHub surfaces it automatically in the Security tab and in the "Report a vulnerability" flow.
