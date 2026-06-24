#!/usr/bin/env bash
# manifest.sh — load, validate, and resolve manifest.json. Requires jq.
set -u

manifest_validate() { # <file>
  local f="$1"
  [ -f "$f" ] || { echo "manifest_validate: no such file: $f" >&2; return 1; }
  jq -e '
    (.version | type == "string") and
    (.agents  | type == "object") and
    (.plugins | type == "object") and
    ([ .plugins[] | .targets | type == "object" ] | all) and
    ([ .plugins[].targets[]
        | (.method | type == "string")
          and (.coverage | test("^(native|partial|manual|unsupported)$"))
          and (.platforms | type == "array")
     ] | all)
  ' "$f" >/dev/null
}

manifest_resolve_plan() { # <file> <os> <agents_json>
  local f="$1" os="$2" agents="$3"
  jq --arg os "$os" --argjson agents "$agents" '
    [ .plugins | to_entries[] as $p
      | ($p.value.targets | to_entries[]) as $t
      | select($t.value.platforms | index($os))
      | select(($agents.agents[$t.key].present // false) == true)
      | {
          plugin:          $p.key,
          agent:           $t.key,
          method:          $t.value.method,
          coverage:        $t.value.coverage,
          requires:        ($t.value.requires // []),
          install_scope:   ($t.value.install_scope // "user"),
          args:            ($t.value.args // {}),
          manual:          ($t.value.manual // null),
          safety:          ($t.value.safety // {}),
          checks:          ($t.value.checks // {}),
          conflict_policy: ($t.value.conflict_policy // "skip")
        }
    ]
  ' "$f"
}
