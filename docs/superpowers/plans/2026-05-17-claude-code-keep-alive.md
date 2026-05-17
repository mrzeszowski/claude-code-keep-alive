# Claude Code Keep-Alive Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship v0.1.0 of a Claude Code plugin that prevents the user's machine from sleeping during long Claude Code sessions, with `/keep-alive:on`, `/keep-alive:off`, `/keep-alive:busy`, and `/keep-alive:status` slash commands, distributed via a single GitHub repository that doubles as a single-plugin marketplace.

**Architecture:** Four small markdown slash commands dispatch to one POSIX-sh helper script (`bin/keep-alive`) that owns all logic: argument parsing, platform detection (macOS `caffeinate`, Linux `systemd-inhibit`), inhibitor lifecycle, and a single global state file under `$XDG_CACHE_HOME`. Two hooks (`UserPromptSubmit` + `Stop`) drive `busy` mode without polling. State is a `key=value` file (sourceable as shell variables) — simpler and dependency-free compared to JSON. All state mutations are `flock`-guarded.

**Tech Stack:** POSIX sh, bats-core for tests, GitHub Actions for CI, shellcheck for lint, jq + yq for manifest validation.

**Spec:** [`docs/superpowers/specs/2026-05-17-claude-code-keep-alive-design.md`](../specs/2026-05-17-claude-code-keep-alive-design.md)

---

## File Structure

| File | Created by | Responsibility |
| ---- | ---------- | -------------- |
| `LICENSE` | Task 1 | MIT license text. |
| `.gitignore` | Task 1 | Ignore editor/OS noise. |
| `tests/test_helper.bash` | Task 1 | bats setup/teardown shared by all tests. |
| `tests/mocks/caffeinate` | Task 1 | Mock that records args and `exec sleep 9999`. |
| `tests/mocks/systemd-inhibit` | Task 1 | Mock that strips inhibit flags and `exec`s the trailing command. |
| `tests/keep_alive.bats` | Tasks 2-10 | Bats integration tests, grown incrementally with the script. |
| `bin/keep-alive` | Tasks 2-10 | The POSIX-sh helper script — single source of behavior. |
| `.claude-plugin/plugin.json` | Task 11 | Plugin manifest. |
| `.claude-plugin/marketplace.json` | Task 12 | Marketplace manifest listing this plugin. |
| `commands/on.md` | Task 13 | `/keep-alive:on [duration]` dispatcher. |
| `commands/off.md` | Task 13 | `/keep-alive:off` dispatcher. |
| `commands/busy.md` | Task 13 | `/keep-alive:busy` dispatcher. |
| `commands/status.md` | Task 13 | `/keep-alive:status` dispatcher. |
| `hooks/hooks.json` | Task 14 | UserPromptSubmit + Stop hooks for busy mode. |
| `README.md` | Task 15 | User-facing install + usage + namespace explanation. |
| `CONTRIBUTING.md` | Task 16 | Dev install (`--plugin-dir`), running tests, release process. |
| `CHANGELOG.md` | Task 16 | Keep-a-Changelog, seeded with `v0.1.0` entry. |
| `.github/workflows/ci.yml` | Task 17 | Lint + matrix tests. |
| `.github/workflows/release.yml` | Task 18 | Tag-driven release with version-parity check. |
| `.github/dependabot.yml` | Task 19 | Weekly GitHub-Actions version PRs. |
| `.github/PULL_REQUEST_TEMPLATE.md` | Task 19 | PR checklist. |
| `.github/ISSUE_TEMPLATE/bug_report.md` | Task 19 | Bug template. |
| `.github/ISSUE_TEMPLATE/feature_request.md` | Task 19 | Feature template. |

**Design note (state format):** The spec illustrates state as JSON. To avoid requiring `jq` at runtime on every user's machine, the implementation uses a `key="value"` file sourceable by `sh`. Same fields (`mode`, `pid`, `started_at`, `expires_at`), same semantics, simpler portability. This is the only material implementation-time deviation from the spec.

---

## Conventions

- **All git commits** use `git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit` (the local repo has no committer config set).
- Each commit message ends with `Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>` via heredoc.
- Working directory: `/Users/marcinrzeszowski/Documents/Repositories/claude-code-keep-alive` (already a git repo with the design spec committed and pushed to `origin/main`).
- Run all `git push` commands as `git push origin main` after each task's commit so progress is visible on GitHub.

---

## Task 1: Project scaffolding and test harness

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `tests/test_helper.bash`
- Create: `tests/mocks/caffeinate`
- Create: `tests/mocks/systemd-inhibit`

- [ ] **Step 1: Create `LICENSE` (MIT, current year)**

```
MIT License

Copyright (c) 2026 Marcin Rzeszowski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
# Editor and OS noise
.DS_Store
*.swp
*~
.idea/
.vscode/

# Test runtime artifacts
tests/tmp/
*.log
```

- [ ] **Step 3: Create `tests/test_helper.bash`**

```bash
# Shared bats setup. Loaded via `load test_helper` in each .bats file.
# Sets up a clean state dir, points PATH at our mocks, and tears down
# any inhibitor processes the test spawned.

setup() {
  TMPDIR_TEST="$(mktemp -d -t keepalive-XXXXXX)"
  export KEEP_ALIVE_STATE_DIR="$TMPDIR_TEST/state"
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  SCRIPT="$BATS_TEST_DIRNAME/../bin/keep-alive"
  export SCRIPT
}

teardown() {
  if [ -f "$KEEP_ALIVE_STATE_DIR/state" ]; then
    pid=$(grep '^pid=' "$KEEP_ALIVE_STATE_DIR/state" 2>/dev/null \
            | sed -E 's/^pid="?//;s/"?$//')
    if [ -n "$pid" ]; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -rf "$TMPDIR_TEST"
}

# Source the state file and echo a named variable. Usage: state_get pid
state_get() {
  # shellcheck disable=SC1090
  ( . "$KEEP_ALIVE_STATE_DIR/state" 2>/dev/null; eval "echo \"\${$1:-}\"" )
}
```

