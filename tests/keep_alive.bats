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
