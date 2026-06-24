root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/methods.sh"
. "$root/lib/report.sh"
plan='[{"plugin":"superpowers","agent":"claude","coverage":"native","method":"claude-plugin","conflict_policy":"skip","requires":["claude","jq"],"safety":{},"args":{"marketplace_src":"obra/superpowers-marketplace","marketplace_name":"superpowers-marketplace","plugin":"superpowers"},"manual":null},{"plugin":"superpowers","agent":"cursor","coverage":"manual","method":"manual","conflict_policy":"skip","requires":[],"safety":{},"args":{},"manual":{"reason":"no cli","steps":["Open chat","Run /add-plugin superpowers"]}}]'
out="$(report_plan "$plan")"
assert_contains "$out" "superpowers/claude [native]" "header native"
assert_contains "$out" "claude plugin install superpowers@superpowers-marketplace" "shows command"
assert_contains "$out" "superpowers/cursor [manual]" "header manual"
assert_contains "$out" "Run /add-plugin superpowers" "manual step shown"