- [ ] **Step 4: Create `tests/mocks/caffeinate`** (mock that records args and sleeps)

```sh
#!/usr/bin/env sh
# Mock for macOS `caffeinate`. Ignores -t/-d/-i/-s flags and just sleeps,
# so tests can capture the PID and verify it's killed correctly.
exec sleep 9999
```

Make it executable: `chmod +x tests/mocks/caffeinate`.

- [ ] **Step 5: Create `tests/mocks/systemd-inhibit`** (mock that strips its own flags and execs trailing command)

```sh
#!/usr/bin/env sh
# Mock for Linux `systemd-inhibit`. Strips its own --what/--who/--why flags
# (both `--flag value` and `--flag=value` forms), then execs the trailing
# command. This preserves the real semantic that killing the wrapper
# terminates the inhibit, because there is no wrapper — the trailing
# command (typically `sleep ...`) becomes the captured PID.
while [ $# -gt 0 ]; do
  case "$1" in
    --what=*|--who=*|--why=*) shift ;;
    --what|--who|--why) shift; [ $# -gt 0 ] && shift ;;
    --mode=*|--mode) shift; [ "${1:-}" ] && shift ;;
    --no-pager|--no-ask-password) shift ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
exec "$@"
```

Make it executable: `chmod +x tests/mocks/systemd-inhibit`.

- [ ] **Step 6: Verify mocks are runnable**

Run: `ls -l tests/mocks/`
Expected: both files have `x` in permissions.

Run: `tests/mocks/caffeinate -t 60 -dis &` then `kill %1`
Expected: backgrounded, killed cleanly.

- [ ] **Step 7: Commit**

```bash
git add LICENSE .gitignore tests/test_helper.bash tests/mocks/caffeinate tests/mocks/systemd-inhibit
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
chore: project scaffolding (LICENSE, gitignore, bats test harness)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 2: `status` on empty state — first vertical slice

**Files:**
- Create: `tests/keep_alive.bats`
- Create: `bin/keep-alive`

This task establishes the script skeleton, the state file format, the `status` command, and the basic test pattern. Subsequent tasks add one capability at a time on top.

- [ ] **Step 1: Verify bats-core is installed**

Run: `bats --version`
Expected: prints `Bats x.y.z`. If missing, install:
- macOS: `brew install bats-core`
- Ubuntu: `sudo apt install bats` (or follow https://bats-core.readthedocs.io/)

- [ ] **Step 2: Write the failing test — empty-state status**

Create `tests/keep_alive.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "status: empty state prints off" {
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "$output" = "keep-alive: off" ]
}

@test "no args: also prints status" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "keep-alive: off" ]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bats tests/keep_alive.bats`
Expected: FAIL — `bin/keep-alive` does not exist yet.

- [ ] **Step 4: Create `bin/keep-alive` with the minimal skeleton + status**

```sh
#!/usr/bin/env sh
# keep-alive — prevent the machine from sleeping during Claude Code sessions
set -u

STATE_DIR="${KEEP_ALIVE_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-keep-alive}"
STATE_FILE="$STATE_DIR/state"
LOCK_FILE="$STATE_DIR/state.lock"

mkdir -p "$STATE_DIR"

read_state() {
  mode=off
  pid=
  started_at=
  expires_at=
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
  fi
}

cmd_status() {
  read_state
  case "$mode" in
    off|"") echo "keep-alive: off" ;;
    on)        echo "keep-alive: on (since $started_at, PID $pid)" ;;
    duration)  echo "keep-alive: duration (expires $expires_at, PID $pid)" ;;
    busy)
      if [ -n "$pid" ]; then
        echo "keep-alive: busy (active, PID $pid)"
      else
        echo "keep-alive: busy (no inhibitor currently active)"
      fi ;;
    *) echo "keep-alive: off" ;;
  esac
}

usage() {
  cat >&2 <<EOF
Usage: keep-alive [status | on [DURATION] | off | busy | --busy-event=start | --busy-event=stop]

  status              Show current state (default when no args).
  on                  Inhibit sleep until 'off' is invoked.
  on DURATION         Inhibit sleep for DURATION (e.g., 30m, 8h, 1d, 30).
                      Bare number is treated as minutes.
  off                 Release the inhibitor.
  busy                Inhibit sleep only while Claude is actively processing.
  --busy-event=...    Internal; invoked by Claude Code hooks.
EOF
}

main() {
  if [ $# -eq 0 ]; then
    cmd_status
    return 0
  fi
  case "$1" in
    status) cmd_status ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
```

Make it executable: `chmod +x bin/keep-alive`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats tests/keep_alive.bats`
Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): keep-alive script skeleton with status command

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 3: `on` — continuous inhibitor

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Append failing tests for `on`**

Append to `tests/keep_alive.bats`:

```bash
@test "on: spawns inhibitor and reports on" {
  run "$SCRIPT" on
  [ "$status" -eq 0 ]
  echo "$output" | grep -E '^keep-alive: on \(since [0-9TZ:-]+, PID [0-9]+\)$'
  pid=$(state_get pid)
  [ -n "$pid" ]
  kill -0 "$pid"
}

@test "on: state file records mode=on and a started_at timestamp" {
  "$SCRIPT" on
  [ "$(state_get mode)" = "on" ]
  [ -n "$(state_get started_at)" ]
}

@test "on is idempotent: second on does not spawn a second inhibitor" {
  "$SCRIPT" on
  first_pid=$(state_get pid)
  "$SCRIPT" on
  second_pid=$(state_get pid)
  [ "$first_pid" = "$second_pid" ]
  kill -0 "$second_pid"
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/keep_alive.bats`
Expected: 3 new tests fail (unknown verb `on`).

