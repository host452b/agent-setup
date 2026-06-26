root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/manifest.sh"
assert_ok   manifest_validate "$root/manifest.json"
assert_fail manifest_validate "$root/tests/fixtures/bad-manifest.json"
# spot-check real data
assert_eq "claude-plugin" \
  "$(jq -r '.plugins.superpowers.targets.claude.method' "$root/manifest.json")" "superpowers claude method"
assert_eq "manual" \
  "$(jq -r '.plugins.superpowers.targets.cursor.coverage' "$root/manifest.json")" "superpowers cursor coverage"
assert_eq "host452b/polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.claude.args.marketplace_src' "$root/manifest.json")" "prompt-polish claude marketplace"
assert_eq "polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.claude.args.marketplace_name' "$root/manifest.json")" "prompt-polish claude marketplace name"
assert_eq "polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.claude.args.plugin' "$root/manifest.json")" "prompt-polish claude skill name"
assert_eq "polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.claude.checks.after[0].name' "$root/manifest.json")" "prompt-polish claude installed plugin name"
assert_eq "host452b/polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.codex.args.marketplace_src' "$root/manifest.json")" "prompt-polish codex marketplace"
assert_eq "polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.codex.args.marketplace_name' "$root/manifest.json")" "prompt-polish codex marketplace name"
assert_eq "polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.codex.args.plugin' "$root/manifest.json")" "prompt-polish codex plugin name"
assert_eq "polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.codex.checks.after[0].name' "$root/manifest.json")" "prompt-polish codex installed plugin name"
assert_eq "https://github.com/host452b/polish.git" \
  "$(jq -r '.plugins["prompt-polish"].targets.cursor.args.repo' "$root/manifest.json")" "prompt-polish cursor repo"
assert_eq '${HOME}/.agent-setup/repos/polish' \
  "$(jq -r '.plugins["prompt-polish"].targets.cursor.args.clone_dest' "$root/manifest.json")" "prompt-polish cursor clone dest"
assert_eq "skills/prompt-polish" \
  "$(jq -r '.plugins["prompt-polish"].targets.cursor.args.link_subpath' "$root/manifest.json")" "prompt-polish cursor link subpath"
assert_eq '${HOME}/.cursor/skills/prompt-polish' \
  "$(jq -r '.plugins["prompt-polish"].targets.cursor.args.link' "$root/manifest.json")" "prompt-polish cursor skill link"

# Test manifest_resolve_plan
agents="$(cat "$root/tests/fixtures/agents-present.json")"
plan="$(manifest_resolve_plan "$root/manifest.json" darwin "$agents")"
# claude present -> superpowers/claude in plan
assert_eq "1" "$(echo "$plan" | jq '[.[]|select(.plugin=="superpowers" and .agent=="claude")]|length')" "sp claude present"
# codex absent -> no codex entries
assert_eq "0" "$(echo "$plan" | jq '[.[]|select(.agent=="codex")]|length')" "no codex when absent"
# cursor present -> ui-ux-pro-max/cursor present, method npm-cli
assert_eq "npm-cli" "$(echo "$plan" | jq -r '.[]|select(.plugin=="ui-ux-pro-max" and .agent=="cursor")|.method')" "ui-ux cursor method"
# every entry carries coverage
assert_eq "0" "$(echo "$plan" | jq '[.[]|select(.coverage==null)]|length')" "all have coverage"
assert_fail manifest_resolve_plan "$root/nonexistent-manifest-xyz.json" darwin "$agents"
