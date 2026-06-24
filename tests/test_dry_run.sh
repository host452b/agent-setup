root="$(cd "$(dirname "$0")/.." && pwd)"
# Dry-run must mutate nothing and must print planned commands. Force agents present via env hook.
out="$(AGENT_SETUP_FORCE_OS=darwin AGENT_SETUP_FAKE_AGENTS='{"os":"darwin","agents":{"claude":{"present":true},"codex":{"present":true},"cursor":{"present":true,"user_dir":"/h/.config/Cursor/User","rules_dir":"/h/.config/Cursor/User/rules","mcp_config":"/h/.config/Cursor/User/mcp.json","skills_dir":"/h/.config/Cursor/User/skills"}}}' bash "$root/install.sh" --dry-run --plugin superpowers 2>&1)"
assert_contains "$out" "superpowers/claude [native]" "dry-run shows claude plan"
assert_contains "$out" "claude plugin install superpowers@superpowers-marketplace" "dry-run shows command"
assert_contains "$out" "superpowers/cursor [manual]" "dry-run shows cursor manual"
# scoping to one agent
out2="$(AGENT_SETUP_FORCE_OS=darwin AGENT_SETUP_FAKE_AGENTS='{"os":"darwin","agents":{"claude":{"present":true},"codex":{"present":false},"cursor":{"present":false}}}' bash "$root/install.sh" --dry-run --plugin superpowers --agent claude 2>&1)"
case "$out2" in *"superpowers/cursor"*) echo "FAIL: cursor should be filtered" >&2; ASSERT_FAILURES=$((ASSERT_FAILURES+1));; esac
assert_contains "$out2" "superpowers/claude" "agent filter keeps claude"
# doc existence and content
assert_ok test -f "$root/README.md"
assert_ok test -f "$root/docs/security.md"
assert_ok test -f "$root/docs/cursor.md"
assert_contains "$(cat "$root/README.md")" "--dry-run" "README documents dry-run"
assert_contains "$(cat "$root/docs/security.md")" "download-then-run" "security documents exec policy"
assert_contains "$(cat "$root/docs/cursor.md")" "best-effort" "cursor doc states best-effort"
