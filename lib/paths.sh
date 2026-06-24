#!/usr/bin/env bash
# paths.sh — cursor-cli (cursor-agent) config path resolution. Pure (env in, stdout out).
set -u

cursor_user_dir() { # <os> — cursor-agent CLI config home; ~/.cursor on every OS
  case "$1" in
    darwin|linux|wsl|windows) printf '%s/.cursor' "$HOME" ;;
    *)                        return 1 ;;
  esac
}
cursor_rules_dir()  { printf '%s/rules' "$(cursor_user_dir "$1")"; }
cursor_mcp_config() { printf '%s/mcp.json' "$(cursor_user_dir "$1")"; }
cursor_skills_dir() { printf '%s/skills' "$(cursor_user_dir "$1")"; }
