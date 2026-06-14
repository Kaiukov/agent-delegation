#!/usr/bin/env bash
# Tests orch-statusline run-record resolution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE_BIN="$PLUGIN_ROOT/bin/orch-statusline"

if [[ ! -f "$STATUSLINE_BIN" ]]; then
  echo "FAIL: orch-statusline not found at $STATUSLINE_BIN"
  exit 1
fi

failures=0
TESTDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TESTDIR"
}
trap cleanup EXIT

mkdir -p \
  "$TESTDIR/workspace/.tasks/orchestrator/runs" \
  "$TESTDIR/workspace/plugins/cmux-todo-board/.tasks/orchestrator/runs" \
  "$TESTDIR/bin"

cat > "$TESTDIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list-sessions" ]]; then
  printf 'orch-153-backend\n'
  exit 0
fi
echo "unsupported tmux mock call: $*" >&2
exit 1
EOF
chmod +x "$TESTDIR/bin/tmux"

cat > "$TESTDIR/workspace/.tasks/orchestrator/runs/153-backend-20260614T143738Z.json" <<'EOF'
{
  "model": "openai-codex/gpt-5.4-mini",
  "task": "old stale run",
  "status": "stalled"
}
EOF

cat > "$TESTDIR/workspace/plugins/cmux-todo-board/.tasks/orchestrator/runs/153-backend-20260614T152127Z.json" <<'EOF'
{
  "model": "openai-codex/gpt-5.4-mini",
  "task": "new live run",
  "status": "running"
}
EOF

echo "=== Test 1: prefer plugin-root run records over stale workspace-root records ==="
output="$(
  cd "$TESTDIR/workspace"
  export PATH="$TESTDIR/bin:$PATH"
  export CLAUDE_PLUGIN_ROOT="$TESTDIR/workspace/plugins/cmux-todo-board"
  printf '{"cwd":"%s"}\n' "$PWD" | "$STATUSLINE_BIN"
)"
if [[ "$output" == "🤖 orch-153-backend · openai-codex/gpt-5.4-mini · new live run [running]" ]]; then
  echo "PASS"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

echo "=== Test 2: fallback walk-up still works for legacy layout ==="
rm -rf "$TESTDIR/workspace/plugins/cmux-todo-board/.tasks"
mkdir -p "$TESTDIR/empty-plugin-root"
output="$(
  cd "$TESTDIR/workspace"
  export PATH="$TESTDIR/bin:$PATH"
  export CLAUDE_PLUGIN_ROOT="$TESTDIR/empty-plugin-root"
  printf '{"cwd":"%s"}\n' "$PWD" | "$STATUSLINE_BIN"
)"
if [[ "$output" == "🤖 orch-153-backend · openai-codex/gpt-5.4-mini · old stale run [stalled]" ]]; then
  echo "PASS"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

echo "=== Test 3: completed runs are reported once after tmux sessions disappear ==="
mkdir -p "$TESTDIR/quiet-plugin-root/.tasks/orchestrator/runs"
cat > "$TESTDIR/quiet-plugin-root/.tasks/orchestrator/runs/153-watch-20260614T160000Z.json" <<'EOF'
{
  "agent": "orch-153-watch",
  "model": "openai-codex/gpt-5.4-mini",
  "task": "watch finished",
  "status": "done"
}
EOF
cat > "$TESTDIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list-sessions" ]]; then
  exit 0
fi
echo "unsupported tmux mock call: $*" >&2
exit 1
EOF
chmod +x "$TESTDIR/bin/tmux"
output="$(
  cd "$TESTDIR/workspace"
  export PATH="$TESTDIR/bin:$PATH"
  export CLAUDE_PLUGIN_ROOT="$TESTDIR/quiet-plugin-root"
  printf '{"cwd":"%s"}\n' "$PWD" | "$STATUSLINE_BIN"
)"
if [[ "$output" == "✅ orch-153-watch · openai-codex/gpt-5.4-mini · watch finished [done]" ]]; then
  echo "PASS"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi
reported_at="$(jq -r '.reported_at // empty' "$TESTDIR/quiet-plugin-root/.tasks/orchestrator/runs/153-watch-20260614T160000Z.json")"
if [[ -n "$reported_at" ]]; then
  echo "PASS: reported_at acknowledged"
else
  echo "FAIL: reported_at missing"
  failures=$((failures + 1))
fi
output="$(
  cd "$TESTDIR/workspace"
  export PATH="$TESTDIR/bin:$PATH"
  export CLAUDE_PLUGIN_ROOT="$TESTDIR/quiet-plugin-root"
  printf '{"cwd":"%s"}\n' "$PWD" | "$STATUSLINE_BIN"
)"
if [[ "$output" == "🟢 orchestrator idle — no agents running" ]]; then
  echo "PASS: completed run no longer repeats"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All orch statusline tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
