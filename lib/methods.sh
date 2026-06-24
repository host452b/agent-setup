#!/usr/bin/env bash
# methods.sh — pure command planning per method type. Requires jq.
set -u

_arg() { jq -r "$2 // \"\"" <<<"$1"; }

method_plan() { # <entry_json>
  local e="$1" m
  m="$(jq -r '.method' <<<"$e")"
  case "$m" in
    claude-plugin)
      printf 'claude plugin marketplace add %s\n' "$(_arg "$e" '.args.marketplace_src')"
      printf 'claude plugin install %s@%s\n' "$(_arg "$e" '.args.plugin')" "$(_arg "$e" '.args.marketplace_name')"
      ;;
    codex-plugin)
      local cp_spec; cp_spec="$(_arg "$e" '.args.plugin')"
      [ -n "$(_arg "$e" '.args.marketplace_name')" ] && cp_spec="$cp_spec@$(_arg "$e" '.args.marketplace_name')"
      printf 'codex plugin marketplace add %s\n' "$(_arg "$e" '.args.marketplace_src')"
      printf 'codex plugin add %s\n' "$cp_spec"
      ;;
    shell-installer)
      printf 'download-then-run %s\n' "$(_arg "$e" '.args.url_unix')"
      ;;
    npx-skills)
      printf 'npx -y skills add %s %s\n' "$(_arg "$e" '.args.repo')" "$(_arg "$e" '.args.extra')"
      ;;
    git-symlink)
      printf 'git clone --depth 1 %s %s\n' "$(_arg "$e" '.args.repo')" "$(_arg "$e" '.args.clone_dest')"
      printf 'ln -sfn %s %s\n' "$(_arg "$e" '.args.clone_dest')" "$(_arg "$e" '.args.link')"
      ;;
    git-setup)
      printf 'git clone --depth 1 %s %s\n' "$(_arg "$e" '.args.repo')" "$(_arg "$e" '.args.dest')"
      printf 'cd %s && ./setup %s\n' "$(_arg "$e" '.args.dest')" "$(_arg "$e" '.args.setup_args')"
      ;;
    npm-cli)
      local ensure
      ensure="$(_arg "$e" '.args.ensure')"
      [ -n "$ensure" ] && printf 'ensure %s (else: %s)\n' "$ensure" "$(_arg "$e" '.args.ensure_install')"
      printf '%s\n' "$(_arg "$e" '.args.command')"
      ;;
    od-mcp)
      printf 'PATH-shadow-guard od (expect %s)\n' "$(_arg "$e" '.args.expected_substr')"
      printf 'od mcp install %s\n' "$(_arg "$e" '.args.agent')"
      ;;
    file-copy)
      printf 'copy %s -> %s\n' "$(_arg "$e" '.args.src')" "$(_arg "$e" '.args.dest')"
      ;;
    unsupported)
      printf 'N/A: %s\n' "$(_arg "$e" '.manual.reason')"
      ;;
    manual)
      printf 'MANUAL: %s\n' "$(_arg "$e" '.manual.reason')"
      ;;
    *)
      printf 'UNKNOWN METHOD %s\n' "$m"; return 1
      ;;
  esac
}
