# Windows Support Design

**Date:** 2026-05-19
**Status:** Approved
**Scope:** Add first-class Windows support to `claude-code-keep-alive` via a detached PowerShell 7 inhibitor process.

---

## 1. Goal

Replace the v0.1 "not yet supported" Windows stub with a working implementation that matches the macOS (`caffeinate`) and Linux (`systemd-inhibit`) behaviour: a detached background process holds a sleep inhibit lock and is killed on `off` or session end. All four commands (`on`, `on <duration>`, `off`, `busy`) must work identically on Windows.

## 2. Mechanism

**`SetThreadExecutionState` via P/Invoke** — the correct Windows API for preventing sleep. Called with:

```
ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED  (0x80000003)
```

This matches `caffeinate -dis` (display + idle/system sleep inhibited). When the process exits for any reason — killed by `off`, duration elapsed, or crash — Windows automatically clears `ES_CONTINUOUS` for the dead process. No explicit cleanup code is required.

## 3. New file: `bin/keep-alive-win.ps1`

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

- Accepts an optional `-Seconds` parameter for duration mode. `0` (default) means indefinite.
- `99999999` for indefinite matches the Linux pattern (`sleep 99999999`) — POSIX-safe, no `infinity`.
- No cleanup on exit: Windows releases the inhibit automatically.

## 4. Changes to `bin/keep-alive`

### 4.1 New helper: `_locate_win_ps1`

Resolves the path to `keep-alive-win.ps1` sibling. When Claude Code invokes `keep-alive` via PATH, `$0` has no directory component; resolution falls back to `command -v`. An env var override (`KEEP_ALIVE_WIN_PS1`) is the test escape hatch, following the same pattern as `KEEP_ALIVE_PLATFORM` and `KEEP_ALIVE_STATE_DIR`.

```sh
_locate_win_ps1() {
    [ -n "${KEEP_ALIVE_WIN_PS1:-}" ] && { echo "$KEEP_ALIVE_WIN_PS1"; return; }
    _cmd=$(command -v "$(basename "$0")" 2>/dev/null)
    _dir=$(cd "$(dirname "${_cmd:-$0}")" 2>/dev/null && pwd 2>/dev/null)
    echo "${_dir:-$(dirname "$0")}/keep-alive-win.ps1"
}
```

### 4.2 `ensure_inhibitor_binary` — replace Windows stub

Before:
```sh
windows)
    echo "keep-alive: Windows not yet supported in v0.1; contributions welcome at ..." >&2
    exit 2 ;;
```

After:
```sh
windows)
    command -v pwsh >/dev/null 2>&1 || {
        echo "keep-alive: 'pwsh' not found in PATH (install PowerShell 7+: https://aka.ms/powershell)" >&2
        exit 3
    } ;;
```

Exit code changes from 2 (unsupported platform) to 3 (missing binary) — consistent with how missing `caffeinate`/`systemd-inhibit` is handled.

### 4.3 `spawn_inhibitor` — add Windows case

```sh
windows)
    _ps1=$(_locate_win_ps1)
    if [ "$duration_secs" -gt 0 ]; then
        nohup pwsh -NonInteractive -File "$_ps1" -Seconds "$duration_secs" </dev/null >/dev/null 2>&1 9>&- &
    else
        nohup pwsh -NonInteractive -File "$_ps1" </dev/null >/dev/null 2>&1 9>&- &
    fi ;;
```

- `-NonInteractive` suppresses prompts (important in headless CI/hook contexts).
- `9>&-` closes the flock fd in the child — same as macOS/Linux cases, load-bearing invariant.
- `nohup ... &` detaches the process so it survives the shell that started it.

## 5. Test changes

### 5.1 New mocks

**`tests/mocks/pwsh`** — shell script mock for cross-platform CI:
```sh
#!/usr/bin/env sh
exec sleep 9999
```
Ignores all arguments. Used on macOS/Ubuntu CI when `KEEP_ALIVE_PLATFORM=windows` is set.

**`tests/mocks/keep-alive-win.ps1`** — empty/dummy file at a known path so `KEEP_ALIVE_WIN_PS1` can point to it in tests. Never executed on non-Windows runners (the mock `pwsh` swallows it); the path just needs to resolve.

### 5.2 Test case changes in `tests/keep_alive.bats`

| Change | Detail |
|--------|--------|
| Remove | `"unsupported platform (windows): exit 2 with hint"` — Windows is now supported |
| Add | `"windows: on starts inhibitor (mock pwsh)"` — KEEP_ALIVE_PLATFORM=windows, mock PATH, check exit 0 and mode=on |
| Add | `"windows: off kills inhibitor"` — on → off, check state=off |
| Add | `"windows: busy mode round-trip"` — busy → busy-event=start → busy-event=stop |
| Add | `"windows: missing pwsh exits 3"` — KEEP_ALIVE_PLATFORM=windows with pwsh absent, check exit 3 |

On the Windows CI runner, platform detection returns `windows` naturally and the real `pwsh` runs the actual PS1 — no mocks needed there.

## 6. CI changes

Add `windows-latest` to the test matrix in `.github/workflows/ci.yml`.

**Extra setup steps on Windows only:**
- **Install bats** via `npm install -g bats` (npm is pre-installed on GitHub-hosted Windows runners; bats is not).
- **Run tests under Git Bash** — set `shell: bash` on the test step (Git Bash is bundled with the Windows runner; `bats` will not work under `cmd` or `pwsh`).
- **Skip ShellCheck** on Windows — ShellCheck validates POSIX sh and is already covered by macOS/Ubuntu jobs; installing it on Windows adds friction with no new signal.

## 7. Exit code table update

| Situation | Exit code |
|-----------|-----------|
| Windows + pwsh missing | 3 (was 2 in v0.1) |
| Truly unsupported platform | 2 (unchanged) |

## 8. Out of scope

- `powershell.exe` (Windows PowerShell 5.1) fallback — explicitly not included. `pwsh` (PowerShell 7+) is required; if absent, exit 3 with an install hint.
- Per-session inhibitor isolation — remains a post-v0.1 item.
- `ES_AWAYMODE_REQUIRED` — not included; matches existing scope of caffeinate/systemd-inhibit flags.
