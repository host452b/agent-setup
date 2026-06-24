root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/methods.sh"
cp='{"method":"claude-plugin","args":{"marketplace_src":"obra/superpowers-marketplace","marketplace_name":"superpowers-marketplace","plugin":"superpowers"}}'
out="$(method_plan "$cp")"
assert_contains "$out" "claude plugin marketplace add obra/superpowers-marketplace" "claude mkt add"
assert_contains "$out" "claude plugin install superpowers@superpowers-marketplace" "claude install"

gs='{"method":"git-setup","args":{"repo":"https://github.com/garrytan/gstack.git","dest":"${HOME}/.gstack","setup_args":"--host cursor"}}'
out="$(method_plan "$gs")"
assert_contains "$out" "git clone --depth 1 https://github.com/garrytan/gstack.git" "git clone"
assert_contains "$out" "./setup --host cursor" "setup args"

sh='{"method":"shell-installer","args":{"url_unix":"https://example.com/install.sh"}}'
assert_contains "$(method_plan "$sh")" "download-then-run https://example.com/install.sh" "shell installer"

mn='{"method":"manual","manual":{"reason":"no cli"}}'
assert_contains "$(method_plan "$mn")" "MANUAL: no cli" "manual line"
