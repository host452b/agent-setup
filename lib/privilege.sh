#!/usr/bin/env bash
# privilege.sh — surface privilege needs before execution. Requires jq.
set -u

priv_is_admin() { [ "$(id -u 2>/dev/null)" = "0" ]; }

priv_target_needs_admin() { # <target_json>
  jq -r '.safety.requires_admin // false' <<<"$1"
}

priv_summarize() { # <plan_json>
  jq -r '
    .[]
    | select((.safety.requires_admin // false) or (.safety.may_prompt_for_sudo // false))
    | "\(.plugin)/\(.agent): "
      + ((if (.safety.requires_admin // false) then "requires_admin " else "" end)
       + (if (.safety.may_prompt_for_sudo // false) then "may_sudo" else "" end) | ltrimstr(" ") | rtrimstr(" "))
  ' <<<"$1"
}
