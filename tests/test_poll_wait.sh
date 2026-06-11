#!/usr/bin/env bash
# Tests for poll-wait.sh — pure-bash, NO network. Stubs cmux and poll-push.sh
# via PATH shim to feed canned event lines. Follows style of test_agent_notify.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLL_WAIT="$REPO_ROOT/skills/cmux-agent-workflows/scripts/poll-wait.sh"

if [[ ! -f "$POLL_WAIT" ]]; then
  echo "FAIL: poll-wait.sh not found at $POLL_WAIT"
  exit 1
fi

_FAILURES=0

run_in_mock_env() {
  local test_name="$1" test_fn="$2"
  echo "=== $test_name ==="

  local TMPENV
  TMPENV="$(mktemp -d)"
  local PLUGINDIR="$TMPENV/.config/opencode/plugins"
  mkdir -p "$PLUGINDIR"
  # Create dummy plugin file (tests C explicitly removes it for missing-plugin path)
  touch "$PLUGINDIR/cmux-session.js"

  # ── mock cmux ──
  cat > "$TMPENV/cmux" <<'CMUX_EOF'
#!/usr/bin/env bash
if [[ "$1" == "events" ]]; then
  if [[ -n "${CMUX_EVENT_FILE:-}" && -f "$CMUX_EVENT_FILE" ]]; then
    cat "$CMUX_EVENT_FILE"
    exit 0
  fi
  # No event file: simulate live stream; exit when parent dies
  sleep "${CMUX_EVENT_SLEEP:-300}" &
  SPID=$!
  while kill -0 $SPID 2>/dev/null; do
    kill -0 $PPID 2>/dev/null || { kill $SPID 2>/dev/null; exit 0; }
    sleep 1
  done
fi
exit 0
CMUX_EOF
  chmod +x "$TMPENV/cmux"

  # ── mock timeout (simple passthrough — actual timeout via EVENT_TIMEOUT / kill -0) ──
  cat > "$TMPENV/timeout" <<'TIMEOUT_EOF'
#!/usr/bin/env bash
TIMEOUT_SEC="$1"; shift
if [[ -z "$TIMEOUT_SEC" || "$TIMEOUT_SEC" -le 0 ]]; then
  exec "$@"
fi
"$@" &
TIMEOUT_PID=$!
(
  # Killer: wait TIMEOUT_SEC then kill the command
  sleep "$TIMEOUT_SEC" 2>/dev/null
  # Kill the process group so children are also terminated
  kill "$TIMEOUT_PID" 2>/dev/null
) &
KILLER_PID=$!
wait "$TIMEOUT_PID" 2>/dev/null || true
kill "$KILLER_PID" 2>/dev/null
# Clean up any leftover orphaned process group
kill -0 "$TIMEOUT_PID" 2>/dev/null && kill -9 "$TIMEOUT_PID" 2>/dev/null
exit 0
TIMEOUT_EOF
  chmod +x "$TMPENV/timeout"

  # ── mock poll-push.sh ──
  cat > "$TMPENV/poll-push.sh" <<'POLL_EOF'
#!/usr/bin/env bash
if [[ "${POLL_RESULT:-}" == "PUSHED" ]]; then
  sleep "${POLL_DELAY:-0}"
  echo "PUSHED deadbeef  (mock)"
  exit 0
fi
sleep "${POLL_SLEEP:-300}" &
SPID=$!
while kill -0 $SPID 2>/dev/null; do
  kill -0 $PPID 2>/dev/null || { kill $SPID 2>/dev/null; exit 0; }
  sleep 1
done
exit 1
POLL_EOF
  chmod +x "$TMPENV/poll-push.sh"

  # ── stub lib.sh ──
  cat > "$TMPENV/lib.sh" <<'LIB_EOF'
die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo ">>  $*" >&2; }
LIB_EOF

  # ── copy poll-wait.sh so DIR resolves to TMPENV ──
  cp "$POLL_WAIT" "$TMPENV/poll-wait.sh"
  chmod +x "$TMPENV/poll-wait.sh"

  (
    PATH="$TMPENV:$PATH"
    HOME="$TMPENV"
    export PATH HOME
    "$test_fn" "$TMPENV"
  )
  local rc=$?

  # Clean up any remaining background processes
  rm -rf "$TMPENV"
  return $rc
}

