#!/usr/bin/env bash
# install.sh — manifest-driven unix installer for coding agents + plugins.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/prereqs.sh"
. "$HERE/lib/paths.sh"
. "$HERE/lib/detect.sh"
. "$HERE/lib/manifest.sh"
. "$HERE/lib/privilege.sh"
. "$HERE/lib/checks.sh"
. "$HERE/lib/methods.sh"
. "$HERE/lib/report.sh"

# pure: interpret a confirm answer. Default (empty) = yes; only n/no declines.
_confirm_answer() { case "$1" in n|N|no|NO) return 1 ;; *) return 0 ;; esac; }

# confirm <prompt> -> 0 yes / 1 no.
# Default is YES, auto-confirmed after a 3s countdown unless the user presses n.
# --yes skips the wait; --non-interactive declines (safe for CI); no terminal
# auto-confirms (the piped one-liner's default).
confirm() {
  [ "$NON_INTERACTIVE" = "1" ] && return 1
  [ "$ASSUME_YES" = "1" ] && return 0
  [ -r /dev/tty ] || return 0
  local a="" s
  for s in 3 2 1; do
    printf '\r%s  auto-yes in %ds (press n to decline) ' "$1" "$s" > /dev/tty
    if read -t 1 -r a < /dev/tty; then break; fi
    a=""
  done
  printf '\n' > /dev/tty
  _confirm_answer "$a"
}

# _exec_entry <entry_json> — real side effects per method.
# Returns: 0 success · 3 skipped/not-applicable · other = failure.
_exec_entry() {
  local e="$1" m; m="$(jq -r '.method' <<<"$e")"
  case "$m" in
    claude-plugin)
      claude plugin marketplace add "$(_arg "$e" '.args.marketplace_src')" \
      && claude plugin install "$(_arg "$e" '.args.plugin')@$(_arg "$e" '.args.marketplace_name')" ;;
    codex-plugin)
      if ! codex plugin add --help >/dev/null 2>&1; then
        echo "  codex 'plugin add' is unsupported by this codex version — upgrade codex, or install '$(_arg "$e" '.args.plugin')' via codex's /plugins UI. Skipping." >&2
        return 3
      fi
      codex plugin marketplace add "$(_arg "$e" '.args.marketplace_src')" \
      && codex plugin add "$(_arg "$e" '.args.plugin')" ;;
    shell-installer)
      local tmp; tmp="$(mktemp)"; curl -fsSL "$(_arg "$e" '.args.url_unix')" -o "$tmp" && bash "$tmp"; rm -f "$tmp" ;;
    npx-skills)
      npx -y skills add "$(_arg "$e" '.args.repo')" ;;
    git-setup)
      local repo dest sa; repo="$(_arg "$e" '.args.repo')"; dest="$(_expand "$(_arg "$e" '.args.dest')")"; sa="$(_arg "$e" '.args.setup_args')"
      [ -d "$dest/.git" ] || git clone --depth 1 "$repo" "$dest"
      ( cd "$dest" && ./setup $sa ) ;;
    npm-cli)
      local ensure; ensure="$(_arg "$e" '.args.ensure')"
      if [ -n "$ensure" ] && ! tool_present "$ensure"; then sh -c "$(_arg "$e" '.args.ensure_install')" || return 1; fi
      # run from $HOME so a project-scoped CLI lands in the user's home dirs
      ( cd "$HOME" && sh -c "$(_arg "$e" '.args.command')" ) ;;
    od-mcp)
      local odp; odp="$(tool_realpath od)"
      if [ -z "$odp" ]; then
        echo "  open-design: 'od' not installed — skipping (install open-design first; see docs)" >&2; return 3
      fi
      case "$odp" in
        *"$(_arg "$e" '.args.expected_substr')"*) od mcp install "$(_arg "$e" '.args.agent')" ;;
        *) echo "  open-design: 'od' resolves to $odp (shadowed, not open-design) — skipping" >&2; return 3 ;;
      esac ;;
    *) echo "no executor for method: $m" >&2; return 1 ;;
  esac
}

MODE="install"          # install | dry-run | plan | status | check-prereqs
DO_INSTALL_PREREQS=0
F_AGENT=""; F_PLUGIN=""; F_METHOD=""
AGENTS_ONLY=0; ASSUME_YES=0; NON_INTERACTIVE=0

usage() { grep -E '^\s+--' "$HERE/install.sh" | sed 's/) .*//' >&2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|--plan)   MODE="dry-run" ;;
    --status)           MODE="status" ;;
    --check-prereqs)    MODE="check-prereqs" ;;
    --install-prereqs)  DO_INSTALL_PREREQS=1 ;;
    --agent)            F_AGENT="$2"; shift ;;
    --plugin)           F_PLUGIN="$2"; shift ;;
    --only-method)      F_METHOD="$2"; shift ;;
    --agents-only)      AGENTS_ONLY=1 ;;
    --yes)              ASSUME_YES=1 ;;
    --non-interactive)  NON_INTERACTIVE=1 ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

# 1. detect OS  (overridable for tests)
OS="${AGENT_SETUP_FORCE_OS:-$(detect_os)}"

# 1b. install prereqs if requested
if [ "$DO_INSTALL_PREREQS" = "1" ]; then
  prereqs_install jq git node bun
