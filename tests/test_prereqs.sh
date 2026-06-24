root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/prereqs.sh"
assert_ok require_jq                       # jq is a test prerequisite
assert_ok tool_present jq
assert_fail tool_present definitely-not-a-real-binary-xyz
assert_contains "$(prereqs_report jq definitely-not-a-real-binary-xyz)" "MISSING" "report flags missing"
assert_contains "$(prereqs_report jq)" "jq:" "report names tool"
assert_ok prereqs_install jq
# install-hint: sudo only when not root
assert_eq "apt-get install -y jq"      "$(_install_hint_for apt yes jq)" "apt as root drops sudo"
assert_eq "sudo apt-get install -y jq" "$(_install_hint_for apt no jq)"  "apt non-root uses sudo"
assert_eq "brew install jq"            "$(_install_hint_for brew yes jq)" "brew never sudo"
