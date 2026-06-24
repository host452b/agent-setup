root="$(cd "$(dirname "$0")/.." && pwd)"
export AGENT_SETUP_BOOTSTRAP_NOEXEC=1
. "$root/bootstrap.sh"
assert_eq "/h/.agent-setup" "$(HOME=/h bootstrap_cache_dir)" "default cache dir"
assert_eq "/custom"         "$(AGENT_SETUP_HOME=/custom bootstrap_cache_dir)" "override cache dir"
assert_eq "git"     "$(_fetch_method_from yes)" "git when present"
assert_eq "tarball" "$(_fetch_method_from no)"  "tarball when absent"
assert_eq "git"     "$(bootstrap_fetch_method)" "machine has git"
assert_fail bootstrap_fetch /tmp/agent-setup-x nonsense-method
