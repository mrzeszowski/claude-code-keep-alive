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

Claude Code plugin commands are namespaced as `/<plugin>:<command>`. Rather than a single dispatcher (which would force the awkward `/keep-alive:keep-alive ...`), the plugin ships one shortcut command per action. Duration folds naturally into `on` so the command reads as English: "turn it on for 30 minutes."

| User input                       | Behavior |
| -------------------------------- | -------- |
| `/keep-alive:status`             | Print current state (mode, time remaining if applicable, inhibitor PID). |
| `/keep-alive:on`                 | Inhibit sleep until `off` is invoked. |
| `/keep-alive:on <N>m`            | Inhibit for N minutes, then auto-release. |
| `/keep-alive:on <N>h`            | Inhibit for N hours, then auto-release. |
| `/keep-alive:on <N>d`            | Inhibit for N days, then auto-release. |
| `/keep-alive:on <N>`             | Bare number = minutes. |
| `/keep-alive:off`                | Release the inhibitor. |
| `/keep-alive:busy`               | Inhibit only while Claude is actively processing (started/stopped by hooks on `UserPromptSubmit`/`Stop`). |

This is a small, deliberate divergence from Copilot CLI's surface (`/keep-alive 30m` becomes `/keep-alive:on 30m`). The semantic mapping is one-to-one; only the verb-placement differs.

## 4. Architecture

Three pieces interact:

1. **Slash commands** (`commands/on.md`, `off.md`, `busy.md`, `status.md`) — four small markdown prompts, each restricted to the Bash tool. Each tells Claude to invoke the helper script with a fixed verb (`on`, `off`, `busy`, `status`) plus any `$ARGUMENTS` (used only by `on` for the optional duration). No logic, just dispatch.
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
│   ├── on.md                             /keep-alive:on [duration]
│   ├── off.md                            /keep-alive:off
│   ├── busy.md                           /keep-alive:busy
│   └── status.md                         /keep-alive:status
├── hooks/
│   └── hooks.json                        UserPromptSubmit + Stop integration
├── tests/
│   ├── test_keep_alive.bats              bats integration tests
│   └── mocks/
│       └── caffeinate                    fake inhibitor that just sleeps
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                        shellcheck + manifest validation + bats matrix
│   │   └── release.yml                   tag-driven GitHub release
│   ├── dependabot.yml                    weekly GitHub-Actions version updates
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
├── README.md                             install (marketplace) + usage + namespace explanation
├── CONTRIBUTING.md                       local-dev install, running tests
├── CHANGELOG.md                          Keep-a-Changelog
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
  "homepage": "https://github.com/mrzeszowski/claude-code-keep-alive",
  "repository": "https://github.com/mrzeszowski/claude-code-keep-alive",
  "license": "MIT"
}
```

The repo is hosted at `https://github.com/mrzeszowski/claude-code-keep-alive` (public).

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
      "homepage": "https://github.com/mrzeszowski/claude-code-keep-alive",
      "tags": ["productivity", "sleep", "caffeinate", "system"]
    }
  ]
}
```

Marketplace `name` matches the repo name. Install reads as `/plugin install {plugin-name}@{marketplace-name}` — once users see the pattern, the repetition is informative rather than awkward.

### 6.3 Slash command files

All four files share the same shape: tight frontmatter, a one-line instruction, `allowed-tools` locked to `Bash`. This prevents the LLM from wandering off into editing files or asking clarifying questions when the user just wanted to flip a toggle.

**`commands/on.md`**
```markdown
---
description: Prevent the machine from sleeping (optionally for a fixed duration)
argument-hint: "[<N>m | <N>h | <N>d | <N>]"
allowed-tools: ["Bash"]
---

Run `keep-alive on $ARGUMENTS` using the Bash tool and print its stdout/stderr
verbatim, with no commentary, no summarization, and no follow-up suggestions.
```

**`commands/off.md`**
```markdown
---
description: Release the keep-alive inhibitor and let the machine sleep normally
allowed-tools: ["Bash"]
---