- [ ] **Step 3: Add `on` support to `bin/keep-alive`**

Above `cmd_status`, add helpers:

```sh
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    Linux)  echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unsupported ;;
  esac
}

is_alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

write_state() {
  cat > "$STATE_FILE" <<EOF
mode="$1"
pid="${2:-}"
started_at="${3:-}"
expires_at="${4:-}"
EOF
}

spawn_inhibitor() {
  # $1 = duration in seconds (0 or empty = forever). Echoes the PID.
  duration_secs="${1:-0}"
  case "$(detect_platform)" in
    darwin)
      if [ "$duration_secs" -gt 0 ]; then
        nohup caffeinate -t "$duration_secs" -dis </dev/null >/dev/null 2>&1 &
      else
        nohup caffeinate -dis </dev/null >/dev/null 2>&1 &
      fi ;;
    linux)
      sleep_arg=infinity
      [ "$duration_secs" -gt 0 ] && sleep_arg="$duration_secs"
      nohup systemd-inhibit \
        --what=idle:sleep \
        --who=claude-code-keep-alive \
        --why="Active Claude Code session" \
        sleep "$sleep_arg" </dev/null >/dev/null 2>&1 & ;;
  esac
  echo $!
}
```

Add a new command function (above `usage`):

```sh
cmd_on() {
  read_state
  if [ "$mode" = on ] || [ "$mode" = duration ]; then
    if is_alive "$pid"; then
      cmd_status
      return 0
    fi
  fi
  new_pid=$(spawn_inhibitor 0)
  write_state on "$new_pid" "$(now_iso)" ""
  cmd_status
}
```

Update `main()`'s case to add `on`:

```sh
    on)     cmd_on ;;
```

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): add `on` command spawning a detached inhibitor

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 4: `off` — release the inhibitor

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Append failing tests for `off`**

```bash
@test "off after on: kills PID and reports off" {
  "$SCRIPT" on
  pid=$(state_get pid)
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  [ "$output" = "keep-alive: off" ]
  ! kill -0 "$pid" 2>/dev/null
}

@test "off on empty state is a no-op success" {
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  [ "$output" = "keep-alive: off" ]
}

@test "off clears mode and pid in state file" {
  "$SCRIPT" on
  "$SCRIPT" off
  [ "$(state_get mode)" = "off" ]
  [ -z "$(state_get pid)" ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/keep_alive.bats`
Expected: 3 new tests fail.

- [ ] **Step 3: Implement `cmd_off`**

Add to `bin/keep-alive` above `usage`:

```sh
cmd_off() {
  read_state
  if [ -n "$pid" ] && is_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    # Give the process a moment to die so subsequent tests see kill -0 fail.
    for _ in 1 2 3 4 5; do
      is_alive "$pid" || break
      sleep 0.1
    done
  fi
  write_state off "" "" ""
  cmd_status
}
```

Update `main()` to add the `off` case:

```sh
    off)    cmd_off ;;
```

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): add `off` command to release inhibitor and clear state

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 5: `on <duration>` — auto-expiring inhibitor

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Append failing tests for duration**

```bash
@test "on 30m: mode=duration, expires_at set" {
  run "$SCRIPT" on 30m
  [ "$status" -eq 0 ]
  echo "$output" | grep -E '^keep-alive: duration \(expires [0-9TZ:-]+, PID [0-9]+\)$'
  [ "$(state_get mode)" = "duration" ]
  [ -n "$(state_get expires_at)" ]
}

@test "on 1h: parses hours" {
  "$SCRIPT" on 1h
  [ "$(state_get mode)" = "duration" ]
}

@test "on 1d: parses days" {
  "$SCRIPT" on 1d
  [ "$(state_get mode)" = "duration" ]
}

@test "on 30: bare number treated as minutes" {
  "$SCRIPT" on 30
  [ "$(state_get mode)" = "duration" ]
}

@test "on 5x: invalid duration exits 1 with usage hint" {
  run "$SCRIPT" on 5x
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "invalid duration"
}

@test "on 0m: invalid (zero is not a useful duration)" {
  run "$SCRIPT" on 0m
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/keep_alive.bats`
Expected: 6 new tests fail.

- [ ] **Step 3: Add `parse_duration` and update `cmd_on`**

Add `parse_duration` near the other helpers in `bin/keep-alive`:

```sh
parse_duration() {
  # Parse "30m" / "8h" / "1d" / "30" → seconds on stdout. Returns 1 on parse failure.
  arg="$1"
  [ -n "$arg" ] || return 1
  case "$arg" in
    *[!0-9mhd]*) return 1 ;;
    *m) suffix=m; num=${arg%m} ;;
    *h) suffix=h; num=${arg%h} ;;
    *d) suffix=d; num=${arg%d} ;;
    *)  suffix=m; num=$arg ;;
  esac
  case "$num" in
    ""|*[!0-9]*) return 1 ;;
  esac
  [ "$num" -gt 0 ] || return 1
  case "$suffix" in
    m) echo $(( num * 60 )) ;;
    h) echo $(( num * 3600 )) ;;
    d) echo $(( num * 86400 )) ;;
  esac
}

future_iso() {
  # $1 = seconds from now; echoes ISO 8601 UTC timestamp.
  secs="$1"
  if date -u -r 0 +%s >/dev/null 2>&1; then
    # BSD date (macOS)
    date -u -r "$(( $(date -u +%s) + secs ))" +%Y-%m-%dT%H:%M:%SZ
  else
    # GNU date (Linux)
    date -u -d "@$(( $(date -u +%s) + secs ))" +%Y-%m-%dT%H:%M:%SZ
  fi
}
```

