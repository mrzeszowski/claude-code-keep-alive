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
