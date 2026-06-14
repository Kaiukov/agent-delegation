#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPAWN_BIN="$PLUGIN_ROOT/bin/orch-spawn"

if [[ ! -x "$SPAWN_BIN" ]]; then
  echo "FAIL: orch-spawn not found at $SPAWN_BIN"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

REPO_ROOT="$TMPDIR/host-repo"
WORKTREE_PATH="$TMPDIR/wt-issue-157-backend"
STUB_LOG="$TMPDIR/orch-tmux-spawn.log"
mkdir -p "$TMPDIR/bin" "$REPO_ROOT"

git -C "$REPO_ROOT" init -b main -q
mkdir -p "$REPO_ROOT/app"
echo "seed" > "$REPO_ROOT/app/README.md"
git -C "$REPO_ROOT" config user.email "test@test"
git -C "$REPO_ROOT" config user.name "Test"
git -C "$REPO_ROOT" add -A
git -C "$REPO_ROOT" commit -qm "init"
git -C "$REPO_ROOT" worktree add -q -b issue-157-backend "$WORKTREE_PATH" HEAD

cat > "$TMPDIR/bin/orch-tmux-spawn" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${ORCH_TMUX_SPAWN_LOG:?}"
printf 'stubbed orch-tmux-spawn\n'
EOF
chmod +x "$TMPDIR/bin/orch-tmux-spawn"

output="$(
  cd "$TMPDIR"
  ORCH_REPO_ROOT="$REPO_ROOT" \
  ORCH_TMUX_SPAWN="$TMPDIR/bin/orch-tmux-spawn" \
  ORCH_TMUX_SPAWN_LOG="$STUB_LOG" \
  "$SPAWN_BIN" --role backend --task-id 157
)"

args=()
while IFS= read -r line; do
  args+=("$line")
done < "$STUB_LOG"

arg_value() {
  local want="$1" i
  for ((i = 0; i < ${#args[@]} - 1; i++)); do
    if [[ "${args[$i]}" == "$want" ]]; then
      printf '%s' "${args[$((i + 1))]}"
      return 0
    fi
  done
  return 1
}

expected_worktree="$(cd "$TMPDIR" && pwd -P)/wt-issue-157-backend"
actual_worktree="$(arg_value --worktree)"
actual_repo_root="$(arg_value --repo-root)"
expected_repo_root="$(cd "$REPO_ROOT" && pwd -P)"

if [[ "$output" != "stubbed orch-tmux-spawn" ]]; then
  echo "FAIL: unexpected output: $output"
  exit 1
fi

if [[ "$actual_worktree" == "$expected_worktree" && "$actual_repo_root" == "$expected_repo_root" ]]; then
  echo "PASS: portable target repo resolution"
else
  echo "FAIL: worktree=$actual_worktree repo-root=$actual_repo_root"
  exit 1
fi

if grep -q "$PLUGIN_ROOT" "$STUB_LOG"; then
  echo "FAIL: plugin repo path leaked into repo-root args"
  exit 1
fi

echo "All orch-portability tests passed."
