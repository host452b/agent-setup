#!/usr/bin/env bash
# prereqs.sh — prerequisite checks + PATH-shadow-aware resolution.
set -u

tool_present()  { command -v "$1" >/dev/null 2>&1; }
tool_realpath() {
  local p; p="$(command -v "$1" 2>/dev/null)" || return 0
  if command -v realpath >/dev/null 2>&1; then realpath "$p" 2>/dev/null || echo "$p"; else echo "$p"; fi
}

require_jq() {
  if tool_present jq; then return 0; fi
  echo "jq is required to parse manifest.json safely." >&2
  echo "Install it with: brew install jq   (macOS) / sudo apt install jq   (Debian/Ubuntu)" >&2
  return 2
}

prereqs_report() { # <name...>
  local t
  for t in "$@"; do
    if tool_present "$t"; then printf '%s: present (%s)\n' "$t" "$(tool_realpath "$t")"
    else printf '%s: MISSING\n' "$t"; fi
  done
}

prereqs_install() { # <name...> — install any missing tools via the platform hint; returns 0 if all present/installed
  local t rc=0
  for t in "$@"; do
    if tool_present "$t"; then continue; fi
    local hint; hint="$(prereq_install_hint "$t")"
    echo "installing prerequisite: $t  ->  $hint" >&2
    sh -c "$hint" || { echo "failed to install $t" >&2; rc=1; }
  done
  return $rc
}

prereq_install_hint() { # <name>
  if   tool_present brew;   then echo "brew install $1"
  elif tool_present apt;    then echo "sudo apt install -y $1"
  elif tool_present winget; then echo "winget install $1"
  else echo "(install $1 with your platform package manager)"; fi
}
