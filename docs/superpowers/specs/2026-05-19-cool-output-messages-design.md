# Design: Cool Output Messages for keep-alive

**Date:** 2026-05-19  
**Scope:** `bin/keep-alive` — `_cmd_status` function only

## Problem

Current output is terse and machine-flavored (`keep-alive: on (since 2026-05-19T10:00:00Z, PID 1234)`). PIDs and ISO timestamps are exposed in every status line. The UX goal is friendly confirmations that tell the user what just happened without implementation noise.

## Decision

Emoji + short context phrase. One line per state. No PID, no ISO timestamp.

## New Output Messages

| State | stdout |
|---|---|
| `off` | `✔  Keep-alive off — machine can sleep normally.` |
| `on` (indefinite) | `☕ Keep-alive on — machine won't sleep.` |
| `on` (timed) | `☕ Keep-alive on (timed) — machine won't sleep.` |
| `busy`, idle | `💤 Busy mode — idle, waiting for next prompt.` |
| `busy`, active | `💤 Busy mode — currently inhibiting sleep.` |

## Architecture

All five messages come from `_cmd_status`. Every public command (`on`, `off`, `busy`, `status`) already calls `_cmd_status` as its final output step — so changing that one function is the complete change. No other functions touched.

Error messages (stderr paths: invalid args, missing binary, unsupported platform) are unchanged — they are diagnostic, not UX.

### Duration display

`expires_at` is stored as an ISO 8601 UTC string. Computing a human-readable countdown (`expires in ~25m`) requires POSIX date arithmetic and branching for both BSD and GNU `date`. Out of scope for v0.1 — `(timed)` label is sufficient. Can revisit in v0.2.

## Test Impact

Approximately 8 assertions in `tests/` match the old `keep-alive: on / off / duration / busy` string patterns. These must be updated to the new format. No new test cases required.

## Out of Scope

- `commands/*.md` frontmatter (descriptions, argument hints) — not changing.
- Error message formatting — not changing.
- Relative duration countdown in timed mode — deferred to v0.2.
