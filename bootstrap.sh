#!/usr/bin/env bash
# bootstrap.sh — one-line installer for agent-setup.
#   curl -fsSL https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.sh | bash
#   ... | bash -s -- --dry-run      # pass installer flags after --
set -u

AGENT_SETUP_REPO_SLUG="${AGENT_SETUP_REPO_SLUG:-host452b/agent-setup}"
AGENT_SETUP_BRANCH="${AGENT_SETUP_BRANCH:-main}"

bootstrap_cache_dir() { printf '%s' "${AGENT_SETUP_HOME:-$HOME/.agent-setup}"; }

_fetch_method_from() { case "$1" in yes) echo git ;; *) echo tarball ;; esac; }
bootstrap_fetch_method() {
  if command -v git >/dev/null 2>&1; then _fetch_method_from yes; else _fetch_method_from no; fi
}

bootstrap_fetch() { # <cache> <method>
  local cache="$1" method="$2"
  local url="https://github.com/${AGENT_SETUP_REPO_SLUG}.git"
  local tarball="https://github.com/${AGENT_SETUP_REPO_SLUG}/archive/refs/heads/${AGENT_SETUP_BRANCH}.tar.gz"
  case "$method" in
    git)
      if [ -d "$cache/.git" ]; then
        git -C "$cache" pull --ff-only --quiet || {
          echo "agent-setup: update failed, re-cloning fresh" >&2
          rm -rf "$cache"
          git clone --depth 1 --branch "$AGENT_SETUP_BRANCH" "$url" "$cache" --quiet
        }
      else
        rm -rf "$cache"
        git clone --depth 1 --branch "$AGENT_SETUP_BRANCH" "$url" "$cache" --quiet
      fi
      ;;
    tarball)
      local tmp; tmp="$(mktemp)"
      trap 'rm -f "$tmp"' RETURN
      curl -fsSL "$tarball" -o "$tmp" || { echo "agent-setup: download failed" >&2; return 1; }
      rm -rf "$cache"; mkdir -p "$cache"
      tar xzf "$tmp" -C "$cache" --strip-components=1
      ;;
    *) echo "agent-setup: unknown fetch method: $method" >&2; return 1 ;;
  esac
}

bootstrap_main() {
  local cache method
  cache="$(bootstrap_cache_dir)"
  method="$(bootstrap_fetch_method)"
  echo "agent-setup: fetching ${AGENT_SETUP_REPO_SLUG}@${AGENT_SETUP_BRANCH} via ${method} -> ${cache}" >&2
  bootstrap_fetch "$cache" "$method" || return 1
  [ -f "$cache/install.sh" ] || {
    echo "agent-setup: install.sh not found in fetched repo (is the unix driver merged to ${AGENT_SETUP_BRANCH}?)" >&2
    return 1
  }
  exec bash "$cache/install.sh" "$@"
}

# Run unless sourced for testing.
[ -n "${AGENT_SETUP_BOOTSTRAP_NOEXEC:-}" ] || bootstrap_main "$@"
