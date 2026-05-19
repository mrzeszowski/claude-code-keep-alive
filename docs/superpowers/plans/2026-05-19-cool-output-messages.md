# Cool Output Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace terse `keep-alive: on (since ..., PID ...)` output with emoji + short prose messages that confirm state without exposing PIDs or ISO timestamps.

**Architecture:** All user-facing output flows through `_cmd_status` in `bin/keep-alive`. Every public command (`on`, `off`, `busy`, `status`) calls `_cmd_status` as its final step, so changing that one function is the complete change. Tests in `tests/keep_alive.bats` assert on exact output strings and need updating first (TDD red → green).

**Tech Stack:** POSIX sh, BATS (bash-based test framework), ShellCheck

---

### Task 1: Update test assertions to new output strings (TDD red)

**Files:**
- Modify: `tests/keep_alive.bats:8,14,20,46,53,66,100,165,179`

- [ ] **Step 1: Update all output assertions in `tests/keep_alive.bats`**

Make the following targeted changes (exact line replacements):

**Line 8** — status off:
```bash
# old:
  [ "$output" = "keep-alive: off" ]
# new:
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
```

**Line 14** — no-args status:
```bash
# old:
  [ "$output" = "keep-alive: off" ]
# new:
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
```

**Line 20** — `on` confirmation:
```bash
# old:
  echo "$output" | grep -E '^keep-alive: on \(since [0-9TZ:-]+, PID [0-9]+\)$'
# new:
  [ "$output" = "☕ Keep-alive on — machine won't sleep." ]
```

**Line 46** — `off` after `on`:
```bash
# old:
  [ "$output" = "keep-alive: off" ]
# new:
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
```

**Line 53** — `off` on empty state:
```bash
# old:
  [ "$output" = "keep-alive: off" ]
# new:
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
```

**Line 66** — `on 30m` duration confirmation:
```bash
# old:
  echo "$output" | grep -E '^keep-alive: duration \(expires [0-9TZ:-]+, PID [0-9]+\)$'
# new:
  [ "$output" = "☕ Keep-alive on (timed) — machine won't sleep." ]
```

**Line 100** — `busy` mode set:
```bash
# old:
  echo "$output" | grep -q "keep-alive: busy (no inhibitor currently active)"
# new:
  [ "$output" = "💤 Busy mode — idle, waiting for next prompt." ]
```

**Line 165** — stale PID in on-mode normalizes to off:
```bash
# old:
  [ "$output" = "keep-alive: off" ]
# new:
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
```

**Line 179** — stale PID in busy-mode stays busy idle:
```bash
# old:
  echo "$output" | grep -q "keep-alive: busy (no inhibitor currently active)"
# new:
  [ "$output" = "💤 Busy mode — idle, waiting for next prompt." ]
```

- [ ] **Step 2: Run tests to confirm they fail (TDD red)**

```bash
KEEP_ALIVE_PLATFORM=darwin bats tests/
```

Expected: multiple failures on the updated assertions (old code still produces old strings). Everything else should still pass.

---

### Task 2: Update `_cmd_status` in `bin/keep-alive` (TDD green)

**Files:**
- Modify: `bin/keep-alive:168-182`

- [ ] **Step 1: Replace the `_cmd_status` function body**

Current function (lines 168–182):
```sh
_cmd_status() {
  refresh_state
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
```

Replace with:
```sh
_cmd_status() {
  refresh_state
  case "$mode" in
    on)       echo "☕ Keep-alive on — machine won't sleep." ;;
    duration) echo "☕ Keep-alive on (timed) — machine won't sleep." ;;
    busy)
      if [ -n "$pid" ]; then
        echo "💤 Busy mode — currently inhibiting sleep."
      else
        echo "💤 Busy mode — idle, waiting for next prompt."
      fi ;;
    *)        echo "✔  Keep-alive off — machine can sleep normally." ;;
  esac
}
```

Note: The `*` catch-all covers `off`, `""`, and any unknown value — all map to the off message, preserving the existing invariant.

- [ ] **Step 2: Run tests to confirm they pass (TDD green)**

```bash
KEEP_ALIVE_PLATFORM=darwin bats tests/
```

Expected: `28 tests, 0 failures`

- [ ] **Step 3: Run ShellCheck**

```bash
shellcheck -s sh bin/keep-alive
```

Expected: no output (clean).

- [ ] **Step 4: Commit**

```bash
git add bin/keep-alive tests/keep_alive.bats
git commit -m "feat: emoji output messages — no PID or ISO timestamp"
```
