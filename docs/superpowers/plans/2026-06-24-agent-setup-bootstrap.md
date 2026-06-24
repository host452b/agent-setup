# agent-setup — Bootstrap One-Liner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a one-line installer (`bootstrap.sh`) so users run `curl -fsSL …/bootstrap.sh | bash` instead of cloning manually; it fetches the repo to a cache dir and delegates to `install.sh`, passing flags through.

**Architecture:** `bootstrap.sh` holds no install logic — it resolves a cache dir, fetches the repo (git clone --depth 1, falling back to a curl tarball when git is absent), then `exec`s `install.sh "$@"`. Pure helpers (`bootstrap_cache_dir`, `_fetch_method_from`, `bootstrap_fetch_method`) are unit-tested without network; `bootstrap_main` runs unless sourced under a test sentinel.

**Tech Stack:** Bash, curl, git/tar, the existing plain-bash test harness in `tests/`.

This branch (`bootstrap-oneliner`) is stacked on the unix-driver branch, so `install.sh`, `lib/`, `manifest.json`, `README.md`, `docs/`, and `tests/` are all present.

## Global Constraints

- File starts with `#!/usr/bin/env bash` and `set -u`.
- No pipe-to-shell of remote code; the tarball is downloaded to a temp file then extracted (data extraction, not code exec).
- Flags pass through verbatim to `install.sh` (`… | bash -s -- --dry-run`).
- Native-Windows `bootstrap.ps1` is OUT OF SCOPE (waits for the Windows driver / `install.ps1`). Windows is covered now via Git-Bash running `bootstrap.sh`.
- Commits end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` (repo-local identity host452b, already set).
- Run tests with `bash tests/run.sh`.

---

### Task 1: bootstrap.sh + tests + docs

**Files:**
- Create: `bootstrap.sh`
- Create: `tests/test_bootstrap.sh`
- Modify: `README.md` (add a `## One-line install` section near the top)
- Modify: `docs/security.md` (add the bootstrap pipe-to-shell tradeoff note)

**Interfaces:**
- Produces: `bootstrap_cache_dir` → echoes `${AGENT_SETUP_HOME:-$HOME/.agent-setup}`; `_fetch_method_from <yes|no>` → `git`|`tarball`; `bootstrap_fetch_method` → `git` if `git` on PATH else `tarball`; `bootstrap_fetch <cache> <method>` → clones/pulls or downloads+extracts (returns 1 on unknown method); `bootstrap_main "$@"` → fetch then `exec bash "$cache/install.sh" "$@"`.

- [ ] **Step 1: Write the failing test**

`tests/test_bootstrap.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
export AGENT_SETUP_BOOTSTRAP_NOEXEC=1
. "$root/bootstrap.sh"
assert_eq "/h/.agent-setup" "$(HOME=/h bootstrap_cache_dir)" "default cache dir"
assert_eq "/custom"         "$(AGENT_SETUP_HOME=/custom bootstrap_cache_dir)" "override cache dir"
assert_eq "git"     "$(_fetch_method_from yes)" "git when present"
assert_eq "tarball" "$(_fetch_method_from no)"  "tarball when absent"
assert_eq "git"     "$(bootstrap_fetch_method)" "machine has git"
assert_fail bootstrap_fetch /tmp/agent-setup-x nonsense-method
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `bootstrap.sh` missing.

- [ ] **Step 3: Write bootstrap.sh**

```bash
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
      curl -fsSL "$tarball" -o "$tmp" || { echo "agent-setup: download failed" >&2; rm -f "$tmp"; return 1; }
      rm -rf "$cache"; mkdir -p "$cache"
      tar xzf "$tmp" -C "$cache" --strip-components=1
      rm -f "$tmp"
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — all bootstrap assertions succeed and the prior suites stay green.

- [ ] **Step 5: Docs**

Add a `## One-line install` section near the top of `README.md`:
````markdown
## One-line install

```bash
# macOS / Linux / WSL / Git-Bash (Windows)
curl -fsSL https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.sh | bash

# preview without installing
curl -fsSL https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.sh | bash -s -- --dry-run
```

Prefer to inspect before running (recommended):

```bash
curl -fsSL https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.sh -o bootstrap.sh
less bootstrap.sh
bash bootstrap.sh
```

The bootstrap caches the repo at `~/.agent-setup` (override with `AGENT_SETUP_HOME`) and re-runs are fast. Native Windows PowerShell support arrives with the Windows driver; until then use Git-Bash.
````

Append to `docs/security.md`:
```markdown
## Bootstrap one-liner tradeoff

`curl … | bash` is pipe-to-shell — the very pattern this project avoids for the
installers it runs. We offer it for convenience but recommend the inspect-first
variant (download `bootstrap.sh`, read it, then run it), or a plain
`git clone` + `bash install.sh`. The bootstrap itself only fetches the repo
(git clone, or a tarball downloaded to a temp file then extracted — never piped
to a shell) and then runs the local `install.sh`.
```

- [ ] **Step 6: Commit**

```bash
chmod +x bootstrap.sh
git add bootstrap.sh tests/test_bootstrap.sh README.md docs/security.md
git commit -m "feat: add bootstrap.sh one-line installer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** one-liner (bootstrap.sh), flag passthrough (`exec … "$@"`), git+tarball fallback (`bootstrap_fetch`), cache dir + override, inspect-first + security note (docs), Windows-via-Git-Bash + ps1-deferred note. ✓
- **Placeholder scan:** none.
- **Type consistency:** `bootstrap_cache_dir`, `_fetch_method_from`, `bootstrap_fetch_method`, `bootstrap_fetch`, `bootstrap_main` used consistently; test sentinel `AGENT_SETUP_BOOTSTRAP_NOEXEC` matches the guard.
- **Merge-order note:** bootstrap is functionally live only after the unix driver (install.sh) reaches `main`; the `install.sh not found` guard fails loudly until then.
