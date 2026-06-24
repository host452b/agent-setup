#!/usr/bin/env bash
# detect.sh — OS taxonomy + present-agent structured detection. Requires lib/paths.sh + jq.
set -u

detect_os_from() { # <uname_s> <proc_version>
  case "$1" in
    Darwin) echo darwin ;;
    Linux)  case "$2" in *icrosoft*|*WSL*) echo wsl ;; *) echo linux ;; esac ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo linux ;;
  esac
}
detect_os() { detect_os_from "$(uname -s 2>/dev/null)" "$(cat /proc/version 2>/dev/null)"; }

_present() { command -v "$1" >/dev/null 2>&1 && echo true || echo false; }

detect_agents_json() { # <os>
  local os="$1" cu
  cu="$(cursor_user_dir "$os")"
  jq -n \
    --arg os "$os" \
    --argjson claude "$(_present claude)" \
    --argjson codex  "$(_present codex)" \
    --argjson cursor "$(_present cursor-agent)" \
    --arg cu "$cu" \
    '{ os: $os, agents: {
        claude: { present: $claude },
        codex:  { present: $codex },
        cursor: { present: $cursor, user_dir: $cu, rules_dir: ($cu+"/rules"),
                  mcp_config: ($cu+"/mcp.json"), skills_dir: ($cu+"/skills") }
    } }'
}
