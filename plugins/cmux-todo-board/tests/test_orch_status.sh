#!/usr/bin/env bash
# test_orch_status.sh — orch-status output should be compact and deterministic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH_STATUS="$REPO_ROOT/bin/orch-status"

if [[ ! -f "$ORCH_STATUS" ]]; then
  echo "FAIL: orch-status not found at $ORCH_STATUS"
  exit 1
fi

run_status() {
  (cd "$TMPDIR" && bash "$ORCH_STATUS" "$@")
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ORCH_DIR="$TMPDIR/.tasks/orchestrator"

# ─── Helper: create a run dir with state ─────────────────────────────────
create_run() {
  local run_id="$1" state="$2" pid="$3" started="$4" head="${5:-}"
  local d="$ORCH_DIR/$run_id"
  mkdir -p "$d"
  echo "$state" > "$d/state"
  echo "$pid" > "$d/pid"
  echo "$started" > "$d/started"
  [[ -z "$head" ]] || echo "$head" > "$d/head"
}

echo "--- Test 1: no orchestrator dir --- (no active runs) ---"
output=$(run_status 2>/dev/null)
if [[ "$output" == "(no active runs)" ]]; then
  echo "PASS"
else
  echo "FAIL: expected '(no active runs)', got '$output'"
  exit 1
fi

# ─── Setup: create runs with various states ─────────────────────────────
NOW=$(date +%s)
create_run "run-alpha"  "running"           "1001" "$(( NOW - 30 ))"  "abc123"
create_run "run-beta"   "progressed"        "1002" "$(( NOW - 120 ))" "def456"
create_run "run-gamma"  "ready-for-verify"  "1003" "$(( NOW - 600 ))" "789abc"
create_run "run-delta"  "failed"            ""     "$(( NOW - 900 ))" ""
create_run "run-epsilon" "stalled"          "1005" "$(( NOW - 1800 ))" "deadbeef"

echo "--- Test 2: human output has header and all runs ---"
output=$(run_status 2>/dev/null)

# Should have header
if echo "$output" | grep -q "RUN_ID"; then
  echo "PASS: header present"
else
  echo "FAIL: header not found"
  echo "$output"
  exit 1
fi

# Should list all 5 run IDs
for rid in run-alpha run-beta run-gamma run-delta run-epsilon; do
  if echo "$output" | grep -q "$rid"; then
    echo "PASS: $rid present"
  else
    echo "FAIL: $rid not found in output"
    echo "$output"
    exit 1
  fi
done

# Should have a summary line
if echo "$output" | grep -q "total=.*running=.*progressed=.*ready_for_verify=.*failed=.*stalled="; then
  echo "PASS: summary line present"
else
  echo "FAIL: summary line not found"
  echo "$output"
  exit 1
fi

echo "--- Test 3: human output state values ---"
for state in running progressed ready-for-verify failed stalled; do
  if echo "$output" | grep -q "$state"; then
    echo "PASS: state '$state' present"
  else
    echo "FAIL: state '$state' not found"
    echo "$output"
    exit 1
  fi
done

echo "--- Test 4: --json output shape ---"
json_output=$(run_status --json 2>/dev/null)

# Should be valid JSON
if echo "$json_output" | jq '.' >/dev/null 2>&1; then
  echo "PASS: valid JSON"
else
  echo "FAIL: invalid JSON: $json_output"
  exit 1
fi

# Check counts
total=$(echo "$json_output" | jq -r '.counts.total')
running=$(echo "$json_output" | jq -r '.counts.running')
progressed=$(echo "$json_output" | jq -r '.counts.progressed')
ready=$(echo "$json_output" | jq -r '.counts.ready_for_verify')
failed=$(echo "$json_output" | jq -r '.counts.failed')
stalled=$(echo "$json_output" | jq -r '.counts.stalled')

if [[ "$total" == "5" && "$running" == "1" && "$progressed" == "1" && "$ready" == "1" && "$failed" == "1" && "$stalled" == "1" ]]; then
  echo "PASS: counts correct (total=5, each state=1)"
else
  echo "FAIL: counts incorrect: total=$total running=$running progressed=$progressed ready_for_verify=$ready failed=$failed stalled=$stalled"
  echo "$json_output"
  exit 1
fi

# Check runs array
runs_len=$(echo "$json_output" | jq '.runs | length')
if [[ "$runs_len" == "5" ]]; then
  echo "PASS: runs array length = 5"
else
  echo "FAIL: runs array length = $runs_len"
  echo "$json_output"
  exit 1
fi

# Check specific run
gamma_state=$(echo "$json_output" | jq -r '.runs[] | select(.run_id == "run-gamma") | .state')
gamma_pid=$(echo "$json_output" | jq -r '.runs[] | select(.run_id == "run-gamma") | .pid')
if [[ "$gamma_state" == "ready-for-verify" && "$gamma_pid" == "1003" ]]; then
  echo "PASS: run-gamma state and pid correct"
else
  echo "FAIL: run-gamma state=$gamma_state pid=$gamma_pid"
  echo "$json_output"
  exit 1
fi

# delta has no pid
delta_pid=$(echo "$json_output" | jq -r '.runs[] | select(.run_id == "run-delta") | .pid')
if [[ "$delta_pid" == "null" ]]; then
  echo "PASS: run-delta pid is null (no pid file)"
else
  echo "FAIL: run-delta pid should be null, got $delta_pid"
  exit 1
fi

echo "--- Test 5: deterministic structure and ordering ---"
output1=$(run_status 2>/dev/null)
output2=$(run_status 2>/dev/null)

# Extract run IDs and states in order (skip elapsed column which changes)
run_ids1=$(echo "$output1" | grep -E '^[a-z]' | awk '{print $1, $2}')
run_ids2=$(echo "$output2" | grep -E '^[a-z]' | awk '{print $1, $2}')
if [[ "$run_ids1" == "$run_ids2" ]]; then
  echo "PASS: deterministic run ordering and states"
else
  echo "FAIL: ordering or states differ"
  echo "--- first ---"
  echo "$run_ids1"
  echo "--- second ---"
  echo "$run_ids2"
  exit 1
fi

# Summary line should have stable counts
summary1=$(echo "$output1" | grep "^total=" | sed 's/[0-9]*s//g' | sed 's/[0-9]*m[0-9]*s//g')
summary2=$(echo "$output2" | grep "^total=" | sed 's/[0-9]*s//g' | sed 's/[0-9]*m[0-9]*s//g')
if [[ "$summary1" == "$summary2" ]]; then
  echo "PASS: deterministic summary counts"
else
  echo "FAIL: summary differs"
  exit 1
fi

echo "--- Test 6: empty .tasks/orchestrator/ dir (no run subdirs) ---"
EMPTY_TMP=$(mktemp -d)
mkdir -p "$EMPTY_TMP/.tasks/orchestrator"
empty_output=$(cd "$EMPTY_TMP" && bash "$ORCH_STATUS" 2>/dev/null)
if [[ "$empty_output" == "(no active runs)" ]]; then
  echo "PASS: empty dir reports no active runs"
else
  echo "FAIL: got '$empty_output' expected '(no active runs)'"
  rm -rf "$EMPTY_TMP"
  exit 1
fi
empty_json=$(cd "$EMPTY_TMP" && bash "$ORCH_STATUS" --json 2>/dev/null)
if echo "$empty_json" | jq -e '.counts.total == 0' >/dev/null 2>&1; then
  echo "PASS: empty --json has total=0"
else
  echo "FAIL: empty --json: $empty_json"
  rm -rf "$EMPTY_TMP"
  exit 1
fi
rm -rf "$EMPTY_TMP"

echo "--- Test 7: --help flag ---"
if bash "$ORCH_STATUS" --help 2>&1 | grep -q "Usage:"; then
  echo "PASS: --help shows usage"
else
  echo "FAIL: --help did not show usage"
  exit 1
fi

echo ""
echo "All orch-status tests passed."
