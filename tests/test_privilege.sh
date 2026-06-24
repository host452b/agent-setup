root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/privilege.sh"
t='{"safety":{"requires_admin":true}}'
assert_eq "true"  "$(priv_target_needs_admin "$t")" "admin true"
assert_eq "false" "$(priv_target_needs_admin '{"safety":{}}')" "admin default false"
plan='[{"plugin":"a","agent":"claude","safety":{"requires_admin":true}},{"plugin":"b","agent":"codex","safety":{"may_prompt_for_sudo":true}},{"plugin":"c","agent":"cursor","safety":{}}]'
out="$(priv_summarize "$plan")"
assert_contains "$out" "a/claude" "lists admin entry"
assert_contains "$out" "b/codex"  "lists sudo entry"
case "$out" in *c/cursor*) echo "FAIL: c/cursor should not appear" >&2; ASSERT_FAILURES=$((ASSERT_FAILURES+1));; esac
