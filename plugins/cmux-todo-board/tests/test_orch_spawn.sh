#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCH_SPAWN="$REPO_ROOT/plugins/cmux-todo-board/bin/orch-spawn"
REAL_REPO="/Users/oleksandrkaiukov/Code/claude-code-cmux-todo-plugin"

if [[ ! -x "$ORCH_SPAWN" ]]; then
  echo "FAIL: orch-spawn not found at $ORCH_SPAWN"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

STUB_LOG="$TMPDIR/orch-tmux-spawn.log"
STUB_OUT="$TMPDIR/orch-tmux-spawn.out"
mkdir -p "$TMPDIR/bin"

cat > "$TMPDIR/bin/orch-tmux-spawn" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${ORCH_TMUX_SPAWN_LOG:?}"
printf 'stubbed orch-tmux-spawn\n'
EOF
chmod +x "$TMPDIR/bin/orch-tmux-spawn"

export ORCH_TMUX_SPAWN="$TMPDIR/bin/orch-tmux-spawn"
export ORCH_TMUX_SPAWN_LOG="$STUB_LOG"

ISSUE="4711"
ROLE="backend"
BRANCH="issue-${ISSUE}-${ROLE}"
WORKTREE="$(dirname "$REPO_ROOT")/wt-${BRANCH}"
SESSION="orch-${ISSUE}-${ROLE}"

if [[ -d "$REAL_REPO" ]]; then
  before_worktrees="$(git -C "$REAL_REPO" worktree list --porcelain | awk '/^worktree / {print $2}' | grep '/wt-issue-' || true)"
else
  before_worktrees=""
fi

output="$($ORCH_SPAWN --role "$ROLE" --task-id "$ISSUE")"
printf '%s\n' "$output" > "$STUB_OUT"

expected_args=(
  --issue "$ISSUE"
  --worktree "$WORKTREE"
  --profile "$ROLE"
  --role "$ROLE"
  --session "$SESSION"
)
actual_args=()
while IFS= read -r line; do
  actual_args+=("$line")
done < "$STUB_LOG"

if [[ "$output" == "stubbed orch-tmux-spawn" ]]; then
  echo "PASS: dispatcher delegates to orch-tmux-spawn"
else
  echo "FAIL: unexpected dispatcher output: $output"
  exit 1
fi

if [[ ${#actual_args[@]} -eq ${#expected_args[@]} ]]; then
  mismatch=0
  for i in "${!expected_args[@]}"; do
    if [[ "${actual_args[$i]}" != "${expected_args[$i]}" ]]; then
      mismatch=1
      break
    fi
  done
  if [[ $mismatch -eq 0 ]]; then
    echo "PASS: dispatcher arguments and naming contract"
  else
    echo "FAIL: dispatcher args mismatch"
    printf 'expected: %q\n' "${expected_args[@]}"
    printf 'actual:   %q\n' "${actual_args[@]}"
    exit 1
  fi
else
  echo "FAIL: expected ${#expected_args[@]} args, got ${#actual_args[@]}"
  printf 'expected: %q\n' "${expected_args[@]}"
  printf 'actual:   %q\n' "${actual_args[@]}"
  exit 1
fi

if [[ -d "$REAL_REPO" ]]; then
  after_worktrees="$(git -C "$REAL_REPO" worktree list --porcelain | awk '/^worktree / {print $2}' | grep '/wt-issue-' || true)"
  if [[ "$before_worktrees" == "$after_worktrees" ]]; then
    echo "PASS: no new real wt-issue worktrees were created"
  else
    echo "FAIL: real worktree list changed"
    printf 'before:\n%s\n' "$before_worktrees"
    printf 'after:\n%s\n' "$after_worktrees"
    exit 1
  fi
fi

echo "All orch-spawn tests passed."
