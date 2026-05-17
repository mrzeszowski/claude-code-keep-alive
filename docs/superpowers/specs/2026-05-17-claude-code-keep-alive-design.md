# Claude Code Keep-Alive Plugin — Design

**Date:** 2026-05-17
**Status:** Draft, awaiting user review
**Repo:** `claude-code-keep-alive` (public, GitHub)

## 1. Goal

Build a Claude Code plugin that replicates the user-facing behavior of GitHub Copilot CLI's `/keep-alive` command: prevent the user's machine from going to sleep during a Claude Code session, with the same subcommand surface (`on`, `off`, `busy`, duration). Distribute it from a public GitHub repository that doubles as both the plugin source and a single-plugin marketplace, so users can install with two `/plugin` commands.

The motivation in Copilot CLI is to keep a session alive while the user steers it remotely from GitHub.com or mobile. Claude Code has no equivalent remote-steering surface; only the keep-awake mechanic is ported. Users will run this when they kick off long Claude Code tasks (multi-step builds, long agent runs) and walk away.

## 2. Non-Goals

- Remote control / "steer remotely" features. Out of scope; no Claude Code equivalent exists.
- Per-session isolation. State is a single machine-global record, matching Copilot CLI's behavior.
- First-class Windows support in v0.1. The script will detect Windows and print a clear "not yet supported, contributions welcome" message. Adding Windows support later is straightforward (PowerShell `SetThreadExecutionState` or `powercfg /requests`) and does not require redesign.
- Display-on-while-idle as a separate toggle. We always inhibit display + idle + system sleep when active (parity with what users expect from `caffeinate -dis`).

## 3. Command Surface

Closest achievable parity with Copilot CLI's `/keep-alive`. Claude Code plugin commands are namespaced as `/<plugin>:<command>`, so:

| User input                                | Behavior |
| ----------------------------------------- | -------- |
| `/keep-alive:keep-alive`                  | Print current status (mode, time remaining if applicable, inhibitor PID). |
| `/keep-alive:keep-alive on`               | Inhibit sleep until `off` is invoked. |
| `/keep-alive:keep-alive off`              | Release the inhibitor. |
| `/keep-alive:keep-alive busy`             | Inhibit only while Claude is actively processing (started/stopped by hooks on `UserPromptSubmit`/`Stop`). |
| `/keep-alive:keep-alive <N>m`             | Inhibit for N minutes, then auto-release. |
| `/keep-alive:keep-alive <N>h`             | Inhibit for N hours, then auto-release. |
| `/keep-alive:keep-alive <N>d`             | Inhibit for N days, then auto-release. |
| `/keep-alive:keep-alive <N>`              | Bare number = minutes (Copilot parity). |

The doubled `keep-alive:keep-alive` is the price of Claude Code's mandatory namespacing. Tab-completion makes it a single keystroke after `/k`. The README will explain this clearly so the redundancy doesn't feel like a bug.

## 4. Architecture

Three pieces interact:

1. **Slash command** (`commands/keep-alive.md`) — a markdown prompt restricted to the Bash tool. Tells Claude to invoke `keep-alive $ARGUMENTS` and report output verbatim, or `keep-alive status` when no args were passed. No logic, just dispatch.
2. **Helper script** (`bin/keep-alive`) — a POSIX-sh script added to the Bash tool's `PATH` while the plugin is enabled. All real work lives here: argument parsing, platform detection, inhibitor lifecycle, state management.
3. **Hooks** (`hooks/hooks.json`) — register a `UserPromptSubmit` and a `Stop` hook. Both invoke `keep-alive --busy-event=start|stop` in the background. These are cheap no-ops unless the state file says `mode=busy`. This is what makes `busy` mode work without polling.

State persists in a single global file (`$HOME/.cache/claude-code-keep-alive/state.json`) protected by `flock`. The inhibitor process is detached via `setsid`/`nohup` so it survives across slash-command invocations and across Claude Code sessions.

## 5. Repository Layout

