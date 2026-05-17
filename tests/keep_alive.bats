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
