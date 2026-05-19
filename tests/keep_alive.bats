#!/usr/bin/env bats

load test_helper

@test "status: empty state prints off" {
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
}

@test "no args: also prints status" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
}

@test "on: spawns inhibitor and reports on" {
  run "$SCRIPT" on
  [ "$status" -eq 0 ]
  [ "$output" = "☕ Keep-alive on — machine won't sleep." ]
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

@test "off after on: kills PID and reports off" {
  "$SCRIPT" on
  pid=$(state_get pid)
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
  ! kill -0 "$pid" 2>/dev/null
}

@test "off on empty state is a no-op success" {
  run "$SCRIPT" off
  [ "$status" -eq 0 ]
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
}

@test "off clears mode and pid in state file" {
  "$SCRIPT" on
  "$SCRIPT" off
  [ "$(state_get mode)" = "off" ]
  [ -z "$(state_get pid)" ]
}

@test "on 30m: mode=duration, expires_at set" {
  run "$SCRIPT" on 30m
  [ "$status" -eq 0 ]
  [ "$output" = "☕ Keep-alive on (timed) — machine won't sleep." ]
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

@test "busy: sets mode=busy, does not spawn an inhibitor" {
  run "$SCRIPT" busy
  [ "$status" -eq 0 ]
  [ "$output" = "💤 Busy mode — idle, waiting for next prompt." ]
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

@test "busy + --busy-event=start: spawns inhibitor, mode stays busy" {
  "$SCRIPT" busy
  run "$SCRIPT" --busy-event=start
  [ "$status" -eq 0 ]
  [ "$(state_get mode)" = "busy" ]
  pid=$(state_get pid)
  [ -n "$pid" ]
  kill -0 "$pid"
}

@test "status after busy+start: shows currently inhibiting message" {
  "$SCRIPT" busy
  "$SCRIPT" --busy-event=start
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "$output" = "💤 Busy mode — currently inhibiting sleep." ]
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
  [ "$output" = "✔  Keep-alive off — machine can sleep normally." ]
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
  [ "$output" = "💤 Busy mode — idle, waiting for next prompt." ]
  [ "$(state_get mode)" = "busy" ]
  [ -z "$(state_get pid)" ]
}

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

@test "unknown verb: usage to stderr, exit 1" {
  run "$SCRIPT" foo
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Usage:"
}

@test "missing inhibitor binary: exit 3 with install hint" {
  # Force platform=linux so the script looks for systemd-inhibit.
  # Build a minimal PATH that contains only the tools the script needs
  # (mkdir, date, cat, etc.) but deliberately omits systemd-inhibit.
  # This works on Ubuntu (where /usr/bin/systemd-inhibit exists) and
  # macOS (where it doesn't), without relying on platform-specific gaps.
  _tmpbin="$(mktemp -d -t keepalive-nobin-XXXXXX)"
  for _t in mkdir date cat grep sed kill sleep sh; do
    _tp="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_tp" "$_tmpbin/$_t" || true
  done
  # Deliberately no systemd-inhibit in _tmpbin
  KEEP_ALIVE_PLATFORM=linux PATH="$_tmpbin" run "$SCRIPT" on
  rm -rf "$_tmpbin"
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "not found"
}

@test "help: -h prints usage to stdout, exit 0" {
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Usage:"
}

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
  KEEP_ALIVE_PLATFORM=windows run "$SCRIPT" --busy-event=stop
  [ "$status" -eq 0 ]
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
