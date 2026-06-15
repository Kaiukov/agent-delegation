#!/usr/bin/env bash
# Tests for role-config — the single source of truth for worker role profiles
# (reads prompts/pi/roles/<role>.md frontmatter + .tasks/config.json overrides).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RC="$REPO_ROOT/bin/role-config"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=$((fail+1)); }

[[ -x "$RC" ]] || { echo "FAIL: role-config not executable at $RC"; exit 1; }

# 1. list-profiles includes base roles + variants
list="$("$RC" --list-profiles)"
for p in backend docs frontend frontend-top repo-scout review reviewer backend-fast test tiny-patch; do
  grep -qx "$p" <<<"$list" && pass "list has $p" || bad "list missing $p"
done

# 2. field resolution from frontmatter (single source)
assert_field() { # profile field expected
  local got; got="$("$RC" --get-profile "$1" --json | jq -r ".$2")"
  [[ "$got" == "$3" ]] && pass "$1.$2=$3" || bad "$1.$2='$got' expected '$3'"
}
assert_field backend      provider zai
assert_field backend      model    glm-4.7
assert_field backend      thinking medium
assert_field backend      tools    "read,bash,edit,write,grep,find,ls"
assert_field docs         model    glm-4.5-air
assert_field docs         thinking low
assert_field frontend-top model    glm-5.1
assert_field repo-scout   tools    "read,bash,grep,find,ls"

# 3. variant: backend-fast = base backend + thinking low (one source, overridden field)
assert_field backend-fast model    glm-4.7
assert_field backend-fast thinking low
assert_field backend-fast role     backend

# 4. alias: reviewer → review (role + read-only tools)
assert_field reviewer role  review
assert_field reviewer tools "read,bash,grep,find,ls"

# 5. selectors
[[ "$("$RC" --get-profile docs --model)" == "glm-4.5-air" ]] && pass "selector --model" || bad "selector --model"
[[ "$("$RC" --get-profile docs --provider)" == "zai" ]] && pass "selector --provider" || bad "selector --provider"

# 6. unknown profile → non-zero exit
if "$RC" --get-profile nope --json >/dev/null 2>&1; then bad "unknown should exit non-zero"; else pass "unknown exits non-zero"; fi

# 7. .tasks/config.json overlay (per-project override, deep-merge per field)
TMP="$(mktemp -d)"; mkdir -p "$TMP/.tasks"
echo '{"profiles":{"backend":{"model":"glm-5.1","thinking":"high"}}}' > "$TMP/.tasks/config.json"
ov_model="$( (cd "$TMP" && "$RC" --get-profile backend --model) )"
ov_think="$( (cd "$TMP" && "$RC" --get-profile backend --thinking) )"
ov_prov="$(  (cd "$TMP" && "$RC" --get-profile backend --provider) )"
rm -rf "$TMP"
[[ "$ov_model" == "glm-5.1" && "$ov_think" == "high" && "$ov_prov" == "zai" ]] \
  && pass "overlay deep-merges model+thinking, keeps provider" \
  || bad "overlay: model=$ov_model thinking=$ov_think provider=$ov_prov"

if (( fail == 0 )); then echo "All role-config tests passed."; else echo "role-config: $fail failure(s)"; exit 1; fi