fi

# 2-3. jq gate
require_jq || exit 2

if [ "$MODE" = "check-prereqs" ]; then
  prereqs_report jq git node bun claude codex cursor-agent
  exit 0
fi

# 4. validate manifest
MANIFEST="$HERE/manifest.json"
manifest_validate "$MANIFEST" || { echo "manifest validation failed" >&2; exit 1; }

# 5. resolve present agents (overridable for tests)
AGENTS_JSON="${AGENT_SETUP_FAKE_AGENTS:-$(detect_agents_json "$OS")}"

# 6. resolve plan + apply filters
PLAN="$(manifest_resolve_plan "$MANIFEST" "$OS" "$AGENTS_JSON")"
[ -n "$F_AGENT" ]  && PLAN="$(jq --arg a "$F_AGENT"  '[.[]|select(.agent==$a)]'  <<<"$PLAN")"
[ -n "$F_PLUGIN" ] && PLAN="$(jq --arg p "$F_PLUGIN" '[.[]|select(.plugin==$p)]' <<<"$PLAN")"
[ -n "$F_METHOD" ] && PLAN="$(jq --arg m "$F_METHOD" '[.[]|select(.method==$m)]' <<<"$PLAN")"

if [ "$MODE" = "dry-run" ]; then
  echo "OS: $OS"
  report_plan "$PLAN"
  exit 0
fi

if [ "$MODE" = "status" ]; then
  echo "OS: $OS"
  n="$(jq 'length' <<<"$PLAN")"; i=0
  while [ "$i" -lt "$n" ]; do
    e="$(jq -c ".[$i]" <<<"$PLAN")"
    if ! checks_has_after "$e"; then st="no-check"; elif checks_run_after "$e"; then st="OK"; else st="missing"; fi
    printf '%s/%s: %s\n' "$(jq -r .plugin <<<"$e")" "$(jq -r .agent <<<"$e")" "$st"
    i=$((i + 1))
  done
  exit 0
fi

# 7. privilege preflight
PRIV="$(priv_summarize "$PLAN")"
if [ -n "$PRIV" ]; then
  echo "Privilege requirements:"; echo "$PRIV"
  if [ "$NON_INTERACTIVE" = "1" ]; then echo "non-interactive: refusing privileged steps" >&2; exit 3; fi
fi

# 8. agents step 1 (binary install, download-then-run) unless plugins-only filters set
if [ -z "$F_PLUGIN" ] && [ -z "$F_METHOD" ]; then
  for a in claude codex cursor; do
    [ -n "$F_AGENT" ] && [ "$F_AGENT" != "$a" ] && continue
    bin="$(jq -r --arg a "$a" '.agents[$a].binary' "$MANIFEST")"
    if tool_present "$bin"; then echo "agent $a present ($(tool_realpath "$bin"))"; continue; fi
    url="$(jq -r --arg a "$a" --arg os "$OS" '.agents[$a].install[$os]' "$MANIFEST")"
    echo "installing agent $a from $url"
    confirm "  proceed?" || { echo "agent $a skipped"; continue; }
    tmp="$(mktemp)"; curl -fsSL "$url" -o "$tmp" && bash "$tmp"; rm -f "$tmp"
  done
fi
[ "$AGENTS_ONLY" = "1" ] && exit 0

# 9. execute plan entries
S_OK=""; S_SKIP=""; S_MANUAL=""; S_FAIL=""
n="$(jq 'length' <<<"$PLAN")"; i=0
while [ "$i" -lt "$n" ]; do
  e="$(jq -c ".[$i]" <<<"$PLAN")"; i=$((i + 1))
  label="$(jq -r '.plugin' <<<"$e")/$(jq -r '.agent' <<<"$e")"
  if checks_has_after "$e" && checks_run_after "$e"; then echo "[$label] already satisfied — skip"; S_OK="$S_OK $label"; continue; fi
  if [ "$(jq -r '.method' <<<"$e")" = "manual" ]; then
    echo "[$label] MANUAL:"; report_manual_steps "$e"; S_MANUAL="$S_MANUAL $label"; continue
  fi
  hi="$(jq -r '(.safety.executes_remote_code // false) or (.safety.requires_admin // false)' <<<"$e")"
  if [ "$hi" = "true" ]; then
    echo "[$label] high-risk:"; method_plan "$e" | sed 's/^/    $ /'
    confirm "[$label] proceed?" || { echo "[$label] skipped"; S_SKIP="$S_SKIP $label"; continue; }
  fi
  echo "[$label] executing:"; method_plan "$e" | sed 's/^/    $ /'
  _exec_entry "$e"; rc=$?
  case "$rc" in
    0) S_OK="$S_OK $label" ;;
    3) echo "[$label] skipped"; S_SKIP="$S_SKIP $label" ;;
    *) echo "[$label] FAILED" >&2; S_FAIL="$S_FAIL $label" ;;
  esac
done

echo ""
echo "=== summary ==="
echo "ok:     ${S_OK:- (none)}"
echo "skipped:${S_SKIP:- (none)}"
echo "manual: ${S_MANUAL:- (none)}"
echo "failed: ${S_FAIL:- (none)}"
[ -z "$S_FAIL" ]
