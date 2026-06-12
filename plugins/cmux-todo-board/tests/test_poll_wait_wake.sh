#!/usr/bin/env bash
# Tests for cwd-filtered completion-wake in poll-wait.sh (#92).
# Verifies event_line_matches() correctly filters by cwd basename to prevent
# cross-wake between parallel workers.
#
# This test copies the match function inline (as permitted by .task-spec.md)
# so it can be exercised without a live cmux stream.
set -euo pipefail

# ── event_line_matches (synced with poll-wait.sh) ──
event_line_matches() {
  local line="$1" pattern="$2" cwd_basename="${3:-}"
  if ! grep -qE "$pattern" <<<"$line"; then
    return 1
  fi
  if [[ -n "$cwd_basename" ]]; then
    if ! grep -qF "$cwd_basename" <<<"$line"; then
      return 1
    fi
  fi
  return 0
}

EVENT_PATTERN='(lifecycle.*idle|hook_event_name.*Stop|CTB-DONE.*task=)'

# Realistic agent.hook.Stop event lines (cwd JSON-escaped with \/)
STOP_WT_FOO='{"name":"agent.hook.Stop","category":"agent","payload":{"cwd":"\/Users\/x\/wt-foo","hook_event_name":"Stop","session_id":"pi-abc123","_source":"pi"}}'
STOP_WT_BAR='{"name":"agent.hook.Stop","category":"agent","payload":{"cwd":"\/Users\/x\/wt-bar","hook_event_name":"Stop","session_id":"pi-def456","_source":"pi"}}'

# Non-Stop agent event (must not match)
PRETOOL_WT_FOO='{"name":"agent.hook.PreToolUse","category":"agent","payload":{"cwd":"\/Users\/x\/wt-foo","hook_event_name":"PreToolUse","session_id":"pi-abc123","_source":"pi"}}'

# CTB-DONE notification (fallback path, no cwd field)
CTB_DONE='{"name":"notification.created","category":"notification","payload":{"title":"CTB-DONE","body":"CTB-DONE task=42 surface=surface:174 status=success branch=feat/test"},"surface_id":"surface:174"}'

_FAILURES=0

echo "=== Test 1: Stop event with MATCHING cwd basename → matches ==="
if event_line_matches "$STOP_WT_FOO" "$EVENT_PATTERN" "wt-foo"; then
  echo "PASS"
else
  echo "FAIL: Stop event with matching cwd basename should match"
  _FAILURES=$((_FAILURES + 1))
fi

echo "=== Test 2: Stop event with DIFFERENT cwd basename → does NOT match ==="
if event_line_matches "$STOP_WT_FOO" "$EVENT_PATTERN" "wt-bar"; then
  echo "FAIL: Stop event from wt-foo should NOT match when filtering for wt-bar (cross-wake bug)"
  _FAILURES=$((_FAILURES + 1))
else
  echo "PASS"
fi

echo "=== Test 3: Stop event with no --cwd given → matches (backward compat) ==="
if event_line_matches "$STOP_WT_FOO" "$EVENT_PATTERN" ""; then
  echo "PASS"
else
  echo "FAIL: Stop event without cwd filter should match (backward compat broken)"
  _FAILURES=$((_FAILURES + 1))
fi

echo "=== Test 4: Non-Stop agent event with right cwd → does NOT match ==="
if event_line_matches "$PRETOOL_WT_FOO" "$EVENT_PATTERN" "wt-foo"; then
  echo "FAIL: PreToolUse event should NOT match even with correct cwd (wrong event type)"
  _FAILURES=$((_FAILURES + 1))
else
  echo "PASS"
fi

echo "=== Test 5: CTB-DONE notification line still matches (fallback path) ==="
if event_line_matches "$CTB_DONE" "$EVENT_PATTERN" ""; then
  echo "PASS"
else
  echo "FAIL: CTB-DONE notification should match (fallback path broken)"
  _FAILURES=$((_FAILURES + 1))
fi

echo ""
if [[ $_FAILURES -eq 0 ]]; then
  echo "All poll-wait wake tests passed."
else
  echo "$_FAILURES test(s) failed."
  exit 1
fi
