root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/checks.sh"
tmp="$(mktemp -d)"
echo '{"a":{"b":1}}' > "$tmp/x.json"
assert_ok   check_eval "$(jq -n --arg n jq '{type:"command_exists",name:$n}')"
assert_fail check_eval '{"type":"command_exists","name":"nope-xyz-123"}'
assert_ok   check_eval "$(jq -n --arg p "$tmp/x.json" '{type:"file_exists",path:$p}')"
assert_fail check_eval "$(jq -n --arg p "$tmp/none" '{type:"file_exists",path:$p}')"
assert_ok   check_eval "$(jq -n --arg p "$tmp" '{type:"dir_exists",path:$p}')"
assert_ok   check_eval "$(jq -n --arg p "$tmp/x.json" '{type:"json_path_exists",path:$p,query:".a.b"}')"
assert_fail check_eval "$(jq -n --arg p "$tmp/x.json" '{type:"json_path_exists",path:$p,query:".a.zzz"}')"
# no after-checks => success
assert_ok checks_run_after '{"checks":{}}'
rm -rf "$tmp"
