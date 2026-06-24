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
  echo "Install it with: $(prereq_install_hint jq)" >&2
  echo "Or re-run with --install-prereqs (one-liner: ... | bash -s -- --install-prereqs)." >&2
  return 2
}

prereqs_report() { # <name...>
  local t
  for t in "$@"; do
    if tool_present "$t"; then printf '%s: present (%s)\n' "$t" "$(tool_realpath "$t")"
    else printf '%s: MISSING\n' "$t"; fi
  done
}

prereqs_install() { # <name...> — install any missing tools; returns 0 if all present/installed
  local t rc=0
  for t in "$@"; do
    if tool_present "$t"; then continue; fi
    case "$t" in
      bun)
        echo "installing bun (user-level, no sudo)..." >&2
        local tb; tb="$(mktemp)"
        if curl -fsSL https://bun.sh/install -o "$tb"; then bash "$tb" </dev/null || rc=1; else rc=1; fi
        rm -f "$tb"
        export PATH="$HOME/.bun/bin:$PATH"   # available to the rest of this run
        ;;
      *)
        local hint; hint="$(prereq_install_hint "$t")"
        echo "installing $t  ->  $hint" >&2
        sh -c "$hint" </dev/null || { echo "could not auto-install $t (run: $hint)" >&2; rc=1; }
        ;;
    esac
  done
  return $rc
}

# pure: build the install command for a package manager, dropping sudo when root
_install_hint_for() { # <mgr> <root: yes|no> <pkg>
  case "$1" in
    brew)   echo "brew install $3" ;;
    apt)    if [ "$2" = "yes" ]; then echo "apt-get install -y $3"; else echo "sudo apt-get install -y $3"; fi ;;
    winget) echo "winget install $3" ;;
    *)      echo "(install $3 with your platform package manager)" ;;
  esac
}

prereq_install_hint() { # <name>
  local root="no"; [ "$(id -u 2>/dev/null)" = "0" ] && root="yes"
  if   tool_present brew;                          then _install_hint_for brew   "$root" "$1"
  elif tool_present apt || tool_present apt-get;   then _install_hint_for apt    "$root" "$1"
  elif tool_present winget;                        then _install_hint_for winget "$root" "$1"
  else _install_hint_for none "$root" "$1"; fi
}