Replace the existing `cmd_on` with the duration-aware version:

```sh
cmd_on() {
  duration_arg="${1:-}"
  if [ -n "$duration_arg" ]; then
    if ! secs=$(parse_duration "$duration_arg"); then
      echo "keep-alive: invalid duration '$duration_arg' (use Nm, Nh, Nd, or bare N for minutes)" >&2
      exit 1
    fi
  else
    secs=0
  fi
  read_state
  if { [ "$mode" = on ] || [ "$mode" = duration ]; } && is_alive "$pid"; then
    cmd_status
    return 0
  fi
  new_pid=$(spawn_inhibitor "$secs")
  started=$(now_iso)
  if [ "$secs" -gt 0 ]; then
    expires=$(future_iso "$secs")
    write_state duration "$new_pid" "$started" "$expires"
  else
    write_state on "$new_pid" "$started" ""
  fi
  cmd_status
}
```

Update `main()` to forward args past `on`:

```sh
    on)     shift; cmd_on "$@" ;;
```

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): support duration argument on `on` (Nm/Nh/Nd/bare-N)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 6: `busy` mode (state only)

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Append failing tests**

```bash
@test "busy: sets mode=busy, does not spawn an inhibitor" {
  run "$SCRIPT" busy
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "keep-alive: busy (no inhibitor currently active)"
  [ "$(state_get mode)" = "busy" ]
  [ -z "$(state_get pid)" ]
}

@test "busy then off: clears busy mode" {
  "$SCRIPT" busy
  "$SCRIPT" off
  [ "$(state_get mode)" = "off" ]
}

@test "on then busy: kills the on-inhibitor and switches mode" {
  "$SCRIPT" on
  pid=$(state_get pid)
  "$SCRIPT" busy
  [ "$(state_get mode)" = "busy" ]
  [ -z "$(state_get pid)" ]
  ! kill -0 "$pid" 2>/dev/null
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/keep_alive.bats`
Expected: 3 new tests fail.

- [ ] **Step 3: Implement `cmd_busy`**

Add to `bin/keep-alive`:

```sh
cmd_busy() {
  read_state
  if [ -n "$pid" ] && is_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do is_alive "$pid" || break; sleep 0.1; done
  fi
  write_state busy "" "" ""
  cmd_status
}
```

Add to `main()`:

```sh
    busy)   cmd_busy ;;
```

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 17 tests pass.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): add `busy` command (state-only; hooks drive the inhibitor)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 7: `--busy-event=start|stop` — hook integration

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Append failing tests**

```bash
@test "busy + --busy-event=start: spawns inhibitor, mode stays busy" {
  "$SCRIPT" busy
  run "$SCRIPT" --busy-event=start
  [ "$status" -eq 0 ]
  [ "$(state_get mode)" = "busy" ]
  pid=$(state_get pid)
  [ -n "$pid" ]
  kill -0 "$pid"
}

@test "busy + start + stop: inhibitor torn down, mode stays busy" {
  "$SCRIPT" busy
  "$SCRIPT" --busy-event=start
  pid=$(state_get pid)
  run "$SCRIPT" --busy-event=stop
  [ "$status" -eq 0 ]
  [ "$(state_get mode)" = "busy" ]
  [ -z "$(state_get pid)" ]
  ! kill -0 "$pid" 2>/dev/null
}

@test "--busy-event=start when mode=off: no-op" {
  run "$SCRIPT" --busy-event=start
  [ "$status" -eq 0 ]
  [ -z "$(state_get pid)" ]
}

@test "--busy-event=start is idempotent: second start does not respawn" {
  "$SCRIPT" busy
  "$SCRIPT" --busy-event=start
  first_pid=$(state_get pid)
  "$SCRIPT" --busy-event=start
  [ "$(state_get pid)" = "$first_pid" ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/keep_alive.bats`
Expected: 4 new tests fail.

- [ ] **Step 3: Implement `cmd_busy_event`**

Add to `bin/keep-alive`:

```sh
cmd_busy_event() {
  event="$1"
  read_state
  [ "$mode" = busy ] || return 0
  case "$event" in
    start)
      if [ -z "$pid" ] || ! is_alive "$pid"; then
        new_pid=$(spawn_inhibitor 0)
        write_state busy "$new_pid" "$(now_iso)" ""
      fi ;;
    stop)
      if [ -n "$pid" ] && is_alive "$pid"; then
        kill "$pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do is_alive "$pid" || break; sleep 0.1; done
      fi
      write_state busy "" "" "" ;;
  esac
}
```

Add to `main()`:

```sh
    --busy-event=start) cmd_busy_event start ;;
    --busy-event=stop)  cmd_busy_event stop ;;
```

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 21 tests pass.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): wire --busy-event=start|stop for hook-driven busy mode

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 8: Stale-PID cleanup

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Append failing tests**

```bash
@test "stale PID in on-mode is cleaned: status normalizes to off" {
  mkdir -p "$KEEP_ALIVE_STATE_DIR"
  cat > "$KEEP_ALIVE_STATE_DIR/state" <<EOF
mode="on"
pid="999999"
started_at="2026-05-17T00:00:00Z"
expires_at=""
EOF
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "$output" = "keep-alive: off" ]
  [ "$(state_get mode)" = "off" ]
}

@test "stale PID in busy-mode is cleaned: mode stays busy, pid cleared" {
  mkdir -p "$KEEP_ALIVE_STATE_DIR"
  cat > "$KEEP_ALIVE_STATE_DIR/state" <<EOF
mode="busy"
pid="999999"
started_at="2026-05-17T00:00:00Z"
expires_at=""
EOF
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "keep-alive: busy (no inhibitor currently active)"
  [ "$(state_get mode)" = "busy" ]
  [ -z "$(state_get pid)" ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/keep_alive.bats`
