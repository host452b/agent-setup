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
  local warn=$'\033[30;43;5m' off=$'\033[0m'   # black-on-yellow, blinking
  for s in 3 2 1; do
    printf '\r%s  %s auto-yes in %ds %s (press n to decline) ' "$1" "$warn" "$s" "$off" > /dev/tty
    if read -t 1 -r a < /dev/tty; then break; fi
    a=""
  done
  printf '\r\033[K%s  proceeding...\n' "$1" > /dev/tty
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
      local cp_plugin; cp_plugin="$(_arg "$e" '.args.plugin')"
      codex plugin marketplace add "$(_arg "$e" '.args.marketplace_src')" >/dev/null 2>&1 || true
      if codex plugin add "$cp_plugin" 2>/dev/null; then return 0; fi
      echo "  codex 'plugin add' unsupported by this codex version — upgrade codex (npm i -g @openai/codex) or install '$cp_plugin' via codex's /plugins UI" >&2
      return 3 ;;
    shell-installer)
      local tmp; tmp="$(mktemp)"; curl -fsSL "$(_arg "$e" '.args.url_unix')" -o "$tmp" && bash "$tmp"; rm -f "$tmp" ;;
    npx-skills)
      npx -y skills add "$(_arg "$e" '.args.repo')" ;;
    git-setup)
      local repo dest sa; repo="$(_arg "$e" '.args.repo')"; dest="$(_expand "$(_arg "$e" '.args.dest')")"; sa="$(_arg "$e" '.args.setup_args')"
      [ -d "$dest/.git" ] || git clone --depth 1 "$repo" "$dest"
      # gstack's setup bootstraps bun into ~/.bun/bin — make sure it's on PATH
      ( export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"; cd "$dest" && ./setup $sa ) ;;
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
DO_INSTALL_PREREQS=1     # default: auto-install missing prerequisites (jq/git/node/bun)
F_AGENT=""; F_PLUGIN=""; F_METHOD=""
AGENTS_ONLY=0; ASSUME_YES=0; NON_INTERACTIVE=0   # default: 3s countdown then auto-yes

usage() { grep -E '^\s+--' "$HERE/install.sh" | sed 's/) .*//' >&2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|--plan)   MODE="dry-run" ;;
    --status)           MODE="status" ;;
    --check-prereqs)    MODE="check-prereqs" ;;
    --install-prereqs)  DO_INSTALL_PREREQS=1 ;;
    --skip-prereqs)     DO_INSTALL_PREREQS=0 ;;
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

# 1b. auto-install missing prerequisites (install mode only — never during dry-run/status/check)
if [ "$DO_INSTALL_PREREQS" = "1" ] && [ "$MODE" = "install" ]; then
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
    confirm "  install agent $a?" || { echo "agent $a skipped"; continue; }
    tmp="$(mktemp)"
    if curl -fsSL "$url" -o "$tmp"; then
      # run unattended; </dev/null stops child installers blocking on their own prompts
      case "$a" in
        codex) CODEX_NON_INTERACTIVE=1 bash "$tmp" </dev/null ;;
        *)     bash "$tmp" </dev/null ;;
      esac
    fi
    rm -f "$tmp"
  done
fi
[ "$AGENTS_ONLY" = "1" ] && exit 0

# 9. execute plan entries
REPORT="$(mktemp)"   # tsv: status<TAB>label<TAB>reason
record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$REPORT"; }
last_line() { grep -v '^[[:space:]]*$' | tail -1 | sed 's/^[[:space:]]*//'; }

n="$(jq 'length' <<<"$PLAN")"; i=0
while [ "$i" -lt "$n" ]; do
  e="$(jq -c ".[$i]" <<<"$PLAN")"; i=$((i + 1))
  label="$(jq -r '.plugin' <<<"$e")/$(jq -r '.agent' <<<"$e")"
  if checks_has_after "$e" && checks_run_after "$e"; then
    echo "[$label] already satisfied — skip"; record ok "$label" "already installed"; continue
  fi
  if [ "$(jq -r '.method' <<<"$e")" = "manual" ]; then
    echo "[$label] MANUAL:"; report_manual_steps "$e"
    record manual "$label" "$(jq -r '.manual.reason // "see steps"' <<<"$e")"; continue
  fi
  hi="$(jq -r '(.safety.executes_remote_code // false) or (.safety.requires_admin // false)' <<<"$e")"
  if [ "$hi" = "true" ]; then
    echo "[$label] high-risk:"; method_plan "$e" | sed 's/^/    $ /'
    confirm "[$label] proceed?" || { echo "[$label] skipped"; record skip "$label" "declined"; continue; }
  fi
  echo "[$label] executing:"; method_plan "$e" | sed 's/^/    $ /'
  out="$(mktemp)"
  _exec_entry "$e" 2>&1 | tee "$out"; rc="${PIPESTATUS[0]}"
  reason="$(last_line < "$out")"; rm -f "$out"
  case "$rc" in
    0) record ok "$label" "installed" ;;
    3) echo "[$label] skipped"; record skip "$label" "${reason:-skipped}" ;;
    *) echo "[$label] FAILED" >&2; record fail "$label" "${reason:-error}" ;;
  esac
done

# 10. report — concise, grouped, saved to a file
RUNDIR="${AGENT_SETUP_HOME:-$HOME/.agent-setup}"; mkdir -p "$RUNDIR"
REPORT_FILE="$RUNDIR/last-install-report.txt"
C_GREEN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYAN=$'\033[36m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'
[ -n "${NO_COLOR:-}" ] && { C_GREEN=""; C_YEL=""; C_CYAN=""; C_RED=""; C_OFF=""; }
print_group() { # <key> <heading> <symbol> <color>
  local cnt; cnt="$(awk -F'\t' -v k="$1" '$1==k' "$REPORT" | wc -l | tr -d ' ')"
  [ "$cnt" = 0 ] && return 0
  printf '\n%s%s (%s):%s\n' "$4" "$2" "$cnt" "$C_OFF"
  awk -F'\t' -v k="$1" -v s="$3" -v c="$4" -v o="$C_OFF" '$1==k {printf "  %s%s %-22s%s %s\n", c, s, $2, o, $3}' "$REPORT"
}
STRIP="s/$(printf '\033')\\[[0-9;]*m//g"
{
  echo "================ agent-setup report ================"
  echo "OS: $OS"
  print_group ok     "OK"      "+" "$C_GREEN"
  print_group skip   "SKIPPED" "-" "$C_YEL"
  print_group manual "MANUAL"  "*" "$C_CYAN"
  print_group fail   "FAILED"  "x" "$C_RED"
  echo "===================================================="
} | tee >(sed "$STRIP" > "$REPORT_FILE")
echo "report saved: $REPORT_FILE"

fail_n="$(awk -F'\t' '$1=="fail"' "$REPORT" | wc -l | tr -d ' ')"
rm -f "$REPORT"
[ "$fail_n" = 0 ]
