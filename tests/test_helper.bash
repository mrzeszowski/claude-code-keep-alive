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
  # Kill stray mock inhibitor processes that may not be recorded in the state
  # file (e.g., a process that lost an idempotency race).  Use the distinctive
  # sleep durations chosen by the mocks so we don't disturb unrelated sleeps.
  pkill -9 -f "sleep 99999999" 2>/dev/null || true   # Linux mock (systemd-inhibit path)
  pkill -9 -f "sleep 9999$"    2>/dev/null || true   # macOS mock (caffeinate path)
  rm -rf "$TMPDIR_TEST"
}

# Source the state file and echo a named variable. Usage: state_get pid
state_get() {
  # shellcheck disable=SC1090
  ( . "$KEEP_ALIVE_STATE_DIR/state" 2>/dev/null; eval "echo \"\${$1:-}\"" )
}