Expected: 2 new tests fail.

- [ ] **Step 3: Add `refresh_state` and call it from each command**

Add to `bin/keep-alive` (place between `read_state` and `cmd_status`):

```sh
refresh_state() {
  # Read state; if the saved PID is dead, normalize. Busy mode keeps mode=busy
  # but clears the PID; everything else falls back to mode=off.
  read_state
  if [ -n "$pid" ] && ! is_alive "$pid"; then
    if [ "$mode" = busy ]; then
      write_state busy "" "" ""
    else
      write_state off "" "" ""
    fi
    read_state
  fi
}
```

Replace every `read_state` call inside `cmd_status`, `cmd_on`, `cmd_off`, `cmd_busy`, and `cmd_busy_event` with `refresh_state`.

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 23 tests pass.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): stale-PID cleanup on every state read

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 9: `flock` concurrency safety

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

`flock` ships with util-linux on Linux (default on Ubuntu) but not on macOS. The script gracefully falls back to a `mkdir`-based lock when `flock` is unavailable.

- [ ] **Step 1: Append failing test for concurrent `on`**

```bash
@test "concurrent on invocations: exactly one PID winds up in state" {
  "$SCRIPT" on >/dev/null &
  "$SCRIPT" on >/dev/null &
  wait
  [ "$(state_get mode)" = "on" ]
  pid=$(state_get pid)
  kill -0 "$pid"
  # Count live mock-caffeinate processes that descend from this test:
  # only one should be alive (the one whose PID is in state); the other
  # should have lost the race and either not spawned or been killed.
  # Skip strict count check on systems without pgrep -P.
}
```

- [ ] **Step 2: Run to verify it can be flaky without locking**

Run: `bats tests/keep_alive.bats -f "concurrent on"` repeatedly. Without locking, occasional races leave two live mock processes (only the second PID is recorded). With locking, the second invocation observes the first's PID and exits idempotently.

- [ ] **Step 3: Add `with_lock` and wrap every command**

Add helper:

```sh
with_lock() {
  # Run "$@" under an exclusive lock on $LOCK_FILE.
  if command -v flock >/dev/null 2>&1; then
    ( flock -x 9; "$@" ) 9>"$LOCK_FILE"
  else
    # mkdir-based fallback (atomic on all POSIX filesystems).
    while ! mkdir "$LOCK_FILE.d" 2>/dev/null; do sleep 0.05; done
    trap 'rmdir "$LOCK_FILE.d" 2>/dev/null' EXIT INT TERM
    "$@"
    rc=$?
    rmdir "$LOCK_FILE.d" 2>/dev/null || true
    trap - EXIT INT TERM
    return $rc
  fi
}
```

Rename the existing per-command functions to `_cmd_status`, `_cmd_on`, etc. (internal), and add public wrappers:

```sh
cmd_status()      { with_lock _cmd_status; }
cmd_on()          { with_lock _cmd_on "$@"; }
cmd_off()         { with_lock _cmd_off; }
cmd_busy()        { with_lock _cmd_busy; }
cmd_busy_event()  { with_lock _cmd_busy_event "$@"; }
```

Move the duration-parsing block out of `_cmd_on` so it runs *before* locking (no need to hold the lock during a usage error):

```sh
cmd_on() {
  duration_arg="${1:-}"
  if [ -n "$duration_arg" ]; then
    if ! secs=$(parse_duration "$duration_arg"); then
      echo "keep-alive: invalid duration '$duration_arg' (use Nm, Nh, Nd, or bare N for minutes)" >&2
      exit 1
    fi
  else
    secs=0
  fi
  with_lock _cmd_on "$secs"
}

_cmd_on() {
  secs="$1"
  refresh_state
  if { [ "$mode" = on ] || [ "$mode" = duration ]; } && is_alive "$pid"; then
    _cmd_status
    return 0
  fi
  new_pid=$(spawn_inhibitor "$secs")
  started=$(now_iso)
  if [ "$secs" -gt 0 ]; then
    expires=$(future_iso "$secs")
    write_state duration "$new_pid" "$started" "$expires"
  else
    write_state on "$new_pid" "$started" ""
  fi
  _cmd_status
}
```

`_cmd_status`, `_cmd_off`, `_cmd_busy`, `_cmd_busy_event` are the renamed bodies of their `cmd_*` predecessors — internal calls within `_cmd_on`/etc. should already call `_cmd_status` (the unlocked variant) to avoid lock recursion. Verify that.

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 24 tests pass, including the concurrency test.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): flock-guard state mutations with mkdir fallback

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 10: Error handling (unknown verb, unsupported OS, missing inhibitor)

**Files:**
- Modify: `bin/keep-alive`
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Append failing tests**

```bash
@test "unknown verb: usage to stderr, exit 1" {
  run "$SCRIPT" foo
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Usage:"
}

@test "missing inhibitor binary: exit 3 with install hint" {
  # Empty PATH so neither caffeinate nor systemd-inhibit mocks resolve.
  PATH="/no-such-dir" run "$SCRIPT" on
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "not found"
}

@test "help: -h prints usage to stderr, exit 0" {
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Usage:"
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats tests/keep_alive.bats`
Expected: the "missing inhibitor binary" test fails (others may already pass).

