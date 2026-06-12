#!/usr/bin/env bash
# test_repo_hygiene.sh — hard-gate: .task-spec.md must be gitignored and
# never tracked, preventing worker-spec leaks into the repo.
#
# Every worker worktree gets a .task-spec.md at its root. If it's not
# gitignored, a stray `git add` can leak task spec content (secrets, URLs,
# internal paths) into the shared repo history.
#
# macOS bash 3.2 compatible.
set -euo pipefail

FAILURES=0

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILURES=$((FAILURES + 1)); }

echo "=== Test: repo hygiene — .task-spec.md gating ==="

# ── Case 1: .task-spec.md is gitignored ───────────────────────────────
echo "  checking: .task-spec.md gitignored"
if git check-ignore .task-spec.md >/dev/null 2>&1; then
  pass ".task-spec.md is gitignored"
else
  fail ".task-spec.md is NOT gitignored — add to .gitignore"
fi

# ── Case 2: .task-spec.md is NOT tracked ──────────────────────────────
echo "  checking: .task-spec.md not tracked"
TRACKED="$(git ls-files .task-spec.md 2>/dev/null)"
if [[ -z "$TRACKED" ]]; then
  pass ".task-spec.md is not tracked by git"
else
  fail ".task-spec.md IS tracked by git — remove with: git rm --cached .task-spec.md"
fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All repo hygiene tests PASSED"
  exit 0
else
  echo "$FAILURES repo hygiene test(s) FAILED"
  exit 1
fi
