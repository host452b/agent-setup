#!/usr/bin/env bash
# checks.sh — fixed predicate vocabulary for idempotency + verification. Requires jq.
set -u

_expand() { # expand ${HOME} and $HOME in a path string
  local s="$1"; s="${s//\$\{HOME\}/$HOME}"; s="${s//\$HOME/$HOME}"; printf '%s' "$s"
}

check_eval() { # <check_json>
  local c="$1" type
  type="$(jq -r '.type' <<<"$c")"
  case "$type" in
    command_exists) command -v "$(jq -r '.name' <<<"$c")" >/dev/null 2>&1 ;;
    file_exists)    [ -f "$(_expand "$(jq -r '.path' <<<"$c")")" ] ;;
    dir_exists)     [ -d "$(_expand "$(jq -r '.path' <<<"$c")")" ] ;;
    json_path_exists)
      local f q; f="$(_expand "$(jq -r '.path' <<<"$c")")"; q="$(jq -r '.query' <<<"$c")"
      [ -f "$f" ] && jq -e "$q != null" "$f" >/dev/null 2>&1 ;;
    json_contains)
      local f q v; f="$(_expand "$(jq -r '.path' <<<"$c")")"; q="$(jq -r '.query' <<<"$c")"; v="$(jq -r '.value' <<<"$c")"
      [ -f "$f" ] && [ "$(jq -r "$q" "$f" 2>/dev/null)" = "$v" ] ;;
    cursor_rule_exists)
      [ -f "$(_expand "$(jq -r '.rules_dir' <<<"$c")")/$(jq -r '.name' <<<"$c")" ] ;;
    claude_plugin_installed)
      command -v claude >/dev/null 2>&1 && claude plugin list 2>/dev/null | grep -q "$(jq -r '.name' <<<"$c")" ;;
    codex_plugin_installed)
      command -v codex >/dev/null 2>&1 && codex plugin list 2>/dev/null | grep -q "$(jq -r '.name' <<<"$c")" ;;
    mcp_server_registered)
      local f n; f="$(_expand "$(jq -r '.path' <<<"$c")")"; n="$(jq -r '.name' <<<"$c")"
      [ -f "$f" ] && jq -e --arg n "$n" '(.. | objects | keys?[]?) | select(. == $n)' "$f" >/dev/null 2>&1 ;;
    *) echo "check_eval: unknown type: $type" >&2; return 2 ;;
  esac
}

checks_has_after() { # <plan_entry_json> — 0 if at least one after-check is defined
  local n; n="$(jq '.checks.after | length // 0' <<<"$1" 2>/dev/null)"; n="${n:-0}"
  [ "$n" != "0" ]
}

checks_run_after() { # <plan_entry_json>
  local n i c
  n="$(jq '.checks.after | length // 0' <<<"$1" 2>/dev/null)"; n="${n:-0}"
  [ "$n" = "0" ] && return 0
  i=0
  while [ "$i" -lt "$n" ]; do
    c="$(jq -c ".checks.after[$i]" <<<"$1")"
    check_eval "$c" || return 1
    i=$((i + 1))
  done
  return 0
}