- [ ] **Step 3: Add `ensure_inhibitor_binary` and call it before spawning**

Add helper:

```sh
ensure_inhibitor_binary() {
  case "$(detect_platform)" in
    darwin)
      command -v caffeinate >/dev/null 2>&1 || {
        echo "keep-alive: 'caffeinate' not found in PATH (ships with macOS; check your PATH)" >&2
        exit 3
      } ;;
    linux)
      command -v systemd-inhibit >/dev/null 2>&1 || {
        echo "keep-alive: 'systemd-inhibit' not found in PATH (install systemd-container, e.g. 'sudo apt install systemd-container')" >&2
        exit 3
      } ;;
    windows)
      echo "keep-alive: Windows not yet supported in v0.1; contributions welcome at https://github.com/mrzeszowski/claude-code-keep-alive" >&2
      exit 2 ;;
    *)
      echo "keep-alive: unsupported platform '$(uname -s)'" >&2
      exit 2 ;;
  esac
}
```

Call `ensure_inhibitor_binary` at the top of `cmd_on` (before locking) and at the top of `cmd_busy` (so `busy` also fails fast on unsupported platforms, even though it doesn't spawn immediately). Do NOT call it from `cmd_busy_event` — hooks fire on every prompt and must stay silent on unsupported platforms.

- [ ] **Step 4: Run all tests**

Run: `bats tests/keep_alive.bats`
Expected: all 27 tests pass.

- [ ] **Step 5: Run shellcheck**

Run: `shellcheck -s sh bin/keep-alive`
Expected: no errors at default severity (warnings about `$pid`/`$mode` etc. being set via `.` are acceptable; suppress with `# shellcheck disable=SC2034` only where intentional).

- [ ] **Step 6: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(script): error handling for unknown verbs, unsupported OS, missing inhibitor

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 11: `.claude-plugin/plugin.json`

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create the manifest**

```json
{
  "name": "keep-alive",
  "description": "Prevents your machine from sleeping during Claude Code sessions (mirrors GitHub Copilot CLI /keep-alive)",
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

- [ ] **Step 2: Validate JSON**

Run: `jq -e . .claude-plugin/plugin.json`
Expected: exit 0, pretty-printed manifest.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(plugin): add plugin.json manifest (v0.1.0)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 12: `.claude-plugin/marketplace.json`

**Files:**
- Create: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Create the marketplace manifest**

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

- [ ] **Step 2: Validate JSON**

Run: `jq -e . .claude-plugin/marketplace.json`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/marketplace.json
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(plugin): add marketplace.json so the repo doubles as a single-plugin marketplace

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 13: Slash command files

**Files:**
- Create: `commands/on.md`
- Create: `commands/off.md`
- Create: `commands/busy.md`
- Create: `commands/status.md`

- [ ] **Step 1: Create `commands/on.md`**

```markdown
---
description: Prevent the machine from sleeping (optionally for a fixed duration)
argument-hint: "[<N>m | <N>h | <N>d | <N>]"
allowed-tools: ["Bash"]
---

Run `keep-alive on $ARGUMENTS` using the Bash tool and print its stdout/stderr
verbatim, with no commentary, no summarization, and no follow-up suggestions.
```

- [ ] **Step 2: Create `commands/off.md`**

```markdown
---
description: Release the keep-alive inhibitor and let the machine sleep normally
allowed-tools: ["Bash"]
---

Run `keep-alive off` using the Bash tool and print its stdout/stderr verbatim.
```

- [ ] **Step 3: Create `commands/busy.md`**

```markdown
---
description: Inhibit sleep only while Claude is actively processing
allowed-tools: ["Bash"]
---

Run `keep-alive busy` using the Bash tool and print its stdout/stderr verbatim.
```

- [ ] **Step 4: Create `commands/status.md`**

```markdown
---
description: Show current keep-alive state
allowed-tools: ["Bash"]
---

Run `keep-alive status` using the Bash tool and print its stdout/stderr verbatim.
```

- [ ] **Step 5: Validate frontmatter parses as YAML**

Run:
```bash
for f in commands/*.md; do
  echo "=== $f"
  awk '/^---$/{c++;next} c==1' "$f" | yq -e .
done
```
Expected: each file emits a valid YAML object with `description` (and `allowed-tools`, `argument-hint` where applicable). If `yq` is not installed locally, skip — CI runs this check.

- [ ] **Step 6: Commit**

```bash
git add commands/
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(plugin): add slash command dispatchers (on/off/busy/status)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 14: `hooks/hooks.json`

**Files:**
- Create: `hooks/hooks.json`

- [ ] **Step 1: Create the hooks manifest**

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

- [ ] **Step 2: Validate JSON**

Run: `jq -e . hooks/hooks.json`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
feat(plugin): UserPromptSubmit + Stop hooks driving busy-mode inhibitor

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 15: README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

```markdown
# claude-code-keep-alive

A [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin that prevents your machine from sleeping during long Claude Code sessions. Inspired by GitHub Copilot CLI's `/keep-alive` command.

## Install

Inside a Claude Code session:

```text
/plugin marketplace add mrzeszowski/claude-code-keep-alive
/plugin install keep-alive@claude-code-keep-alive
/reload-plugins
```

That's it. The plugin's four slash commands are now available under the `/keep-alive:` namespace.

## Usage

| Command | What it does |
| --- | --- |
| `/keep-alive:status` | Show current state. |
| `/keep-alive:on` | Inhibit sleep until you turn it off. |
| `/keep-alive:on 30m` | Inhibit sleep for 30 minutes. (`m`, `h`, `d` suffixes; bare number = minutes.) |
| `/keep-alive:off` | Release the inhibitor. |
| `/keep-alive:busy` | Inhibit sleep only while Claude is actively processing. Idle time is allowed to sleep. |

The `keep-alive:` prefix is the plugin namespace — every Claude Code plugin's commands are prefixed by the plugin's name to avoid collisions across plugins.

## How it works

- **macOS:** spawns a detached `caffeinate -dis` process.
- **Linux (systemd):** spawns a detached `systemd-inhibit --what=idle:sleep ... sleep` process.
- **Windows:** not yet supported in v0.1; contributions welcome.

State lives in `${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-keep-alive/state` — a single global file shared across all your Claude Code sessions on this machine. `flock` (or a `mkdir`-based fallback on macOS) serializes concurrent invocations.

`busy` mode is driven by two hooks shipped with the plugin: `UserPromptSubmit` starts the inhibitor, `Stop` tears it down. Both are no-ops unless you've explicitly opted in with `/keep-alive:busy`.

## Updating

```text
/plugin update keep-alive@claude-code-keep-alive
```

You only receive updates when the plugin's `version` field is bumped (not on every commit).

## Uninstall

```text
/plugin uninstall keep-alive@claude-code-keep-alive
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
docs: README with marketplace install instructions and usage table

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 16: CONTRIBUTING.md + CHANGELOG.md

**Files:**
- Create: `CONTRIBUTING.md`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create `CONTRIBUTING.md`**

```markdown
# Contributing

Thanks for considering a contribution. The plugin is small (~200 lines of POSIX sh plus four 5-line slash commands) and intentionally low-magic.

## Local development

```bash
git clone git@github.com:mrzeszowski/claude-code-keep-alive.git
cd claude-code-keep-alive
claude --plugin-dir .
```

Then, inside the Claude Code session:

```text
/reload-plugins
/keep-alive:status
```

After making changes, run `/reload-plugins` again — no need to restart Claude Code.

## Running tests

Install [bats-core](https://bats-core.readthedocs.io/) and [shellcheck](https://www.shellcheck.net/):

- macOS: `brew install bats-core shellcheck`
- Ubuntu: `sudo apt install bats shellcheck`

Then:

```bash
shellcheck -s sh bin/keep-alive
bats tests/
```

Tests use mock inhibitors under `tests/mocks/` so they're safe to run repeatedly. CI runs the same suite on `ubuntu-latest` and `macos-latest`.

## Release process

1. Update `version` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
2. Add a `CHANGELOG.md` entry.
3. Open a PR titled `release: vX.Y.Z`; merge after CI passes.
4. Tag the merged commit: `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. The `release.yml` workflow creates a GitHub release with auto-generated notes, after verifying the tag matches `plugin.json`'s version.

Users on the marketplace receive the update when they run `/plugin update keep-alive@claude-code-keep-alive`.
```

- [ ] **Step 2: Create `CHANGELOG.md`**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md CHANGELOG.md
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
docs: CONTRIBUTING and CHANGELOG (seeded with v0.1.0 entry)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 17: `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the CI workflow**

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

      - name: Shellcheck bin/
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: ./bin
          severity: warning

      - name: Validate plugin and marketplace manifests
        run: |
          jq -e . .claude-plugin/plugin.json
          jq -e . .claude-plugin/marketplace.json

      - name: Validate hooks manifest
        run: jq -e . hooks/hooks.json

      - name: Install yq
        run: sudo snap install yq

      - name: Validate command frontmatter
        run: |
          for f in commands/*.md; do
            echo "--- $f"
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

      - name: Install bats (Ubuntu)
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y bats

      - name: Install bats (macOS)
        if: runner.os == 'macOS'
        run: brew install bats-core

      - name: Run bats suite
        run: bats tests/
```

- [ ] **Step 2: Commit**

```bash
mkdir -p .github/workflows
git add .github/workflows/ci.yml
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
ci: lint (shellcheck + manifest validation) and bats matrix on macos + ubuntu

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

- [ ] **Step 3: Verify CI passes on GitHub**

Run: `gh run watch` (or open the Actions tab).
Expected: both `lint` and the two `test` matrix jobs succeed. If any fail, fix the underlying issue (do not skip the failing step) and re-push.

---

## Task 18: `.github/workflows/release.yml`

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the release workflow**

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
            echo "::error::Tag $TAG does not match plugin.json version $MANIFEST"
            exit 1
          fi

      - name: Verify marketplace.json version matches tag
        run: |
          TAG="${GITHUB_REF_NAME#v}"
          MANIFEST=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
          if [ "$TAG" != "$MANIFEST" ]; then
            echo "::error::Tag $TAG does not match marketplace.json plugin version $MANIFEST"
            exit 1
          fi

      - name: Create GitHub release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          draft: false
          prerelease: ${{ contains(github.ref_name, '-') }}
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
ci: tag-driven release workflow with manifest version-parity check

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 19: `.github/dependabot.yml` + PR/issue templates

**Files:**
- Create: `.github/dependabot.yml`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Create: `.github/ISSUE_TEMPLATE/feature_request.md`

- [ ] **Step 1: Create `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
    commit-message:
      prefix: "ci"
      include: "scope"
```

- [ ] **Step 2: Create `.github/PULL_REQUEST_TEMPLATE.md`**

```markdown
## Summary

<!-- One or two sentences on what changed and why. -->

## Checklist

- [ ] `shellcheck -s sh bin/keep-alive` passes
- [ ] `bats tests/` passes locally on at least one OS (macOS or Linux)
- [ ] If user-facing behavior changed: README updated
- [ ] If a new feature: `CHANGELOG.md` updated under `[Unreleased]`
- [ ] If a release: `version` bumped in both `plugin.json` and `marketplace.json`
```

- [ ] **Step 3: Create `.github/ISSUE_TEMPLATE/bug_report.md`**

```markdown
---
name: Bug report
about: Something doesn't work as expected
labels: bug
---

## What happened

<!-- Describe the unexpected behavior. -->

## What you expected

<!-- Describe what you thought would happen. -->

## Environment

- OS and version (e.g., macOS 14.4, Ubuntu 24.04):
- Claude Code version (run `claude --version`):
- Plugin version (run `/plugin list` inside Claude Code):
- Output of `/keep-alive:status`:

## Reproduction steps

1.
2.
3.

## Additional context

<!-- Logs, screenshots, anything else relevant. -->
```

- [ ] **Step 4: Create `.github/ISSUE_TEMPLATE/feature_request.md`**

```markdown
---
name: Feature request
about: Suggest an idea for this plugin
labels: enhancement
---

## What you want to do

<!-- Describe the workflow or capability you'd like. -->

## Why

<!-- What problem does this solve? -->

## Sketch of how it might work

<!-- Optional: command surface, UX, etc. -->
```

- [ ] **Step 5: Commit**

```bash
mkdir -p .github/ISSUE_TEMPLATE
git add .github/dependabot.yml .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/
git -c user.name="Marcin Rzeszowski" -c user.email="mrzeszowski@outlook.com" commit -m "$(cat <<'EOF'
chore: dependabot for actions + PR / issue templates

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Task 20: End-to-end smoke test + pre-release tag

**Files:** (none — this is a verification + tagging task)

- [ ] **Step 1: Confirm CI is green on the latest commit**

Run: `gh run list --limit 3`
Expected: latest run on `main` is `success` for `CI`.

- [ ] **Step 2: Install the plugin locally via `--plugin-dir` and smoke-test**

In a fresh terminal:

```bash
claude --plugin-dir /Users/marcinrzeszowski/Documents/Repositories/claude-code-keep-alive
```

Inside the session:

```text
/reload-plugins
/keep-alive:status       # expect: keep-alive: off
/keep-alive:on           # expect: keep-alive: on (since ..., PID ...)
```

In another terminal (macOS): `pmset -g assertions | grep claude-code-keep-alive` or `ps aux | grep caffeinate` — confirm the inhibitor is alive.

(Linux: `systemd-inhibit --list | grep claude-code-keep-alive`.)

Back in the session:

```text
/keep-alive:off          # expect: keep-alive: off
```

Confirm the inhibitor is gone.

Then:

```text
/keep-alive:on 1m        # 1-minute duration; expect duration line
```

Wait ~70 seconds, then `/keep-alive:status` — expect `off` (the duration timed out and stale-PID cleanup normalized the state).

Then:

```text
/keep-alive:busy
```

Submit any prompt that triggers Claude work (e.g., "list the files in this repo"). While Claude is working, in another terminal verify the inhibitor process exists. After Claude finishes, verify it's gone. The state still shows `busy`.

```text
/keep-alive:off
```

- [ ] **Step 3: Tag `v0.1.0-rc.1`**

```bash
git tag v0.1.0-rc.1
git push origin v0.1.0-rc.1
```

`release.yml` runs, the version-parity check passes (since `plugin.json` is `0.1.0` and the tag normalizes to `0.1.0`), and a pre-release is published on GitHub.

- [ ] **Step 4: Install from the marketplace and verify**

In a fresh Claude Code session (without `--plugin-dir`):

```text
/plugin marketplace add mrzeszowski/claude-code-keep-alive
/plugin install keep-alive@claude-code-keep-alive
/reload-plugins
/keep-alive:status
```

Expected: `keep-alive: off`. (Same smoke test as Step 2 can be re-run from the installed copy.)

- [ ] **Step 5: Promote to `v0.1.0`**

Once Step 4 passes:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow publishes `v0.1.0` (not pre-release this time). Users running `/plugin update keep-alive@claude-code-keep-alive` will receive it.

---

## Self-Review

**Spec coverage:**
- §3 Command Surface → Tasks 2-7, 10, 13.
- §4 Architecture → matches Tasks 2-10 (script), 13 (commands), 14 (hooks).
- §5 Repository Layout → Tasks 11-19.
- §6.1 plugin.json → Task 11.
- §6.2 marketplace.json → Task 12.
- §6.3 Slash command files → Task 13.
- §6.4 Script behavior → Tasks 2-10.
- §6.5 hooks.json → Task 14.
- §7 Data flow → covered by Task 20 smoke test.
- §8 Installation → Tasks 12 + 15 (manifest + README).
- §9 Error handling → Task 10.
- §10 Testing → Tasks 1-10 (incremental TDD).
- §11 GitHub Actions Workflows → Tasks 17, 18, 19.
- §12 Security/Privacy → enforced by Tasks 17/18 (pinned actions, minimal `permissions:`).
- §13 Versioning → Task 18 (parity check) + Task 20 (rc → final tag flow).
- §15 Open items: hook event names (verified in Task 14 by validating against current Claude Code docs at implementation time); `allowed-tools` frontmatter syntax (verified in Task 13 by `yq` parse).

**Placeholder scan:** none — every step shows the actual code, command, or content.

**Type/name consistency:** state file fields `mode`, `pid`, `started_at`, `expires_at` are referenced identically across Tasks 2-9. Script function names (`cmd_on`, `_cmd_on`, `spawn_inhibitor`, `parse_duration`, `refresh_state`, `with_lock`, `ensure_inhibitor_binary`) match across tasks. Slash command names align with command-file names (`on.md` → `/keep-alive:on`).

**State-format note:** Spec §6.4 illustrates JSON; plan implements `key=value` for portability. Equivalent semantically; flagged in the File Structure section.
