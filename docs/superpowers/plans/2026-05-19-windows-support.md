# Windows Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-class Windows sleep inhibition to `claude-code-keep-alive` via a detached `pwsh` process that calls `SetThreadExecutionState`.

**Architecture:** A new `bin/keep-alive-win.ps1` calls `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)` then blocks with `Start-Sleep`. The shell script spawns it detached via `nohup pwsh -NonInteractive -File` and kills it by PID — identical lifecycle to `caffeinate` and `systemd-inhibit`. A `_locate_win_ps1` helper resolves the sibling PS1 path at runtime, with a `KEEP_ALIVE_WIN_PS1` env var override for advanced test scenarios.

**Tech Stack:** POSIX sh (`bin/keep-alive`), PowerShell 7+ (`pwsh`), bats, shellcheck, GitHub Actions.

---

### Task 1: Create `bin/keep-alive-win.ps1` and test mocks

**Files:**
- Create: `bin/keep-alive-win.ps1`
- Create: `tests/mocks/pwsh`
- Create: `tests/mocks/keep-alive-win.ps1` (empty)

- [ ] **Step 1: Create `bin/keep-alive-win.ps1`**

```powershell
param([int]$Seconds = 0)

Add-Type -Namespace Win32 -Name PowerMgmt -MemberDefinition @'
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
'@

# ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED  (matches caffeinate -dis)
[void][Win32.PowerMgmt]::SetThreadExecutionState([uint32]0x80000003)

if ($Seconds -gt 0) { Start-Sleep -Seconds $Seconds } else { Start-Sleep -Seconds 99999999 }
```

- [ ] **Step 2: Create `tests/mocks/pwsh`**

```sh
#!/usr/bin/env sh
exec sleep 9999
```

Then make it executable:

```bash
chmod +x tests/mocks/pwsh
```

The mock ignores all arguments (`-NonInteractive -File ... -Seconds ...`) and sleeps — matching the pattern of the existing `caffeinate` and `systemd-inhibit` mocks. The teardown in `test_helper.bash` already kills `sleep 9999$` processes, so no changes to the helper are needed.

- [ ] **Step 3: Create empty `tests/mocks/keep-alive-win.ps1`**

```bash
touch tests/mocks/keep-alive-win.ps1
```

The mock `pwsh` never executes the PS1 (it ignores all args). This file exists only so the path the shell script constructs always resolves on disk in production.

- [ ] **Step 4: Run the existing test suite — must still pass**

```bash
bats tests/
shellcheck -s sh bin/keep-alive
```

Expected: all 29 existing tests pass; shellcheck reports no issues. No script changes yet, so nothing should regress.

- [ ] **Step 5: Commit**

```bash
git add bin/keep-alive-win.ps1 tests/mocks/pwsh tests/mocks/keep-alive-win.ps1
git commit -m "feat: add keep-alive-win.ps1 PowerShell inhibitor and test mocks"
```

---

### Task 2: Write failing Windows tests (TDD red)

**Files:**
- Modify: `tests/keep_alive.bats`

- [ ] **Step 1: Remove the old "unsupported platform (windows)" test**

Delete these 5 lines from `tests/keep_alive.bats`:

```bash
@test "unsupported platform (windows): exit 2 with hint" {
  KEEP_ALIVE_PLATFORM=windows run "$SCRIPT" on
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "not yet supported"
}
```

- [ ] **Step 2: Append 4 new Windows tests to the end of `tests/keep_alive.bats`**

```bash
@test "windows: on starts inhibitor (mock pwsh)" {
  KEEP_ALIVE_PLATFORM=windows run "$SCRIPT" on
  [ "$status" -eq 0 ]
  [ "$output" = "☕ Keep-alive on — machine won't sleep." ]
  [ "$(state_get mode)" = "on" ]
  pid=$(state_get pid)
  [ -n "$pid" ]
  kill -0 "$pid"
}

@test "windows: off kills inhibitor" {
  KEEP_ALIVE_PLATFORM=windows "$SCRIPT" on
  pid=$(state_get pid)
  KEEP_ALIVE_PLATFORM=windows run "$SCRIPT" off
  [ "$status" -eq 0 ]
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
  [ "$(state_get mode)" = "off" ]
  ! kill -0 "$pid" 2>/dev/null
}

@test "windows: busy mode round-trip" {
  KEEP_ALIVE_PLATFORM=windows run "$SCRIPT" busy
  [ "$status" -eq 0 ]
  [ "$output" = "💤 Busy mode — idle, waiting for next prompt." ]
  [ "$(state_get mode)" = "busy" ]
  KEEP_ALIVE_PLATFORM=windows "$SCRIPT" --busy-event=start
  pid=$(state_get pid)
  [ -n "$pid" ]
  kill -0 "$pid"
  KEEP_ALIVE_PLATFORM=windows "$SCRIPT" --busy-event=stop
  [ "$(state_get mode)" = "busy" ]
  [ -z "$(state_get pid)" ]
  ! kill -0 "$pid" 2>/dev/null
}

@test "windows: missing pwsh exits 3" {
  _tmpbin="$(mktemp -d -t keepalive-nobin-XXXXXX)"
  for _t in mkdir date cat grep sed kill sleep sh; do
    _tp="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_tp" "$_tmpbin/$_t" || true
  done
  KEEP_ALIVE_PLATFORM=windows PATH="$_tmpbin" run "$SCRIPT" on
  rm -rf "$_tmpbin"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "pwsh"
}
```

