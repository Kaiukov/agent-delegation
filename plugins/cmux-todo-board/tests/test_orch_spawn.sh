#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ORCH_SPAWN="$REPO_ROOT/plugins/cmux-todo-board/bin/orch-spawn"

if [[ ! -x "$ORCH_SPAWN" ]]; then
  echo "FAIL: orch-spawn not found at $ORCH_SPAWN"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- Isolated host repo so worktree creation is sandboxed (never touches the real repo).
HOST="$TMPDIR/host"
mkdir -p "$HOST"
git -C "$HOST" init -q
git -C "$HOST" config user.email t@t && git -C "$HOST" config user.name t
echo seed > "$HOST/seed.txt"
git -C "$HOST" add seed.txt && git -C "$HOST" commit -qm seed
HOST="$(git -C "$HOST" rev-parse --show-toplevel)"   # canonical (macOS /private symlink)

STUB_LOG="$TMPDIR/orch-tmux-spawn.log"
mkdir -p "$TMPDIR/bin"

# Stub orch-tmux-spawn: record args, emit a marker.
cat > "$TMPDIR/bin/orch-tmux-spawn" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${ORCH_TMUX_SPAWN_LOG:?}"
printf 'stubbed orch-tmux-spawn\n'
EOF
chmod +x "$TMPDIR/bin/orch-tmux-spawn"

# Stub gh: force the .task-spec.md fallback path deterministically (no network).
cat > "$TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMPDIR/bin/gh"

export PATH="$TMPDIR/bin:$PATH"
export ORCH_TMUX_SPAWN="$TMPDIR/bin/orch-tmux-spawn"
export ORCH_TMUX_SPAWN_LOG="$STUB_LOG"
export ORCH_REPO_ROOT="$HOST"

ISSUE="4711"
ROLE="backend"
BRANCH="issue-${ISSUE}-${ROLE}"
WORKTREE="$(dirname "$HOST")/wt-${BRANCH}"
SESSION="orch-${ISSUE}-${ROLE}"

output="$($ORCH_SPAWN --role "$ROLE" --task-id "$ISSUE")"

expected_args=(
  --issue "$ISSUE"
  --worktree "$WORKTREE"
  --repo-root "$HOST"
  --model "zai/glm-4.7"
  --thinking "medium"
  --tools "read,bash,edit,write,grep,find,ls"
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

# --- New contract: orch-spawn is self-contained — it creates the worktree, the
# branch, and materializes the worker's .task-spec.md before handing off.
if [[ -d "$WORKTREE" ]]; then
  echo "PASS: worktree created"
else
  echo "FAIL: worktree not created at $WORKTREE"
  exit 1
fi

if git -C "$HOST" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "PASS: branch $BRANCH created"
else
  echo "FAIL: branch $BRANCH not created"
  exit 1
fi

if [[ -s "$WORKTREE/.task-spec.md" ]]; then
  echo "PASS: .task-spec.md materialized"
else
  echo "FAIL: .task-spec.md missing or empty"
  exit 1
fi

# Idempotency: a second dispatch must not fail when worktree/branch already exist.
if $ORCH_SPAWN --role "$ROLE" --task-id "$ISSUE" >/dev/null 2>&1; then
  echo "PASS: re-dispatch is idempotent (existing worktree/branch reused)"
else
  echo "FAIL: re-dispatch errored on existing worktree/branch"
  exit 1
fi

# Cleanup sandboxed worktree (TMPDIR trap removes the rest).
git -C "$HOST" worktree remove "$WORKTREE" --force 2>/dev/null || true

echo "All orch-spawn tests passed."
