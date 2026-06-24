#!/usr/bin/env bash
# report.sh — render the resolved plan for dry-run / plan / report. Requires jq + lib/methods.sh.
set -u

report_manual_steps() { # <entry_json>
  local steps n i
  n="$(jq '.manual.steps | length // 0' <<<"$1" 2>/dev/null)"; n="${n:-0}"
  [ "$n" = "0" ] && return 0
  i=0
  while [ "$i" -lt "$n" ]; do
    printf '    %d. %s\n' "$((i + 1))" "$(jq -r ".manual.steps[$i]" <<<"$1")"
    i=$((i + 1))
  done
}

report_plan() { # <plan_json>
  local n i e
  n="$(jq 'length' <<<"$1")"
  i=0
  while [ "$i" -lt "$n" ]; do
    e="$(jq -c ".[$i]" <<<"$1")"
    printf '%s/%s [%s]\n' \
      "$(jq -r '.plugin' <<<"$e")" "$(jq -r '.agent' <<<"$e")" "$(jq -r '.coverage' <<<"$e")"
    method_plan "$e" | sed 's/^/    $ /'
    printf '    conflict: %s   requires: %s\n' \
      "$(jq -r '.conflict_policy' <<<"$e")" "$(jq -r '(.requires // []) | join(",")' <<<"$e")"
    if [ "$(jq -r '.safety.requires_admin // false' <<<"$e")" = "true" ]; then printf '    NEEDS ADMIN\n'; fi
    report_manual_steps "$e"
    printf '\n'
    i=$((i + 1))
  done
}