```
claude-code-keep-alive/                   public GitHub repo, also IS the plugin
├── .claude-plugin/
│   ├── plugin.json                       plugin manifest
│   └── marketplace.json                  marketplace listing (single entry: this plugin, source "./")
├── bin/
│   └── keep-alive                        POSIX-sh script, executable, added to PATH
├── commands/
│   └── keep-alive.md                     slash command (frontmatter + body)
├── hooks/
│   └── hooks.json                        UserPromptSubmit + Stop integration
├── tests/
│   ├── test_keep_alive.bats              bats integration tests
│   └── mocks/
│       └── caffeinate                    fake inhibitor that just sleeps
├── .github/workflows/ci.yml              run bats on macOS + Ubuntu
├── README.md                             install + usage + namespace explanation
└── LICENSE                               MIT
```

Single-repo-doubles-as-marketplace is the standard pattern for one-plugin distributions. The marketplace `source` points at `./` and lists this plugin only.

## 6. File-Level Specifications

### 6.1 `.claude-plugin/plugin.json`

```json
{
  "name": "keep-alive",
  "description": "Prevents your machine from sleeping during Claude Code sessions",
  "version": "0.1.0",
  "author": {
    "name": "Marcin Rzeszowski",
    "email": "mrzeszowski@outlook.com"
  },
  "homepage": "https://github.com/<github-user>/claude-code-keep-alive",
  "repository": "https://github.com/<github-user>/claude-code-keep-alive",
  "license": "MIT"
}
```

`<github-user>` is filled in when the repo is published. The implementation plan will treat this as a configuration step, not a code change.

### 6.2 `.claude-plugin/marketplace.json`

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "claude-code-keep-alive",
  "description": "Single-plugin marketplace for the keep-alive plugin",
  "owner": {
    "name": "Marcin Rzeszowski",
    "email": "mrzeszowski@outlook.com"
  },
  "plugins": [
    {
      "name": "keep-alive",
      "description": "Prevents your machine from sleeping during Claude Code sessions",
      "category": "productivity",
      "version": "0.1.0",
      "source": "./",
      "author": { "name": "Marcin Rzeszowski" },
      "homepage": "https://github.com/<github-user>/claude-code-keep-alive",
      "tags": ["productivity", "sleep", "caffeinate", "system"]
    }
  ]
}
```

### 6.3 `commands/keep-alive.md`

```markdown
---
description: Prevent the machine from sleeping during this Claude Code session (mirrors GitHub Copilot CLI /keep-alive)
argument-hint: "[on | off | busy | <N>m | <N>h | <N>d]"
allowed-tools: ["Bash"]
---

Run the following shell command using the Bash tool and print its stdout/stderr
verbatim, with no commentary, no summarization, and no follow-up suggestions:

