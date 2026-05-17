# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-05-17

### Added
- `/keep-alive:on` — inhibit sleep until released, with optional duration argument (`30m`, `8h`, `1d`, bare-number=minutes).
- `/keep-alive:off` — release the inhibitor.
- `/keep-alive:busy` — inhibit sleep only while Claude is actively processing.
- `/keep-alive:status` — show current state.
- macOS support via `caffeinate`.
- Linux (systemd) support via `systemd-inhibit`.
- `UserPromptSubmit` + `Stop` hooks driving busy mode.
- bats test suite running on macOS and Ubuntu in CI.

### Known limitations
- Windows is not yet supported. The script detects Windows and prints an actionable error.
- State is a single machine-global record, not per-session.

[Unreleased]: https://github.com/mrzeszowski/claude-code-keep-alive/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mrzeszowski/claude-code-keep-alive/releases/tag/v0.1.0