Note: `test_helper.bash` already prepends `tests/mocks/` to PATH in `setup()`, so the `pwsh` mock is found automatically by the first three tests. The `"missing pwsh exits 3"` test overrides PATH with a minimal tmpdir that deliberately excludes `pwsh`.

- [ ] **Step 3: Run tests — confirm the 4 new tests fail**

```bash
bats tests/
```

Expected: 28 existing tests pass, 4 new tests fail. The first 3 Windows tests fail with exit code 2 ("not yet supported"); the missing-pwsh test fails because it also gets exit 2 instead of 3.

- [ ] **Step 4: Commit**

```bash
git add tests/keep_alive.bats
git commit -m "test(windows): add failing Windows bats tests (TDD red)"
```

---

### Task 3: Implement Windows support in `bin/keep-alive` (TDD green)

**Files:**
- Modify: `bin/keep-alive`

- [ ] **Step 1: Add `_locate_win_ps1` helper immediately before `spawn_inhibitor`**

Insert this block before the `spawn_inhibitor()` function (i.e., before the line `spawn_inhibitor() {`):

```sh
_locate_win_ps1() {
  [ -n "${KEEP_ALIVE_WIN_PS1:-}" ] && { echo "$KEEP_ALIVE_WIN_PS1"; return; }
  _cmd=$(command -v "$(basename "$0")" 2>/dev/null)
  _dir=$(cd "$(dirname "${_cmd:-$0}")" 2>/dev/null && pwd 2>/dev/null)
  echo "${_dir:-$(dirname "$0")}/keep-alive-win.ps1"
}

```

Resolution logic: when the script is invoked by absolute path (bats tests, direct call), `dirname "$0"` gives the script's directory directly. When invoked via PATH lookup as bare `keep-alive` (Claude Code plugin use), `command -v keep-alive` resolves the full path first. The `KEEP_ALIVE_WIN_PS1` env var short-circuits both — same escape-hatch pattern as `KEEP_ALIVE_PLATFORM` and `KEEP_ALIVE_STATE_DIR`.

- [ ] **Step 2: Replace the Windows stub in `ensure_inhibitor_binary`**

Find and replace this block inside `ensure_inhibitor_binary`:

```sh
    windows)
      echo "keep-alive: Windows not yet supported in v0.1; contributions welcome at https://github.com/mrzeszowski/claude-code-keep-alive" >&2
      exit 2 ;;
```

Replace with:

```sh
    windows)
      command -v pwsh >/dev/null 2>&1 || {
        echo "keep-alive: 'pwsh' not found in PATH (install PowerShell 7+: https://aka.ms/powershell)" >&2
        exit 3
      } ;;
```

Exit code changes from 2 (unsupported platform) to 3 (missing binary), consistent with how `caffeinate` and `systemd-inhibit` absence is handled.

- [ ] **Step 3: Add `windows)` case to `spawn_inhibitor`**

Inside `spawn_inhibitor`, find the `linux)` case (ends with `;;`). Add the `windows)` case immediately after it:

```sh
    windows)
      _ps1=$(_locate_win_ps1)
      if [ "$duration_secs" -gt 0 ]; then
        nohup pwsh -NonInteractive -File "$_ps1" -Seconds "$duration_secs" </dev/null >/dev/null 2>&1 9>&- &
      else
        nohup pwsh -NonInteractive -File "$_ps1" </dev/null >/dev/null 2>&1 9>&- &
      fi ;;
```

`-NonInteractive` suppresses credential prompts in headless hook contexts. `9>&-` closes the flock fd in the child — same as the `darwin` and `linux` cases; this is a load-bearing invariant (see CLAUDE.md).

- [ ] **Step 4: Run shellcheck — must be clean**

```bash
shellcheck -s sh bin/keep-alive
```

Expected: no warnings or errors.

- [ ] **Step 5: Run the full bats suite — all tests must pass**

```bash
bats tests/
```

Expected: 32 tests, all pass. (29 original − 1 removed + 4 new = 32.)

- [ ] **Step 6: Commit**

```bash
git add bin/keep-alive
git commit -m "feat(windows): implement Windows sleep inhibition via pwsh SetThreadExecutionState"
```

---

### Task 4: Add Windows CI runner

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add `windows-latest` to the test matrix**

Find:
```yaml
        os: [ubuntu-latest, macos-latest]
```

Replace with:
```yaml
        os: [ubuntu-latest, macos-latest, windows-latest]
```

- [ ] **Step 2: Add Windows bats install step**

After the existing `Install bats (macOS)` step, add:

```yaml
      - name: Install bats (Windows)
        if: runner.os == 'Windows'
        uses: bats-core/bats-action@4.0.0
```

- [ ] **Step 3: Set `shell: bash` on the "Run bats suite" step**

Find:
```yaml
      - name: Run bats suite
        run: bats tests/
```

Replace with:
```yaml
      - name: Run bats suite
        shell: bash
        run: bats tests/
```

`shell: bash` is a no-op on Linux and macOS (already bash). On Windows it activates Git Bash, which is bundled with the runner and is required for bats to work. ShellCheck is not added to the Windows job — it's already covered by the existing `lint` job which runs on `ubuntu-latest`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add windows-latest to test matrix"
```