If $ARGUMENTS is empty, run: `keep-alive status`
Otherwise run: `keep-alive $ARGUMENTS`
```

Restricting `allowed-tools` to `Bash` prevents the LLM from wandering off into editing files or asking clarifying questions when the user just wanted a status toggle.

### 6.4 `bin/keep-alive` — Behavior

**Argument grammar:**
- `` (empty) or `status` → print current state
- `on` → activate continuous inhibitor
- `off` → release inhibitor, clear state
- `busy` → set mode=busy; hooks will start/stop the inhibitor
- `<N>[mhd]` (e.g. `30m`, `8h`, `1d`, or bare `30` → minutes) → activate inhibitor with auto-expiry
- `--busy-event=start` / `--busy-event=stop` → internal, invoked only by hooks

**Platform detection** (via `uname -s`):
- `Darwin` → `caffeinate -dis` (display + idle + system on AC)
- `Linux` → `systemd-inhibit --what=idle:sleep --who=claude-code-keep-alive --why="Active Claude Code session" sleep infinity`
- `MINGW*` / `MSYS*` / `CYGWIN*` → print `"keep-alive: Windows not supported in v0.1; contributions welcome at <repo>"` to stderr and exit 2
- Other → same as Windows path, generic "unsupported" message

If the chosen inhibitor binary is missing on a supported platform, exit 3 with an install hint.

**State file:** `${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-keep-alive/state.json`

```json
{
  "mode": "off|on|busy|duration",
  "pid": 12345,
  "started_at": "2026-05-17T19:30:00Z",
  "expires_at": "2026-05-17T20:00:00Z"
}
```

All state reads/writes happen inside `flock` on a sibling `state.json.lock` file. Before trusting `pid`, the script verifies it with `kill -0 $pid` and clears the field if the process is gone (stale-PID recovery).

**Spawning the inhibitor:** detached via `setsid <cmd> </dev/null >/dev/null 2>&1 &` so it survives the shell that started it. For duration mode, wrapped in `timeout $SECONDS` so the kernel reaps it at expiry without needing a watchdog.

**`off` and `--busy-event=stop`:** read PID under flock, `kill $pid` if alive, clear PID + mode. If the inhibitor was launched via `timeout`/`systemd-inhibit ... sleep infinity`, sending TERM to the saved PID cleanly tears down the inhibit (`systemd-inhibit`'s child holds the lock — killing the wrapping `sleep` releases it; killing the parent `systemd-inhibit` is equivalent).

**`status`:** prints a single human-readable line, e.g.
```
keep-alive: on (since 2026-05-17 19:30:00 UTC, PID 12345)
keep-alive: busy (no inhibitor currently active)
keep-alive: 8h (expires 2026-05-18 03:30:00 UTC, PID 12345)
keep-alive: off
```

**Exit codes:** 0 success; 1 invalid args; 2 unsupported platform; 3 missing inhibitor binary; 4 internal state corruption.

### 6.5 `hooks/hooks.json`

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "keep-alive --busy-event=start >/dev/null 2>&1 &" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "keep-alive --busy-event=stop >/dev/null 2>&1 &" }
        ]
      }
    ]
  }
}
```

Backgrounded with `&` and silenced so a slow `flock` or transient script error never delays Claude's session flow.

The hook fires in every Claude Code session whenever the plugin is installed and enabled — even sessions that never invoked `/keep-alive`. That is acceptable because `--busy-event=*` does nothing unless the state file says `mode=busy`. The cost is one `flock`-protected JSON read per prompt/stop.

## 7. Data Flow Examples

### 7.1 `on` then walk away

1. User types `/keep-alive:keep-alive on`.
2. Claude's Bash tool runs `keep-alive on`.
3. Script takes flock, reads state (mode=off, no PID), spawns `caffeinate -dis` detached, records new PID, sets mode=on, releases flock.
4. Script prints `keep-alive: on (since ..., PID ...)`.
5. User closes laptop lid → display sleeps but system stays awake.
6. Later, user runs `/keep-alive:keep-alive off`. Script kills PID, clears state, prints `keep-alive: off`.

### 7.2 `busy` mode across a long agent run

1. User types `/keep-alive:keep-alive busy`. Script writes mode=busy. No inhibitor running yet.
2. User submits a prompt that triggers a long agent loop.
3. `UserPromptSubmit` hook fires → `keep-alive --busy-event=start`. Script sees mode=busy and no live PID → spawns inhibitor, saves PID.
4. Agent runs for 20 minutes, machine stays awake.
5. Agent stops, Claude returns control to user. `Stop` hook fires → `keep-alive --busy-event=stop`. Script kills PID, leaves mode=busy.
6. User reads output for 5 minutes; machine is free to sleep.
7. User submits next prompt. `UserPromptSubmit` fires → inhibitor starts again. Loop continues.
8. User runs `/keep-alive:keep-alive off`. Script clears mode entirely; hooks become no-ops.

### 7.3 Duration mode

1. User types `/keep-alive:keep-alive 30m`.
2. Script spawns `timeout 1800 caffeinate -dis` detached, saves PID, sets mode=duration, expires_at=now+30m.
3. After 30 minutes, `timeout` kills `caffeinate`. Next `status` call notices the PID is gone, clears state, reports `off`.

## 8. Installation Flow

```text
1. Open Claude Code
2. /plugin marketplace add <github-user>/claude-code-keep-alive
3. /plugin install keep-alive@claude-code-keep-alive
4. /reload-plugins   (or restart)
5. /keep-alive:keep-alive on
```

For development:
```text
claude --plugin-dir /path/to/claude-code-keep-alive
/reload-plugins
```

## 9. Error Handling

| Condition                              | Behavior |
| -------------------------------------- | -------- |
| Unsupported OS (Windows v0.1, other)    | stderr message, exit 2. Slash command surfaces stderr to the user verbatim. |
| `caffeinate` / `systemd-inhibit` absent | stderr install hint, exit 3. |
| Invalid args (`/keep-alive 5x`)         | stderr usage, exit 1. |
| State file corrupt or unparseable       | stderr warning, reset state, exit 4. |
| Stale PID (process already exited)      | silently clean state, continue with intended action. |
| Concurrent invocation                   | `flock` serializes. Lock is held briefly; spawned inhibitors live outside the lock. |
| Inhibitor dies unexpectedly             | Next `status` or `--busy-event=*` notices via `kill -0` and clears state. |

## 10. Testing Strategy

**Unit / integration: bats**

- Fixture: `tests/mocks/caffeinate` and `tests/mocks/systemd-inhibit` are scripts that just `exec sleep 9999`. `PATH` is rewritten in the test harness.
- State file location overridden via `KEEP_ALIVE_STATE_DIR` env var (also supported in the real script for testability).
- Test cases:
  - `status` on empty state prints `off`
  - `on` → `status` shows mode=on, PID alive
  - `on` → `on` is idempotent (does not spawn a second inhibitor)
  - `on` → `off` kills PID and reports `off`
  - `off` on empty state is a no-op success
  - `30m` schedules expiry; simulated PID death triggers stale cleanup on next `status`
  - `busy` alone does not spawn an inhibitor
  - `busy` + `--busy-event=start` spawns; `--busy-event=stop` tears down; mode=busy persists
  - `--busy-event=*` with mode=off is a no-op
  - Concurrent `on` invocations serialize via flock; only one PID winds up in state
  - Stale PID in state file is cleaned silently
  - Bare integer argument (`30`) is parsed as minutes
  - Invalid argument exits 1 with usage
  - Missing inhibitor binary exits 3 with install hint

**CI:** GitHub Actions matrix on `macos-latest` (real `caffeinate` available) and `ubuntu-latest` (mock inhibitor, since CI runners lack `systemd-inhibit` for an interactive session). Each runner installs `bats-core` and runs the suite.

**Manual smoke test (documented in README):**
1. Load with `--plugin-dir`.
2. `/keep-alive:keep-alive on`; run `pmset -g assertions` (macOS) or `systemd-inhibit --list` (Linux) to confirm the inhibit is registered.
3. `/keep-alive:keep-alive off`; confirm assertion is released.
4. `/keep-alive:keep-alive busy`; submit a prompt; assert inhibit appears during work and disappears after `Stop`.

## 11. Security and Privacy

- No network calls. No telemetry.
- Hooks execute on every prompt; the hook command is small, well-defined, and shipped within the plugin (no user-controlled string interpolation). State path is namespaced under the user's `$XDG_CACHE_HOME`.
- The shipped `bin/keep-alive` does only what the design specifies. Code review surface is small (~150 lines of POSIX sh).

## 12. Versioning and Release

- `version` field set explicitly in both `plugin.json` and `marketplace.json` (`0.1.0` initially). Users only receive updates when the version is bumped, not on every commit.
- Semantic versioning. Public release tags follow `v0.1.0`, `v0.2.0`, etc.
- Pre-release: tag `v0.1.0-rc.1` and dogfood by installing from the repo before tagging `v0.1.0`.

## 13. Out-of-Scope for v0.1 (Tracked for Later)

- Windows support (`SetThreadExecutionState` via PowerShell or `powercfg /requests` watchdog).
- Per-session inhibitor (would require passing `CLAUDE_SESSION_ID` from hooks and tracking N PIDs).
- Configurable inhibitor flags (e.g., let user choose `caffeinate -i` vs `-dis`).
- Notification when duration expires.
- A `/keep-alive:list` to enumerate active inhibitors across plugin versions.

## 14. Open Items Before Implementation

1. **GitHub username/org**: Plugin manifest and README contain `<github-user>` placeholders. Final repo URL determines these. Implementation plan should treat this as a one-line fill-in, not a code change.
2. **Hook event names**: This design assumes `UserPromptSubmit` and `Stop` are the right names. Implementation plan will verify against current Claude Code hook documentation; if they have changed, equivalent "session became busy" / "session became idle" events will be substituted.
3. **`allowed-tools` syntax in command frontmatter**: Design assumes JSON-array `["Bash"]`. Implementation plan will confirm exact frontmatter shape (some docs show whitespace-separated string). Choice does not affect overall design.
4. **Single command vs. shortcut commands**: Current design ships one slash command, invoked as `/keep-alive:keep-alive <args>` for full Copilot parity. An alternative is to additionally ship `on.md`, `off.md`, `busy.md`, `status.md` so users can type `/keep-alive:on`, `/keep-alive:off`, etc. Cleaner UX, costs four extra one-line markdown files. v0.1 ships only the parity command; shortcuts are deferred to v0.2 unless the user prefers them now.