Run `keep-alive off` using the Bash tool and print its stdout/stderr verbatim.
```

**`commands/busy.md`**
```markdown
---
description: Inhibit sleep only while Claude is actively processing
allowed-tools: ["Bash"]
---

Run `keep-alive busy` using the Bash tool and print its stdout/stderr verbatim.
```

**`commands/status.md`**
```markdown
---
description: Show current keep-alive state
allowed-tools: ["Bash"]
---

Run `keep-alive status` using the Bash tool and print its stdout/stderr verbatim.
```

### 6.4 `bin/keep-alive` — Behavior

**Argument grammar:**
- `` (empty) or `status` → print current state
- `on` → activate continuous inhibitor
- `on <N>[mhd]` (or bare `on <N>` → minutes) → activate inhibitor with auto-expiry
- `off` → release inhibitor, clear state
- `busy` → set mode=busy; hooks will start/stop the inhibitor
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

1. User types `/keep-alive:on`.
2. Claude's Bash tool runs `keep-alive on`.
3. Script takes flock, reads state (mode=off, no PID), spawns `caffeinate -dis` detached, records new PID, sets mode=on, releases flock.
4. Script prints `keep-alive: on (since ..., PID ...)`.
5. User closes laptop lid → display sleeps but system stays awake.
6. Later, user runs `/keep-alive:off`. Script kills PID, clears state, prints `keep-alive: off`.

### 7.2 `busy` mode across a long agent run

1. User types `/keep-alive:busy`. Script writes mode=busy. No inhibitor running yet.
2. User submits a prompt that triggers a long agent loop.
3. `UserPromptSubmit` hook fires → `keep-alive --busy-event=start`. Script sees mode=busy and no live PID → spawns inhibitor, saves PID.
4. Agent runs for 20 minutes, machine stays awake.
5. Agent stops, Claude returns control to user. `Stop` hook fires → `keep-alive --busy-event=stop`. Script kills PID, leaves mode=busy.
6. User reads output for 5 minutes; machine is free to sleep.
7. User submits next prompt. `UserPromptSubmit` fires → inhibitor starts again. Loop continues.
8. User runs `/keep-alive:off`. Script clears mode entirely; hooks become no-ops.

### 7.3 Duration mode

1. User types `/keep-alive:on 30m`.
2. Claude's Bash tool runs `keep-alive on 30m`.
3. Script spawns `timeout 1800 caffeinate -dis` detached, saves PID, sets mode=duration, expires_at=now+30m.
4. After 30 minutes, `timeout` kills `caffeinate`. Next `status` call notices the PID is gone, clears state, reports `off`.

## 8. Installation

### 8.1 Recommended (marketplace install) — the most popular path

Claude Code's native plugin manager is the standard distribution channel. Since this repository contains both `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json`, users can install with two short commands inside any Claude Code session:

```text
/plugin marketplace add mrzeszowski/claude-code-keep-alive
/plugin install keep-alive@claude-code-keep-alive
```

Behind the scenes Claude Code clones the repo into its plugin cache, reads the marketplace manifest, fetches the plugin source from `./`, and namespaces the four slash commands under `/keep-alive:`. Users get versioned updates whenever the `version` field is bumped — they pull with `/plugin update keep-alive@claude-code-keep-alive`.

The general form is `/plugin install {plugin-name}@{marketplace-name}`. Here both happen to share the `keep-alive` substring because the marketplace is a single-plugin one named after the repo, but they're independent labels: the plugin name (`keep-alive`) becomes the slash-command namespace (`/keep-alive:*`), while the marketplace name (`claude-code-keep-alive`) is just the label users type after `@`. The first line is GitHub shorthand that resolves to `https://github.com/mrzeszowski/claude-code-keep-alive`. The README prominently shows these two commands as the first thing users see.

### 8.2 Local development install

For hacking on the plugin itself:

```text
git clone git@github.com:mrzeszowski/claude-code-keep-alive.git
cd claude-code-keep-alive
claude --plugin-dir .
# then inside the session, after any change:
/reload-plugins
```

