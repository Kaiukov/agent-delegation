#!/usr/bin/env bash
# Dual-source waiter: event-driven (cmux events) + poll fallback (poll-push.sh).
# Replaces poll-push.sh as the PRIMARY wait; poll-push.sh is the fallback.
#
# Usage: poll-wait.sh --surface <ref> --branch <name> [--task <id>]
#                     [--event-timeout <s>] [--total-timeout <s>]
#
# How it works:
#   1. Start cmux events | grep in background (blocks on kernel events, no CPU).
#   2. Start poll-push.sh in background (sleeps 60s between polls).
#   3. Poll both with kill -0 at 1s intervals. First to finish wins.
#   4. On event match: kill poller, report COMPLETE method=event.
#   5. On poll push: kill event listener, report COMPLETE method=poll.
#   6. On total timeout: kill both, report TIMEOUT.
#
# Compatibility: macOS bash 3.2 (no `wait -n`, no arrays, no `read -t`).
#
# UNVERIFIED: event names and payload shapes. The grep patterns below are built
# against shapes documented in WAIT_WITHOUT_SLEEP.md and the cmux audit log
# (~/.cmuxterm/events.jsonl). Confirmed: agent events carry .payload.hook_event_name
# ("Stop", "SessionStart", etc.) and .payload.phase. The field .payload.lifecycle
# was NOT observed in the audit log (null); it may appear only in the live stream
# for opencode agents with cmux-session.js. We match both "lifecycle.*idle" and
# "hook_event_name.*Stop" to cover whichever fires. Notification bodies are
# redacted in the audit log but may be present in the live stream.
#
# UNVERIFIED: surface_id on agent events. In the audit log, agent events have
# surface_id:null because the source process (claude/opencode hook IPC) does not
# report a surface. The cmux-session.js plugin may fill surface_id from the
# enclosing pane. If it does not, surface-scoped event matching is unreliable
# and the grep may catch any agent's Stop/idle event. This is acceptable because
# the fallback poll-push.sh verifies the specific branch was pushed.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

SURFACE=""; BRANCH=""; TASK=""; EVENT_TIMEOUT=120; TOTAL_TIMEOUT=1800
while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface) SURFACE="$2"; shift 2 ;;
    --branch)  BRANCH="$2"; shift 2 ;;
    --task)    TASK="$2"; shift 2 ;;
    --event-timeout) EVENT_TIMEOUT="$2"; shift 2 ;;
    --total-timeout) TOTAL_TIMEOUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$SURFACE" && -n "$BRANCH" ]] || die "usage: poll-wait.sh --surface <ref> --branch <name> [--task <id>] [--event-timeout <s>] [--total-timeout <s>]"

SURF_NUM="${SURFACE#surface:}"
PLUGIN_FILE="$HOME/.config/opencode/plugins/cmux-session.js"
EVENT_PID=""; POLL_PID=""
METHOD=""; SUCCESS=1
TMPDIR="$(mktemp -d)"
trap 'kill $EVENT_PID $POLL_PID 2>/dev/null; rm -rf "$TMPDIR"' EXIT

# ── graceful degradation check (design §5.6) ──
EVENT_ENABLED=false
if command -v cmux &>/dev/null && [[ -f "$PLUGIN_FILE" ]]; then
  EVENT_ENABLED=true
else
  if command -v cmux &>/dev/null; then
    log "WARN: cmux hooks not installed ($PLUGIN_FILE missing) → event path disabled, using poll fallback"
  else
    log "WARN: cmux not available → event path disabled, using poll fallback"
  fi
fi

# ── background event listener (design §3.2 step 1) ──
if $EVENT_ENABLED; then
  # UNVERIFIED: grep pattern covers both lifecycle idle (WAIT_WITHOUT_SLEEP.md)
  # and agent.hook.Stop (observed in audit log). CTB-DONE may appear in
  # notification bodies in the live stream even though they are redacted in
  # the audit log.
  timeout "$EVENT_TIMEOUT" bash -c "
    cmux events --category agent --category notification --no-heartbeat \
      | grep -m1 -E '(lifecycle.*idle|hook_event_name.*Stop|CTB-DONE.*task=)'
  " 2>/dev/null &
  EVENT_PID=$!
fi

# ── background fallback poller (design §3.2 step 2) ──
"$DIR/poll-push.sh" "$BRANCH" 60 "$TOTAL_TIMEOUT" > "$TMPDIR/poll.out" 2>&1 &
POLL_PID=$!

# ── wait loop: poll both PIDs until one finishes or total timeout expires ──
# kill -0 checks process liveness without sending a signal.
ELAPSED=0
while (( ELAPSED < TOTAL_TIMEOUT )); do
  # Check if poller finished (push detected or poll timeout)
  if ! kill -0 $POLL_PID 2>/dev/null; then
    if grep -q "^PUSHED " "$TMPDIR/poll.out" 2>/dev/null; then
      $EVENT_ENABLED && kill $EVENT_PID 2>/dev/null || true
      METHOD=poll
      SUCCESS=0
      break
    fi
    # Poller exited without PUSHED (its own timeout). If events are disabled,
    # that's a hard fail. Otherwise, keep waiting for the event listener.
    if ! $EVENT_ENABLED; then
      SUCCESS=1
      break
    fi
    # Poller failed but event listener may still succeed — reset poll PID
    # so we don't keep checking it, and keep waiting.
    POLL_PID=""
  fi

  # Check if event listener finished (grep matched)
  if $EVENT_ENABLED && [[ -n "$EVENT_PID" ]] && ! kill -0 $EVENT_PID 2>/dev/null; then
    kill $POLL_PID 2>/dev/null || true
    METHOD=event
    SUCCESS=0
    break
  fi

  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

# ── fell out of loop without a winner: total timeout ──
if [[ -z "$METHOD" ]]; then
  $EVENT_ENABLED && kill $EVENT_PID 2>/dev/null || true
  kill $POLL_PID 2>/dev/null || true
  # Last-resort check: poll may have finished between iterations
  if grep -q "^PUSHED " "$TMPDIR/poll.out" 2>/dev/null; then
    METHOD=poll
    SUCCESS=0
  fi
fi

# ── output ──
if [[ $SUCCESS -eq 0 ]]; then
  echo "COMPLETE surface=$SURFACE branch=$BRANCH method=${METHOD:-poll}"
  exit 0
else
  echo "TIMEOUT surface=$SURFACE branch=$BRANCH after ${TOTAL_TIMEOUT}s"
  exit 1
fi
