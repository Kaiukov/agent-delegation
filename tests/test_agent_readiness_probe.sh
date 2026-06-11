#!/usr/bin/env bash
# Tests for reflow-tolerant agent readiness probe (#54).
# Verifies that the normalized screen output + width-stable patterns match
# reflowed opencode TUI footers that the old ^-anchored patterns would miss.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_FILE="$REPO_ROOT/skills/cmux-agent-workflows/scripts/lib.sh"

if [[ ! -f "$LIB_FILE" ]]; then
  echo "FAIL: lib.sh not found at $LIB_FILE"
  exit 1
fi

# Source lib.sh for agent_ready_patterns + log/die stubs
source "$LIB_FILE"

failures=0

# Simulate the readiness check with normalization (mirrors wait_agent_ready logic)
normalize_and_match() {
  local screen="$1" kind="${2:-opencode}"
  local pattern normalized
  pattern="$(agent_ready_patterns "$kind")"
  normalized="$(printf '%s' "$screen" | tr -s ' \n' ' ')"
  grep -qE "$pattern" <<<"$normalized"
}

# ── Test 1: Normal (non-reflowed) footer matches ──
echo "=== Test 1: Normal opencode footer ==="
normal_screen='Build · DeepSeek V4 Pro     esc dismiss'
if normalize_and_match "$normal_screen"; then
  echo "PASS"
else
  echo "FAIL: normal footer should match"
  failures=$((failures + 1))
fi

# ── Test 2: Reflowed footer — Build · on one line, model on next ──
echo "=== Test 2: Reflowed footer (Build· line-break model) ==="
reflowed_screen='Build ·
DeepSeek V4 Pro     esc dismiss'
if normalize_and_match "$reflowed_screen"; then
  echo "PASS"
else
  echo "FAIL: reflowed footer should match after normalization"
  failures=$((failures + 1))
fi

# ── Test 3: OpenCode alone is not a ready signal (no model marker / esc dismiss) ──
echo "=== Test 3: Bare 'OpenCode' text is not a ready signal ==="
opencode_only='Welcome to OpenCode! Type your prompt below.'
if normalize_and_match "$opencode_only"; then
  echo "FAIL: bare OpenCode without model marker or esc dismiss should not match"
  failures=$((failures + 1))
else
  echo "PASS: bare OpenCode correctly rejected (no false positive)"
fi

# ── Test 4: Reflowed GPT model footer ──
echo "=== Test 4: Reflowed GPT footer ==="
gpt_screen='Build ·
gpt-5-codex medium     esc dismiss'
if normalize_and_match "$gpt_screen"; then
  echo "PASS"
else
  echo "FAIL: reflowed GPT footer should match"
  failures=$((failures + 1))
fi

# ── Test 5: Extreme truncation — still has esc dismiss ──
echo "=== Test 5: Truncated footer (esc dismiss survives) ==="
trunc_screen='Bu ·DeepSeek O
esc dismiss'
if normalize_and_match "$trunc_screen"; then
  echo "PASS"
else
  echo "FAIL: truncated footer with esc dismiss should match"
  failures=$((failures + 1))
fi

# ── Test 6: Model reflowed with · separator broken across lines ──
echo "=== Test 6: Dot-separator broken across lines ==="
dotbreak_screen='Build
·
DeepSeek V4 Pro     esc dismiss'
if normalize_and_match "$dotbreak_screen"; then
  echo "PASS"
else
  echo "FAIL: dot-separator broken across lines should match after normalization"
  failures=$((failures + 1))
fi

# ── Test 7: esc dismiss is the universal width-stable fallback ──
echo "=== Test 7: esc dismiss alone matches (universal fallback) ==="
esc_only_screen='some truncated stuff
esc dismiss'
if normalize_and_match "$esc_only_screen"; then
  echo "PASS"
else
  echo "FAIL: esc dismiss should match as universal fallback"
  failures=$((failures + 1))
fi

# ── Test 8: Reflow where only model marker survives ──
echo "=== Test 8: Model marker match after reflow (· GPT) ==="
gpt_reflow_screen='· GPT-5
Codex · esc dismiss'
if normalize_and_match "$gpt_reflow_screen"; then
  echo "PASS"
else
  echo "FAIL: · GPT should match after normalization"
  failures=$((failures + 1))
fi

# ── Test 9: codex readiness patterns still work ──
echo "=== Test 9: codex readiness patterns ==="
codex_screen='OpenAI Codex
gpt-5-codex medium'
codex_pattern="$(agent_ready_patterns codex)"
if echo "$codex_screen" | tr -s ' \n' ' ' | grep -qE "$codex_pattern"; then
  echo "PASS"
else
  echo "FAIL: codex readiness patterns should match"
  failures=$((failures + 1))
fi

# ── Test 10: Bare opencode splash (no model · marker) does NOT match ──
echo "=== Test 10: Bare splash without model marker should not match ==="
splash_screen='Welcome to OpenCode! Type your prompt below.'
if normalize_and_match "$splash_screen"; then
  echo "FAIL: bare splash without esc dismiss or model · marker should not match"
  failures=$((failures + 1))
else
  echo "PASS: bare splash correctly rejected (no false positive)"
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All agent readiness probe tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