When a `--plugin-dir` plugin has the same name as an installed marketplace plugin, the local copy wins for that session, so you can iterate without uninstalling first.

### 8.3 First-run verification

```text
/keep-alive:status        # expect: keep-alive: off
/keep-alive:on            # expect: keep-alive: on (since ..., PID ...)
/keep-alive:off           # expect: keep-alive: off
```

## 9. Error Handling

| Condition                              | Behavior |
| -------------------------------------- | -------- |
| Unsupported OS (Windows v0.1, other)    | stderr message, exit 2. Slash command surfaces stderr to the user verbatim. |
| `caffeinate` / `systemd-inhibit` absent | stderr install hint, exit 3. |
| Invalid args (`keep-alive on 5x`)       | stderr usage, exit 1. |
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
  - `on 30m` schedules expiry; simulated PID death triggers stale cleanup on next `status`
  - `busy` alone does not spawn an inhibitor
  - `busy` + `--busy-event=start` spawns; `--busy-event=stop` tears down; mode=busy persists
  - `--busy-event=*` with mode=off is a no-op
  - Concurrent `on` invocations serialize via flock; only one PID winds up in state
  - Stale PID in state file is cleaned silently
  - Bare integer argument (`on 30`) is parsed as minutes
  - Invalid duration (`on 5x`) exits 1 with usage
  - Unknown verb (`keep-alive foo`) exits 1 with usage
  - Missing inhibitor binary exits 3 with install hint

**CI:** See §11 for the full GitHub Actions setup. In summary: shellcheck + JSON manifest validation on every push/PR, bats matrix on macOS + Ubuntu, tag-driven release workflow, weekly Dependabot for action versions.

**Manual smoke test (documented in README):**
1. Load with `--plugin-dir`.
2. `/keep-alive:on`; run `pmset -g assertions` (macOS) or `systemd-inhibit --list` (Linux) to confirm the inhibit is registered.
3. `/keep-alive:off`; confirm assertion is released.
4. `/keep-alive:busy`; submit a prompt; assert inhibit appears during work and disappears after `Stop`.

## 11. GitHub Actions Workflows

Workflows live under `.github/workflows/`. Three files, plus Dependabot config and standard repository chrome. The goal is to catch obvious breakage (shellcheck issues, broken JSON, failing tests) on every PR while staying lightweight enough that CI doesn't slow contribution to a shell-script plugin.

