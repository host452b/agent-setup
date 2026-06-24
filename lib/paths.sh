#!/usr/bin/env bash
# paths.sh — per-OS Cursor config path resolution. Pure (env in, stdout out).
set -u

cursor_user_dir() { # <os>
  case "$1" in
    darwin)     printf '%s/Library/Application Support/Cursor/User' "$HOME" ;;
    linux|wsl)  printf '%s/.config/Cursor/User' "$HOME" ;;
    windows)    printf '%s/Cursor/User' "${APPDATA:-$HOME/AppData/Roaming}" ;;
    *)          return 1 ;;
  esac
}
cursor_rules_dir()  { printf '%s/rules' "$(cursor_user_dir "$1")"; }
cursor_mcp_config() { printf '%s/mcp.json' "$(cursor_user_dir "$1")"; }
cursor_skills_dir() { printf '%s/skills' "$(cursor_user_dir "$1")"; }
