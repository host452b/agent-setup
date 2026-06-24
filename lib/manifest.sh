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