### 11.1 `.github/workflows/ci.yml` — lint + test on every push/PR

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Shellcheck bin/keep-alive
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: ./bin
          severity: warning
      - name: Validate plugin manifests are valid JSON
        run: |
          jq -e . .claude-plugin/plugin.json
          jq -e . .claude-plugin/marketplace.json
      - name: Validate hooks manifest
        run: jq -e . hooks/hooks.json
      - name: Validate command frontmatter parses as YAML
        run: |
          sudo apt-get update && sudo apt-get install -y yq
          for f in commands/*.md; do
            awk '/^---$/{c++;next} c==1' "$f" | yq -e .
          done
  test:
    needs: lint
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install bats
        uses: bats-core/bats-action@2.0.0
      - name: Run bats tests
        run: bats tests/
```

Rationale:
- **shellcheck** is the de facto linter for POSIX shell; running it at `warning` severity catches the bugs that actually bite without rejecting stylistic preferences.
- **Manifest validation** is the cheapest possible regression net for plugin.json/marketplace.json/hooks.json — a typo there breaks installs silently.
- **bats matrix** on ubuntu + macOS covers the two supported platforms. macOS runner uses real `caffeinate`; ubuntu uses the mock (no `systemd-inhibit` in non-interactive CI).
- **Concurrency** cancels superseded runs on rapid pushes, saving CI minutes.
- **Permissions** start at `read`-only and are widened per-job only when needed.

### 11.2 `.github/workflows/release.yml` — tag-driven GitHub releases

```yaml
name: Release
on:
  push:
    tags: ['v*.*.*']
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify plugin.json version matches tag
        run: |
          TAG="${GITHUB_REF_NAME#v}"
          MANIFEST=$(jq -r .version .claude-plugin/plugin.json)
          if [ "$TAG" != "$MANIFEST" ]; then
            echo "Tag $TAG does not match plugin.json version $MANIFEST" >&2
            exit 1
          fi
      - name: Create GitHub release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          draft: false
          prerelease: ${{ contains(github.ref_name, '-') }}
```

Rationale:
- Plugin updates are gated by the `version` field in `plugin.json`, not by tags. The release workflow exists for *visibility* (release notes, changelog, GitHub's "Releases" tab) and to enforce that the tag and manifest version stay in sync — a common foot-gun for plugin authors.
- Pre-release detection (any tag containing `-`, e.g. `v0.1.0-rc.1`) is automatic.

### 11.3 `.github/dependabot.yml` — weekly action updates

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
```

Keeps `actions/checkout`, `softprops/action-gh-release`, etc. current without manual chasing.

### 11.4 Repository chrome

| File | Purpose |
| ---- | ------- |
| `.github/PULL_REQUEST_TEMPLATE.md` | Checklist: tests pass, version bumped, README updated, manual smoke test done. |
| `.github/ISSUE_TEMPLATE/bug_report.md` | OS, Claude Code version, output of `/keep-alive:status`, reproduction steps. |
| `.github/ISSUE_TEMPLATE/feature_request.md` | Lightweight, optional. |
| `CONTRIBUTING.md` | How to run tests locally, how to test the plugin with `--plugin-dir`. |
| `CHANGELOG.md` | Keep-a-Changelog format, populated per release. |
| `LICENSE` | MIT. |

### 11.5 Branch protection (configured in GitHub UI, documented in CONTRIBUTING.md)

- Require `lint` and `test` checks to pass before merging to `main`.
- Require linear history (rebase or squash; no merge commits).
- Require pull request reviews for changes to `main`.

## 12. Security and Privacy

- No network calls. No telemetry.
- Hooks execute on every prompt; the hook command is small, well-defined, and shipped within the plugin (no user-controlled string interpolation). State path is namespaced under the user's `$XDG_CACHE_HOME`.
- The shipped `bin/keep-alive` does only what the design specifies. Code review surface is small (~150 lines of POSIX sh).
- Workflows pin third-party actions to versioned tags (e.g., `@v4`, `@v2`) and use the minimum `permissions:` scope each job needs.

## 13. Versioning and Release

- `version` field set explicitly in both `plugin.json` and `marketplace.json` (`0.1.0` initially). Users only receive updates when the version is bumped, not on every commit.
- Semantic versioning. Public release tags follow `v0.1.0`, `v0.2.0`, etc.
- Pre-release: tag `v0.1.0-rc.1` and dogfood by installing from the repo before tagging `v0.1.0`.
- `release.yml` (§11.2) enforces tag-to-manifest version parity.

## 14. Out-of-Scope for v0.1 (Tracked for Later)

- Windows support (`SetThreadExecutionState` via PowerShell or `powercfg /requests` watchdog).
- Per-session inhibitor (would require passing `CLAUDE_SESSION_ID` from hooks and tracking N PIDs).
- Configurable inhibitor flags (e.g., let user choose `caffeinate -i` vs `-dis`).
- Notification when duration expires.
- A `/keep-alive:list` to enumerate active inhibitors across plugin versions.
- Submission to the official Anthropic plugin marketplace (post-v0.1, once the plugin has dogfood mileage).

## 15. Open Items Before Implementation

1. **Hook event names**: This design assumes `UserPromptSubmit` and `Stop` are the right names. Implementation plan will verify against current Claude Code hook documentation; if they have changed, equivalent "session became busy" / "session became idle" events will be substituted.
2. **`allowed-tools` syntax in command frontmatter**: Design assumes JSON-array `["Bash"]`. Implementation plan will confirm exact frontmatter shape (some docs show whitespace-separated string). Choice does not affect overall design.