assert_output_contains() {
  local output="$1" pattern="$2" label="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "PASS"
  else
    echo "FAIL ($label): output did not match '$pattern'"
    echo "  got: $output"
    _FAILURES=$((_FAILURES + 1))
  fi
}

# ── Test A: event match → method=event ──
# Canned agent.hook.Stop triggers grep → event listener finishes first.
# Poller is delayed (POLL_DELAY=10) so event wins the race.
test_event_match() {
  local TMPENV="$1"
  cat > "$TMPENV/events.ndjson" <<'EOF'
{"name":"agent.hook.Stop","category":"agent","payload":{"hook_event_name":"Stop","phase":"completed"},"surface_id":null}
EOF
  CMUX_EVENT_FILE="$TMPENV/events.ndjson" \
    CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=5 POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:172 --branch feat/test-ev --task 42 \
      --event-timeout 3 --total-timeout 30
}

# ── Test B: poll fallback → method=poll ──
# No event file → grep never matches → event listener hangs → timeout kills it.
# Poller exits immediately with PUSHED → poll wins first.
test_poll_fallback() {
  local TMPENV="$1"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=0 POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:173 --branch feat/test-poll \
      --event-timeout 2 --total-timeout 30
}

# ── Test C: missing-plugin warning path ──
# Remove plugin file → EVENT_ENABLED=false → poll-only. Poll succeeds.
test_missing_plugin() {
  local TMPENV="$1"
  rm -f "$TMPENV/.config/opencode/plugins/cmux-session.js"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=0 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:174 --branch feat/test-noplugin \
      --event-timeout 2 --total-timeout 30
}

# ── Test D: arg parsing — missing required --branch ──
test_arg_parsing() {
  local TMPENV="$1"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=0 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:175 --event-timeout 2 --total-timeout 30 2>&1 || true
}

# ── Test E: total timeout → exit 1 ──
# No events, poller sleeps forever. Total-timeout expires → fail.
test_total_timeout() {
  local TMPENV="$1"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT="" POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:176 --branch feat/test-timeout \
      --event-timeout 2 --total-timeout 3 2>&1 || true
}

# ═══════════════════════════════════════════════════════════
# Run tests
# ═══════════════════════════════════════════════════════════

echo "--- Test A: event match → method=event ---"
output=$(run_in_mock_env "Test A: event match" test_event_match 2>&1) || true
assert_output_contains "$output" "COMPLETE surface=surface:172 branch=feat/test-ev method=event" "event match output"

echo "--- Test B: poll fallback → method=poll ---"
output=$(run_in_mock_env "Test B: poll fallback" test_poll_fallback 2>&1) || true
assert_output_contains "$output" "COMPLETE surface=surface:173 branch=feat/test-poll method=poll" "poll fallback output"

echo "--- Test C: missing-plugin warning path ---"
output=$(run_in_mock_env "Test C: missing plugin" test_missing_plugin 2>&1) || true
assert_output_contains "$output" "WARN.*cmux hooks not installed.*poll fallback" "missing-plugin warning"
assert_output_contains "$output" "COMPLETE.*method=poll" "missing-plugin still completes via poll"

echo "--- Test D: arg parsing ---"
output=$(run_in_mock_env "Test D: arg parsing" test_arg_parsing 2>&1) || true
assert_output_contains "$output" "ERROR.*usage:" "arg parsing error"

echo "--- Test E: total timeout → exit 1 ---"
output=$(run_in_mock_env "Test E: total timeout" test_total_timeout 2>&1) || true
assert_output_contains "$output" "TIMEOUT" "timeout output"

echo ""
if [[ $_FAILURES -eq 0 ]]; then
  echo "All poll-wait tests passed."
else
  echo "$_FAILURES test(s) failed."
  exit 1
fi
