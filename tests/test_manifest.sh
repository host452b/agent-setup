root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/manifest.sh"
assert_ok   manifest_validate "$root/manifest.json"
assert_fail manifest_validate "$root/tests/fixtures/bad-manifest.json"
# spot-check real data
assert_eq "claude-plugin" \
  "$(jq -r '.plugins.superpowers.targets.claude.method' "$root/manifest.json")" "superpowers claude method"
assert_eq "manual" \
  "$(jq -r '.plugins.superpowers.targets.cursor.coverage' "$root/manifest.json")" "superpowers cursor coverage"

# Test manifest_resolve_plan
agents="$(cat "$root/tests/fixtures/agents-present.json")"
plan="$(manifest_resolve_plan "$root/manifest.json" darwin "$agents")"
# claude present -> superpowers/claude in plan
assert_eq "1" "$(echo "$plan" | jq '[.[]|select(.plugin=="superpowers" and .agent=="claude")]|length')" "sp claude present"
# codex absent -> no codex entries
assert_eq "0" "$(echo "$plan" | jq '[.[]|select(.agent=="codex")]|length')" "no codex when absent"
# cursor present -> gstack/cursor present, method git-setup
assert_eq "git-setup" "$(echo "$plan" | jq -r '.[]|select(.plugin=="gstack" and .agent=="cursor")|.method')" "gstack cursor method"
# every entry carries coverage
assert_eq "0" "$(echo "$plan" | jq '[.[]|select(.coverage==null)]|length')" "all have coverage"
assert_fail manifest_resolve_plan "$root/nonexistent-manifest-xyz.json" darwin "$agents"
