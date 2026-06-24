root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/manifest.sh"
assert_ok   manifest_validate "$root/manifest.json"
assert_fail manifest_validate "$root/tests/fixtures/bad-manifest.json"
# spot-check real data
assert_eq "claude-plugin" \
  "$(jq -r '.plugins.superpowers.targets.claude.method' "$root/manifest.json")" "superpowers claude method"
assert_eq "manual" \
  "$(jq -r '.plugins.superpowers.targets.cursor.coverage' "$root/manifest.json")" "superpowers cursor coverage"
