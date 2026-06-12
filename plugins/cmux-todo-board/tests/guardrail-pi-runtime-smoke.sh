#!/usr/bin/env bash
# guardrail-pi-runtime-smoke.sh — hard-gate: load every .pi/extensions/*.ts in
# pi and verify no import-resolution or load errors.
#
# Lesson from #91: the previous test suite only checked data/wiring and never
# loaded the extension in pi, so the "Cannot find module 'yaml'" crash was
# not caught. This guardrail loads each extension in pi (non-interactive) and
# asserts clean startup. If pi is absent the guardrail SKIPs gracefully.
#
# macOS bash 3.2 compatible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EXT_DIR="$GIT_ROOT/.pi/extensions"
FAILURES=0

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILURES=$((FAILURES + 1)); }

echo "=== guardrail: pi runtime smoke for all .pi/extensions/*.ts ==="

# ── Pre-flight: pi must be available ──────────────────────────────────
if ! command -v pi &>/dev/null; then
  echo "SKIP: pi binary not found — cannot runtime-smoke extensions"
  exit 0
fi

PI_VERSION=$(pi --version 2>/dev/null || echo "unknown")
echo "  pi version: $PI_VERSION"

if [[ ! -d "$EXT_DIR" ]]; then
  echo "SKIP: no .pi/extensions directory"
  exit 0
fi

# Collect every extension file
shopt -s nullglob
ext_files=( "$EXT_DIR"/*.ts )
shopt -u nullglob

if [[ ${#ext_files[@]} -eq 0 ]]; then
  echo "SKIP: no .ts extension files found"
  exit 0
fi

# ── Smoke each extension ──────────────────────────────────────────────
for ext_file in "${ext_files[@]}"; do
  local_name="${ext_file##*/}"
  ext_abs="$(cd "$(dirname "$ext_file")" && pwd)/$local_name"

  echo "  smoking: $local_name"

  # pi --no-extensions ensures ONLY this one file loads (no other ext side-effects)
  # -p = print/pipe mode, --no-session = don't persist session state
  # "say ok" is a trivial built-in to exercise the extension load path.
  pi_output="$(pi --no-extensions -e "$ext_abs" -p --no-session "say ok" 2>&1)" || pi_rc=$?
  pi_rc=${pi_rc:-0}

  # ── Assertions ──────────────────────────────────────────────────────
  had_failure=0

  if echo "$pi_output" | grep -qiE "Cannot find module|Failed to load extension|Error loading extension|MODULE_NOT_FOUND"; then
    fail "$local_name: load error in pi output"
    echo "       pi stderr/stdout:"
    echo "$pi_output" | sed 's/^/       | /'
    had_failure=1
  fi

  if [[ "$pi_rc" -ne 0 ]]; then
    fail "$local_name: pi exited non-zero (rc=$pi_rc)"
    echo "       pi stderr/stdout:"
    echo "$pi_output" | sed 's/^/       | /'
    had_failure=1
  fi

  if [[ "$had_failure" -eq 0 ]]; then
    pass "$local_name loaded cleanly (pi rc=0, no errors)"
  fi
done

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "guardrail PASSED: all extensions load cleanly in pi"
  exit 0
else
  echo "guardrail FAILED: $FAILURES extension(s) failed to load — fix before merging"
  exit 1
fi
