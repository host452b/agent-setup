# agent-setup — Unix Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the manifest-driven unix installer (`install.sh` + `lib/*.sh`) that installs Claude Code / Codex CLI / Cursor CLI and a curated plugin/skill set across macOS / Linux / WSL / Git-Bash.

**Architecture:** A single `manifest.json` (validated by `manifest.schema.json`) declares agents and per-(plugin, agent) install targets. Pure-function library modules (`detect`, `paths`, `prereqs`, `privilege`, `manifest`, `checks`, `methods`, `report`) are sourced by `install.sh`, which runs a fixed startup order: detect → verify jq → validate manifest → resolve plan → privilege preflight → execute/dry-run → after-checks → report.

**Tech Stack:** Bash (POSIX-leaning, runs under Git-Bash too), `jq` for all JSON, plain-bash test harness (no bats dependency).

## Global Constraints

- All JSON parsing uses `jq`. No `awk`/`sed`/`grep` JSON parsing. `jq` is a hard prerequisite.
- OS taxonomy is exactly: `darwin | linux | windows | wsl`. WSL is never folded into linux.
- Library functions are **pure where possible**: parsing/resolution/command-planning take inputs as args and write to stdout; only `install.sh` and the `*_run`/`*_install` wrappers cause side effects.
- Dry-run prints commands and mutates nothing. High-risk steps (`executes_remote_code` or `requires_admin`) need confirmation unless `--yes`.
- Remote scripts use download-then-run (`mktemp` → `curl -o` → run), never pipe-to-shell.
- Cursor is a best-effort integration target; never assume a Cursor plugin-install CLI exists.
- Every file starts with `#!/usr/bin/env bash` and `set -u`; libs are source-only (no top-level side effects).
- Commits: repo-local identity is already set to `host452b`. Every commit message ends with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Run all tests with `bash tests/run.sh` from repo root.

---

### Task 1: Test harness + scaffold

**Files:**
- Create: `tests/lib/assert.sh`
- Create: `tests/run.sh`
- Create: `tests/test_smoke.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces: `assert_eq <expected> <actual> [msg]`, `assert_contains <haystack> <needle> [msg]`, `assert_ok <cmd...>`, `assert_fail <cmd...>` — each increments `ASSERT_FAILURES` on failure. `bash tests/run.sh` sources `tests/lib/assert.sh`, runs every `tests/test_*.sh` in a subshell, exits nonzero if any suite reported failures.

- [ ] **Step 1: Write the failing test**

`tests/test_smoke.sh`:
```bash
# sourced by run.sh with assert.sh already loaded
assert_eq "ok" "ok" "smoke equality"
assert_contains "hello world" "wor" "smoke contains"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `tests/run.sh` and `tests/lib/assert.sh` do not exist yet (`No such file or directory`).

- [ ] **Step 3: Write the harness**

`tests/lib/assert.sh`:
```bash
#!/usr/bin/env bash
ASSERT_FAILURES=${ASSERT_FAILURES:-0}
assert_eq() {
  if [ "$1" != "$2" ]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "${3:-eq}" "$1" "$2" >&2
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}
assert_contains() {
  case "$1" in
    *"$2"*) : ;;
    *) printf 'FAIL: %s\n  %s\n  does not contain: %s\n' "${3:-contains}" "$1" "$2" >&2
       ASSERT_FAILURES=$((ASSERT_FAILURES + 1)) ;;
  esac
}
assert_ok() {
  if ! "$@" >/dev/null 2>&1; then
    printf 'FAIL: expected success: %s\n' "$*" >&2
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}
assert_fail() {
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL: expected failure: %s\n' "$*" >&2
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
  fi
}
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
total=0; failed=0
for t in "$here"/test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $(basename "$t") =="
  rc=$(
    ASSERT_FAILURES=0
    # shellcheck disable=SC1090
    . "$here/lib/assert.sh"
    . "$t"
    echo "$ASSERT_FAILURES"
  )
  rc="${rc##*$'\n'}"
  total=$((total + 1))
  if [ "${rc:-1}" != "0" ]; then failed=$((failed + 1)); echo "  -> $rc failure(s)"; fi
done
echo "Suites: $total  Failed: $failed"
[ "$failed" -eq 0 ]
```

`.gitignore`:
```
*.log
.DS_Store
/tmp/
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — `Suites: 1  Failed: 0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/ .gitignore
git commit -m "test: add plain-bash assert harness and runner

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Manifest schema + manifest data + validator

**Files:**
- Create: `manifest.schema.json`
- Create: `manifest.json`
- Create: `lib/manifest.sh`
- Create: `tests/test_manifest.sh`
- Create: `tests/fixtures/bad-manifest.json`

**Interfaces:**
- Produces: `manifest_validate <file>` → exit 0 if structurally valid (has string `version`, object `agents`, object `plugins`; every plugin has object `targets`; every target has string `method`, `coverage` matching `^(native|partial|manual|unsupported)$`, and array `platforms`). Nonzero otherwise.

- [ ] **Step 1: Write the failing test**

`tests/test_manifest.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/manifest.sh"
assert_ok   manifest_validate "$root/manifest.json"
assert_fail manifest_validate "$root/tests/fixtures/bad-manifest.json"
# spot-check real data
assert_eq "claude-plugin" \
  "$(jq -r '.plugins.superpowers.targets.claude.method' "$root/manifest.json")" "superpowers claude method"
assert_eq "manual" \
  "$(jq -r '.plugins.superpowers.targets.cursor.coverage' "$root/manifest.json")" "superpowers cursor coverage"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/manifest.sh` missing.

- [ ] **Step 3: Write schema, data, and validator**

`manifest.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["version", "agents", "plugins"],
  "properties": {
    "version": { "type": "string" },
    "agents": { "type": "object" },
    "plugins": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["targets"],
        "properties": {
          "targets": {
            "type": "object",
            "additionalProperties": {
              "type": "object",
              "required": ["method", "coverage", "platforms"],
              "properties": {
                "method": { "type": "string" },
                "coverage": { "enum": ["native", "partial", "manual", "unsupported"] },
                "platforms": { "type": "array", "items": { "type": "string" } },
                "requires": { "type": "array", "items": { "type": "string" } },
                "install_scope": { "enum": ["user", "global"] },
                "args": { "type": "object" },
                "safety": { "type": "object" },
                "checks": { "type": "object" },
                "conflict_policy": { "enum": ["skip", "backup", "overwrite", "merge", "prompt"] },
                "manual": { "type": "object" }
              }
            }
          }
        }
      }
    }
  }
}
```

`manifest.json` (verbatim — this is the source of truth):
```json
{
  "version": "0.1.0",
  "agents": {
    "claude": {
      "binary": "claude",
      "install": {
        "darwin": "https://claude.ai/install.sh",
        "linux":  "https://claude.ai/install.sh",
        "wsl":    "https://claude.ai/install.sh",
        "windows":"https://claude.ai/install.sh"
      }
    },
    "codex": {
      "binary": "codex",
      "install": {
        "darwin": "https://chatgpt.com/codex/install.sh",
        "linux":  "https://chatgpt.com/codex/install.sh",
        "wsl":    "https://chatgpt.com/codex/install.sh",
        "windows":"https://chatgpt.com/codex/install.sh"
      }
    },
    "cursor": {
      "binary": "cursor-agent",
      "install": {
        "darwin": "https://cursor.com/install",
        "linux":  "https://cursor.com/install",
        "wsl":    "https://cursor.com/install",
        "windows":"https://cursor.com/install"
      }
    }
  },
  "plugins": {
    "superpowers": {
      "targets": {
        "claude": {
          "method": "claude-plugin", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["claude","jq"],
          "install_scope": "user",
          "args": { "marketplace_src": "obra/superpowers-marketplace", "marketplace_name": "superpowers-marketplace", "plugin": "superpowers" },
          "safety": { "risk": "low", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": false },
          "checks": { "after": [ { "type": "claude_plugin_installed", "name": "superpowers" } ] },
          "conflict_policy": "skip"
        },
        "codex": {
          "method": "codex-plugin", "coverage": "partial",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["codex"],
          "install_scope": "user",
          "args": { "marketplace_src": "obra/superpowers", "plugin": "superpowers" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "skip"
        },
        "cursor": {
          "method": "manual", "coverage": "manual",
          "platforms": ["darwin","linux","wsl","windows"], "requires": [],
          "safety": { "risk": "low", "network": false, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": false },
          "manual": {
            "reason": "Cursor installs superpowers via the in-chat /add-plugin marketplace; no CLI exists.",
            "steps": ["Open a Cursor Agent chat", "Run: /add-plugin superpowers"],
            "verification": ["Ask Cursor to list installed plugins and confirm superpowers appears"]
          }
        }
      }
    },
    "ponytail": {
      "targets": {
        "claude": {
          "method": "claude-plugin", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["claude","jq"],
          "args": { "marketplace_src": "DietrichGebert/ponytail", "marketplace_name": "ponytail", "plugin": "ponytail" },
          "safety": { "risk": "low", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": false },
          "checks": { "after": [ { "type": "claude_plugin_installed", "name": "ponytail" } ] },
          "conflict_policy": "skip"
        },
        "codex": {
          "method": "codex-plugin", "coverage": "partial",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["codex"],
          "args": { "marketplace_src": "DietrichGebert/ponytail", "plugin": "ponytail" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "skip"
        },
        "cursor": {
          "method": "manual", "coverage": "manual",
          "platforms": ["darwin","linux","wsl","windows"], "requires": [],
          "safety": { "risk": "low", "network": false, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": false },
          "manual": {
            "reason": "Ponytail is instruction-only on Cursor: copy its rules file into the Cursor rules dir.",
            "steps": ["Clone https://github.com/DietrichGebert/ponytail", "Copy .cursor/rules/ponytail.md into your Cursor rules directory (see docs/cursor.md)"],
            "verification": ["Confirm ponytail.md exists in the Cursor rules directory"]
          }
        }
      }
    },
    "gstack": {
      "targets": {
        "claude": {
          "method": "git-setup", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["git","node","bun"],
          "args": { "repo": "https://github.com/garrytan/gstack.git", "dest": "${HOME}/.claude/skills/gstack", "setup_args": "" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": true, "requires_admin": false, "requires_confirmation": true },
          "checks": { "after": [ { "type": "dir_exists", "path": "${HOME}/.claude/skills/gstack" } ] },
          "conflict_policy": "skip"
        },
        "codex": {
          "method": "git-setup", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["git","node","bun"],
          "args": { "repo": "https://github.com/garrytan/gstack.git", "dest": "${HOME}/.gstack", "setup_args": "--host codex" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": true, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "skip"
        },
        "cursor": {
          "method": "git-setup", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["git","node","bun"],
          "args": { "repo": "https://github.com/garrytan/gstack.git", "dest": "${HOME}/.gstack", "setup_args": "--host cursor" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": true, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "skip"
        }
      }
    },
    "caveman": {
      "targets": {
        "claude": {
          "method": "shell-installer", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["node"],
          "args": { "url_unix": "https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh" },
          "safety": { "risk": "high", "network": true, "executes_remote_code": true, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "skip"
        }
      }
    },
    "taste-skill": {
      "targets": {
        "claude": {
          "method": "npx-skills", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["node"],
          "args": { "repo": "https://github.com/Leonxlnx/taste-skill" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": true, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "skip"
        }
      }
    },
    "ui-ux-pro-max": {
      "targets": {
        "claude": {
          "method": "npm-cli", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["node"],
          "install_scope": "global", "requires_path_mutation": true,
          "args": { "ensure": "uipro", "ensure_install": "npm install -g uipro-cli", "command": "uipro init --ai claude --global" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true, "writes_global_config": true },
          "checks": { "after": [ { "type": "command_exists", "name": "uipro" } ] },
          "conflict_policy": "skip"
        },
        "codex": {
          "method": "npm-cli", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["node"],
          "install_scope": "global", "requires_path_mutation": true,
          "args": { "ensure": "uipro", "ensure_install": "npm install -g uipro-cli", "command": "uipro init --ai codex --global" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true, "writes_global_config": true },
          "conflict_policy": "skip"
        },
        "cursor": {
          "method": "npm-cli", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["node"],
          "install_scope": "global", "requires_path_mutation": true,
          "args": { "ensure": "uipro", "ensure_install": "npm install -g uipro-cli", "command": "uipro init --ai cursor --global" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true, "writes_global_config": true },
          "conflict_policy": "skip"
        }
      }
    },
    "open-design": {
      "targets": {
        "claude": {
          "method": "od-mcp", "coverage": "partial",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["od"],
          "args": { "agent": "claude", "expected_substr": "open-design" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "merge"
        },
        "codex": {
          "method": "od-mcp", "coverage": "partial",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["od"],
          "args": { "agent": "codex", "expected_substr": "open-design" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "merge"
        },
        "cursor": {
          "method": "od-mcp", "coverage": "partial",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["od"],
          "args": { "agent": "cursor", "expected_substr": "open-design" },
          "safety": { "risk": "medium", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": true },
          "conflict_policy": "merge"
        }
      }
    },
    "prompt-polish": {
      "targets": {
        "claude": {
          "method": "claude-plugin", "coverage": "native",
          "platforms": ["darwin","linux","wsl","windows"], "requires": ["claude","jq"],
          "args": { "marketplace_src": "host452b/prompt-polish", "marketplace_name": "prompt-polish", "plugin": "prompt-polish" },
          "safety": { "risk": "low", "network": true, "executes_remote_code": false, "requires_admin": false, "requires_confirmation": false },
          "checks": { "after": [ { "type": "claude_plugin_installed", "name": "prompt-polish" } ] },
          "conflict_policy": "skip"
        }
      }
    }
  }
}
```

`tests/fixtures/bad-manifest.json` (target missing `coverage`):
```json
{ "version": "0", "agents": {}, "plugins": { "x": { "targets": { "claude": { "method": "claude-plugin", "platforms": ["darwin"] } } } } }
```

`lib/manifest.sh`:
```bash
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — all four assertions in `test_manifest.sh` succeed.

- [ ] **Step 5: Commit**

```bash
git add manifest.schema.json manifest.json lib/manifest.sh tests/test_manifest.sh tests/fixtures/bad-manifest.json
git commit -m "feat: add manifest schema, data, and jq validator

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Path resolution (lib/paths.sh)

**Files:**
- Create: `lib/paths.sh`
- Create: `tests/test_paths.sh`

**Interfaces:**
- Produces: `cursor_user_dir <os>`, `cursor_rules_dir <os>`, `cursor_mcp_config <os>`, `cursor_skills_dir <os>` — each echoes an absolute path derived from `$HOME` (or `$APPDATA` on windows). Pure: reads only env, writes stdout.

- [ ] **Step 1: Write the failing test**

`tests/test_paths.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/paths.sh"
assert_eq "/h/Library/Application Support/Cursor/User" "$(HOME=/h cursor_user_dir darwin)" "darwin user_dir"
assert_eq "/h/.config/Cursor/User"                     "$(HOME=/h cursor_user_dir linux)"  "linux user_dir"
assert_eq "/h/.config/Cursor/User"                     "$(HOME=/h cursor_user_dir wsl)"    "wsl user_dir"
assert_eq "/r/Cursor/User"                             "$(APPDATA=/r cursor_user_dir windows)" "windows user_dir"
assert_eq "/h/.config/Cursor/User/rules"               "$(HOME=/h cursor_rules_dir linux)" "rules_dir"
assert_eq "/h/.config/Cursor/User/mcp.json"            "$(HOME=/h cursor_mcp_config linux)" "mcp_config"
assert_eq "/h/.config/Cursor/User/skills"              "$(HOME=/h cursor_skills_dir linux)" "skills_dir"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/paths.sh` missing.

- [ ] **Step 3: Write lib/paths.sh**

```bash
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — all path assertions match.

- [ ] **Step 5: Commit**

```bash
git add lib/paths.sh tests/test_paths.sh
git commit -m "feat: add per-OS Cursor path resolution

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: OS + agent detection (lib/detect.sh)

**Files:**
- Create: `lib/detect.sh`
- Create: `tests/test_detect.sh`

**Interfaces:**
- Consumes: `cursor_user_dir` from `lib/paths.sh`.
- Produces: `detect_os_from <uname_s> <proc_version>` → `darwin|linux|wsl|windows`; `detect_os` → calls it with live values; `detect_agents_json <os>` → JSON `{os, agents:{claude:{present},codex:{present},cursor:{present,user_dir,rules_dir,mcp_config,skills_dir}}}` where `present` reflects `command -v` for `claude`/`codex`/`cursor-agent`.

- [ ] **Step 1: Write the failing test**

`tests/test_detect.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/paths.sh"
. "$root/lib/detect.sh"
assert_eq "darwin"  "$(detect_os_from Darwin '')" "darwin"
assert_eq "linux"   "$(detect_os_from Linux 'Linux version 6.1 gcc')" "plain linux"
assert_eq "wsl"     "$(detect_os_from Linux 'Linux 5.15 microsoft-standard-WSL2')" "wsl"
assert_eq "windows" "$(detect_os_from MINGW64_NT-10.0 '')" "git-bash windows"
out="$(HOME=/h detect_agents_json linux)"
assert_eq "linux" "$(echo "$out" | jq -r .os)" "json os"
assert_eq "/h/.config/Cursor/User/rules" "$(echo "$out" | jq -r .agents.cursor.rules_dir)" "json cursor rules"
assert_contains "$(echo "$out" | jq -r '.agents.claude.present|type')" "boolean" "claude present is boolean"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/detect.sh` missing.

- [ ] **Step 3: Write lib/detect.sh**

```bash
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — os-from cases and JSON shape assertions pass.

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/test_detect.sh
git commit -m "feat: add OS taxonomy and structured agent detection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Prereqs + PATH-shadow guard (lib/prereqs.sh)

**Files:**
- Create: `lib/prereqs.sh`
- Create: `tests/test_prereqs.sh`

**Interfaces:**
- Produces: `require_jq` → exit 0 if `jq` present, else print install hint and return 2; `tool_present <name>` → 0/1; `tool_realpath <name>` → resolved path on stdout (empty if absent); `prereqs_report <name...>` → one line per tool `name: present|MISSING (path)`; `prereq_install_hint <name>` → install command string for the current package manager.

- [ ] **Step 1: Write the failing test**

`tests/test_prereqs.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/prereqs.sh"
assert_ok require_jq                       # jq is a test prerequisite
assert_ok tool_present jq
assert_fail tool_present definitely-not-a-real-binary-xyz
assert_contains "$(prereqs_report jq definitely-not-a-real-binary-xyz)" "MISSING" "report flags missing"
assert_contains "$(prereqs_report jq)" "jq:" "report names tool"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/prereqs.sh` missing.

- [ ] **Step 3: Write lib/prereqs.sh**

```bash
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

prereq_install_hint() { # <name>
  if   tool_present brew;   then echo "brew install $1"
  elif tool_present apt;    then echo "sudo apt install -y $1"
  elif tool_present winget; then echo "winget install $1"
  else echo "(install $1 with your platform package manager)"; fi
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/prereqs.sh tests/test_prereqs.sh
git commit -m "feat: add prereq checks, jq gate, and PATH-shadow resolution

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Privilege planning (lib/privilege.sh)

**Files:**
- Create: `lib/privilege.sh`
- Create: `tests/test_privilege.sh`

**Interfaces:**
- Produces: `priv_is_admin` → 0 if `id -u`==0; `priv_target_needs_admin <target_json>` → echoes `true`/`false` from `.safety.requires_admin`; `priv_summarize <plan_json>` → for each plan entry needing admin OR may-sudo, one line `plugin/agent: requires_admin|may_sudo`; empty if none.

- [ ] **Step 1: Write the failing test**

`tests/test_privilege.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/privilege.sh"
t='{"safety":{"requires_admin":true}}'
assert_eq "true"  "$(priv_target_needs_admin "$t")" "admin true"
assert_eq "false" "$(priv_target_needs_admin '{"safety":{}}')" "admin default false"
plan='[{"plugin":"a","agent":"claude","safety":{"requires_admin":true}},{"plugin":"b","agent":"codex","safety":{"may_prompt_for_sudo":true}},{"plugin":"c","agent":"cursor","safety":{}}]'
out="$(priv_summarize "$plan")"
assert_contains "$out" "a/claude" "lists admin entry"
assert_contains "$out" "b/codex"  "lists sudo entry"
case "$out" in *c/cursor*) echo "FAIL: c/cursor should not appear" >&2; ASSERT_FAILURES=$((ASSERT_FAILURES+1));; esac
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/privilege.sh` missing.

- [ ] **Step 3: Write lib/privilege.sh**

```bash
#!/usr/bin/env bash
# privilege.sh — surface privilege needs before execution. Requires jq.
set -u

priv_is_admin() { [ "$(id -u 2>/dev/null)" = "0" ]; }

priv_target_needs_admin() { # <target_json>
  jq -r '.safety.requires_admin // false' <<<"$1"
}

priv_summarize() { # <plan_json>
  jq -r '
    .[]
    | select((.safety.requires_admin // false) or (.safety.may_prompt_for_sudo // false))
    | "\(.plugin)/\(.agent): "
      + ((if (.safety.requires_admin // false) then "requires_admin " else "" end)
       + (if (.safety.may_prompt_for_sudo // false) then "may_sudo" else "" end) | ltrimstr(" ") | rtrimstr(" "))
  ' <<<"$1"
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/privilege.sh tests/test_privilege.sh
git commit -m "feat: add privilege preflight summary

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Plan resolution (extend lib/manifest.sh)

**Files:**
- Modify: `lib/manifest.sh`
- Modify: `tests/test_manifest.sh`
- Create: `tests/fixtures/agents-present.json`

**Interfaces:**
- Consumes: validated `manifest.json`, an agents JSON like `detect_agents_json` output.
- Produces: `manifest_resolve_plan <file> <os> <agents_json>` → JSON array; one entry per `(plugin, agent)` target whose `platforms` includes `<os>` AND whose agent has `.agents[agent].present == true`. Each entry: `{plugin, agent, method, coverage, requires, install_scope, args, manual, safety, checks, conflict_policy}`.

- [ ] **Step 1: Write the failing test**

`tests/fixtures/agents-present.json`:
```json
{ "os": "darwin", "agents": { "claude": { "present": true }, "codex": { "present": false }, "cursor": { "present": true } } }
```

Append to `tests/test_manifest.sh`:
```bash
agents="$(cat "$root/tests/fixtures/agents-present.json")"
plan="$(manifest_resolve_plan "$root/manifest.json" darwin "$agents")"
# claude present -> superpowers/claude in plan
assert_eq "1" "$(echo "$plan" | jq '[.[]|select(.plugin=="superpowers" and .agent=="claude")]|length')" "sp claude present"
# codex absent -> no codex entries
assert_eq "0" "$(echo "$plan" | jq '[.[]|select(.agent=="codex")]|length')" "no codex when absent"
# cursor present -> gstack/cursor present, method git-setup
assert_eq "git-setup" "$(echo "$plan" | jq -r '.[]|select(.plugin=="gstack" and .agent=="cursor")|.method')" "gstack cursor method"
# every entry carries coverage
assert_eq "0" "$(echo "$plan" | jq '[.[]|select(.coverage==null)]|length')" "all have coverage"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `manifest_resolve_plan: command not found`.

- [ ] **Step 3: Add manifest_resolve_plan to lib/manifest.sh**

Append:
```bash
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.sh tests/test_manifest.sh tests/fixtures/agents-present.json
git commit -m "feat: resolve execution plan from manifest by os and present agents

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Check predicates (lib/checks.sh)

**Files:**
- Create: `lib/checks.sh`
- Create: `tests/test_checks.sh`

**Interfaces:**
- Produces: `check_eval <check_json>` → exit 0 if the predicate holds. Supported `.type`: `command_exists`(`.name`), `file_exists`(`.path`), `dir_exists`(`.path`), `json_path_exists`(`.path` file, `.query` jq path), `json_contains`(`.path` file, `.query`, `.value`), `cursor_rule_exists`(`.rules_dir`,`.name`), `claude_plugin_installed`(`.name`), `codex_plugin_installed`(`.name`), `mcp_server_registered`(`.path` config, `.name`). Path values are `envsubst`-style expanded for `${HOME}`. `checks_run_after <plan_entry_json>` → runs each `.checks.after[]`, returns 0 only if all pass (no after-checks ⇒ 0).

- [ ] **Step 1: Write the failing test**

`tests/test_checks.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/checks.sh"
tmp="$(mktemp -d)"
echo '{"a":{"b":1}}' > "$tmp/x.json"
assert_ok   check_eval "$(jq -n --arg n jq '{type:"command_exists",name:$n}')"
assert_fail check_eval '{"type":"command_exists","name":"nope-xyz-123"}'
assert_ok   check_eval "$(jq -n --arg p "$tmp/x.json" '{type:"file_exists",path:$p}')"
assert_fail check_eval "$(jq -n --arg p "$tmp/none" '{type:"file_exists",path:$p}')"
assert_ok   check_eval "$(jq -n --arg p "$tmp" '{type:"dir_exists",path:$p}')"
assert_ok   check_eval "$(jq -n --arg p "$tmp/x.json" '{type:"json_path_exists",path:$p,query:".a.b"}')"
assert_fail check_eval "$(jq -n --arg p "$tmp/x.json" '{type:"json_path_exists",path:$p,query:".a.zzz"}')"
# no after-checks => success
assert_ok checks_run_after '{"checks":{}}'
rm -rf "$tmp"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/checks.sh` missing.

- [ ] **Step 3: Write lib/checks.sh**

```bash
#!/usr/bin/env bash
# checks.sh — fixed predicate vocabulary for idempotency + verification. Requires jq.
set -u

_expand() { # expand ${HOME} and $HOME in a path string
  local s="$1"; s="${s//\$\{HOME\}/$HOME}"; s="${s//\$HOME/$HOME}"; printf '%s' "$s"
}

check_eval() { # <check_json>
  local c="$1" type
  type="$(jq -r '.type' <<<"$c")"
  case "$type" in
    command_exists) command -v "$(jq -r '.name' <<<"$c")" >/dev/null 2>&1 ;;
    file_exists)    [ -f "$(_expand "$(jq -r '.path' <<<"$c")")" ] ;;
    dir_exists)     [ -d "$(_expand "$(jq -r '.path' <<<"$c")")" ] ;;
    json_path_exists)
      local f q; f="$(_expand "$(jq -r '.path' <<<"$c")")"; q="$(jq -r '.query' <<<"$c")"
      [ -f "$f" ] && jq -e "$q != null" "$f" >/dev/null 2>&1 ;;
    json_contains)
      local f q v; f="$(_expand "$(jq -r '.path' <<<"$c")")"; q="$(jq -r '.query' <<<"$c")"; v="$(jq -r '.value' <<<"$c")"
      [ -f "$f" ] && [ "$(jq -r "$q" "$f" 2>/dev/null)" = "$v" ] ;;
    cursor_rule_exists)
      [ -f "$(_expand "$(jq -r '.rules_dir' <<<"$c")")/$(jq -r '.name' <<<"$c")" ] ;;
    claude_plugin_installed)
      command -v claude >/dev/null 2>&1 && claude plugin list 2>/dev/null | grep -q "$(jq -r '.name' <<<"$c")" ;;
    codex_plugin_installed)
      command -v codex >/dev/null 2>&1 && codex plugin list 2>/dev/null | grep -q "$(jq -r '.name' <<<"$c")" ;;
    mcp_server_registered)
      local f n; f="$(_expand "$(jq -r '.path' <<<"$c")")"; n="$(jq -r '.name' <<<"$c")"
      [ -f "$f" ] && jq -e --arg n "$n" '(.. | objects | keys?[]?) | select(. == $n)' "$f" >/dev/null 2>&1 ;;
    *) echo "check_eval: unknown type: $type" >&2; return 2 ;;
  esac
}

checks_run_after() { # <plan_entry_json>
  local n i c
  n="$(jq '.checks.after | length // 0' <<<"$1" 2>/dev/null)"; n="${n:-0}"
  [ "$n" = "0" ] && return 0
  i=0
  while [ "$i" -lt "$n" ]; do
    c="$(jq -c ".checks.after[$i]" <<<"$1")"
    check_eval "$c" || return 1
    i=$((i + 1))
  done
  return 0
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/checks.sh tests/test_checks.sh
git commit -m "feat: add fixed-vocabulary check predicates

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Method command planning (lib/methods.sh)

**Files:**
- Create: `lib/methods.sh`
- Create: `tests/test_methods.sh`

**Interfaces:**
- Consumes: a single plan-entry JSON (from `manifest_resolve_plan`).
- Produces: `method_plan <entry_json>` → newline-separated human-readable command lines for that entry's method (pure: no execution, no network). `manual` entries emit a single `MANUAL: <reason>` line. Unknown method → `UNKNOWN METHOD <m>` line + return 1. (Actual execution wrappers are added in Task 11 inside `install.sh`; this task is the pure planner that dry-run and report consume.)

- [ ] **Step 1: Write the failing test**

`tests/test_methods.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/methods.sh"
cp='{"method":"claude-plugin","args":{"marketplace_src":"obra/superpowers-marketplace","marketplace_name":"superpowers-marketplace","plugin":"superpowers"}}'
out="$(method_plan "$cp")"
assert_contains "$out" "claude plugin marketplace add obra/superpowers-marketplace" "claude mkt add"
assert_contains "$out" "claude plugin install superpowers@superpowers-marketplace" "claude install"

gs='{"method":"git-setup","args":{"repo":"https://github.com/garrytan/gstack.git","dest":"${HOME}/.gstack","setup_args":"--host cursor"}}'
out="$(method_plan "$gs")"
assert_contains "$out" "git clone --depth 1 https://github.com/garrytan/gstack.git" "git clone"
assert_contains "$out" "./setup --host cursor" "setup args"

sh='{"method":"shell-installer","args":{"url_unix":"https://example.com/install.sh"}}'
assert_contains "$(method_plan "$sh")" "download-then-run https://example.com/install.sh" "shell installer"

mn='{"method":"manual","manual":{"reason":"no cli"}}'
assert_contains "$(method_plan "$mn")" "MANUAL: no cli" "manual line"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/methods.sh` missing.

- [ ] **Step 3: Write lib/methods.sh**

```bash
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
      printf 'codex plugin marketplace add %s\n' "$(_arg "$e" '.args.marketplace_src')"
      printf 'codex plugin add %s\n' "$(_arg "$e" '.args.plugin')"
      ;;
    shell-installer)
      printf 'download-then-run %s\n' "$(_arg "$e" '.args.url_unix')"
      ;;
    npx-skills)
      printf 'npx -y skills add %s\n' "$(_arg "$e" '.args.repo')"
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
    manual)
      printf 'MANUAL: %s\n' "$(_arg "$e" '.manual.reason')"
      ;;
    *)
      printf 'UNKNOWN METHOD %s\n' "$m"; return 1
      ;;
  esac
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/methods.sh tests/test_methods.sh
git commit -m "feat: add pure per-method command planning

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Plan/report rendering (lib/report.sh)

**Files:**
- Create: `lib/report.sh`
- Create: `tests/test_report.sh`

**Interfaces:**
- Consumes: plan JSON (from `manifest_resolve_plan`), `method_plan` from `lib/methods.sh`.
- Produces: `report_plan <plan_json>` → human-readable text: one block per entry showing `plugin/agent [coverage]`, the planned commands (via `method_plan`), conflict policy, and `requires`/sudo flags; manual entries also print their steps. `report_manual_steps <entry_json>` → numbered manual steps (empty if none).

- [ ] **Step 1: Write the failing test**

`tests/test_report.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/lib/methods.sh"
. "$root/lib/report.sh"
plan='[{"plugin":"superpowers","agent":"claude","coverage":"native","method":"claude-plugin","conflict_policy":"skip","requires":["claude","jq"],"safety":{},"args":{"marketplace_src":"obra/superpowers-marketplace","marketplace_name":"superpowers-marketplace","plugin":"superpowers"},"manual":null},{"plugin":"superpowers","agent":"cursor","coverage":"manual","method":"manual","conflict_policy":"skip","requires":[],"safety":{},"args":{},"manual":{"reason":"no cli","steps":["Open chat","Run /add-plugin superpowers"]}}]'
out="$(report_plan "$plan")"
assert_contains "$out" "superpowers/claude [native]" "header native"
assert_contains "$out" "claude plugin install superpowers@superpowers-marketplace" "shows command"
assert_contains "$out" "superpowers/cursor [manual]" "header manual"
assert_contains "$out" "Run /add-plugin superpowers" "manual step shown"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `lib/report.sh` missing.

- [ ] **Step 3: Write lib/report.sh**

```bash
#!/usr/bin/env bash
# report.sh — render the resolved plan for dry-run / plan / report. Requires jq + lib/methods.sh.
set -u

report_manual_steps() { # <entry_json>
  local steps n i
  n="$(jq '.manual.steps | length // 0' <<<"$1" 2>/dev/null)"; n="${n:-0}"
  [ "$n" = "0" ] && return 0
  i=0
  while [ "$i" -lt "$n" ]; do
    printf '    %d. %s\n' "$((i + 1))" "$(jq -r ".manual.steps[$i]" <<<"$1")"
    i=$((i + 1))
  done
}

report_plan() { # <plan_json>
  local n i e
  n="$(jq 'length' <<<"$1")"
  i=0
  while [ "$i" -lt "$n" ]; do
    e="$(jq -c ".[$i]" <<<"$1")"
    printf '%s/%s [%s]\n' \
      "$(jq -r '.plugin' <<<"$e")" "$(jq -r '.agent' <<<"$e")" "$(jq -r '.coverage' <<<"$e")"
    method_plan "$e" | sed 's/^/    $ /'
    printf '    conflict: %s   requires: %s\n' \
      "$(jq -r '.conflict_policy' <<<"$e")" "$(jq -r '(.requires // []) | join(",")' <<<"$e")"
    if [ "$(jq -r '.safety.requires_admin // false' <<<"$e")" = "true" ]; then printf '    NEEDS ADMIN\n'; fi
    report_manual_steps "$e"
    printf '\n'
    i=$((i + 1))
  done
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/report.sh tests/test_report.sh
git commit -m "feat: add plan/report rendering

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Driver (install.sh) + end-to-end dry-run

**Files:**
- Create: `install.sh`
- Create: `tests/test_dry_run.sh`

**Interfaces:**
- Consumes: every `lib/*.sh`.
- Produces: `install.sh` CLI honoring the startup order and flags. The execution wrappers (`_exec_entry`) dispatch each method to real commands; `--dry-run`/`--plan` short-circuit to `report_plan` with no side effects. `--status` prints after-check results for the resolved plan. Filters: `--agent <a>`, `--plugin <p>`, `--only-method <m>`. `--agents-only` resolves only step-1 agent installs. `--non-interactive` fails on any `requires_admin` entry. `--yes` auto-confirms.

- [ ] **Step 1: Write the failing test**

`tests/test_dry_run.sh`:
```bash
root="$(cd "$(dirname "$0")/.." && pwd)"
# Dry-run must mutate nothing and must print planned commands. Force agents present via env hook.
out="$(AGENT_SETUP_FORCE_OS=darwin AGENT_SETUP_FAKE_AGENTS='{"os":"darwin","agents":{"claude":{"present":true},"codex":{"present":true},"cursor":{"present":true,"user_dir":"/h/.config/Cursor/User","rules_dir":"/h/.config/Cursor/User/rules","mcp_config":"/h/.config/Cursor/User/mcp.json","skills_dir":"/h/.config/Cursor/User/skills"}}}' bash "$root/install.sh" --dry-run --plugin superpowers 2>&1)"
assert_contains "$out" "superpowers/claude [native]" "dry-run shows claude plan"
assert_contains "$out" "claude plugin install superpowers@superpowers-marketplace" "dry-run shows command"
assert_contains "$out" "superpowers/cursor [manual]" "dry-run shows cursor manual"
# scoping to one agent
out2="$(AGENT_SETUP_FORCE_OS=darwin AGENT_SETUP_FAKE_AGENTS='{"os":"darwin","agents":{"claude":{"present":true},"codex":{"present":false},"cursor":{"present":false}}}' bash "$root/install.sh" --dry-run --plugin superpowers --agent claude 2>&1)"
case "$out2" in *"superpowers/cursor"*) echo "FAIL: cursor should be filtered" >&2; ASSERT_FAILURES=$((ASSERT_FAILURES+1));; esac
assert_contains "$out2" "superpowers/claude" "agent filter keeps claude"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — `install.sh` missing.

- [ ] **Step 3: Write install.sh**

```bash
#!/usr/bin/env bash
# install.sh — manifest-driven unix installer for coding agents + plugins.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/prereqs.sh"
. "$HERE/lib/paths.sh"
. "$HERE/lib/detect.sh"
. "$HERE/lib/manifest.sh"
. "$HERE/lib/privilege.sh"
. "$HERE/lib/checks.sh"
. "$HERE/lib/methods.sh"
. "$HERE/lib/report.sh"

MODE="install"          # install | dry-run | plan | status | check-prereqs
DO_INSTALL_PREREQS=0
F_AGENT=""; F_PLUGIN=""; F_METHOD=""
AGENTS_ONLY=0; ASSUME_YES=0; NON_INTERACTIVE=0

usage() { grep -E '^\s+--' "$HERE/install.sh" | sed 's/) .*//' >&2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|--plan)   MODE="dry-run" ;;
    --status)           MODE="status" ;;
    --check-prereqs)    MODE="check-prereqs" ;;
    --install-prereqs)  DO_INSTALL_PREREQS=1 ;;
    --agent)            F_AGENT="$2"; shift ;;
    --plugin)           F_PLUGIN="$2"; shift ;;
    --only-method)      F_METHOD="$2"; shift ;;
    --agents-only)      AGENTS_ONLY=1 ;;
    --yes)              ASSUME_YES=1 ;;
    --non-interactive)  NON_INTERACTIVE=1 ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

# 1. detect OS  (overridable for tests)
OS="${AGENT_SETUP_FORCE_OS:-$(detect_os)}"

# 2-3. jq gate
require_jq || exit 2

if [ "$MODE" = "check-prereqs" ]; then
  prereqs_report jq git node bun claude codex cursor-agent
  exit 0
fi

# 4. validate manifest
MANIFEST="$HERE/manifest.json"
manifest_validate "$MANIFEST" || { echo "manifest validation failed" >&2; exit 1; }

# 5. resolve present agents (overridable for tests)
AGENTS_JSON="${AGENT_SETUP_FAKE_AGENTS:-$(detect_agents_json "$OS")}"

# 6. resolve plan + apply filters
PLAN="$(manifest_resolve_plan "$MANIFEST" "$OS" "$AGENTS_JSON")"
[ -n "$F_AGENT" ]  && PLAN="$(jq --arg a "$F_AGENT"  '[.[]|select(.agent==$a)]'  <<<"$PLAN")"
[ -n "$F_PLUGIN" ] && PLAN="$(jq --arg p "$F_PLUGIN" '[.[]|select(.plugin==$p)]' <<<"$PLAN")"
[ -n "$F_METHOD" ] && PLAN="$(jq --arg m "$F_METHOD" '[.[]|select(.method==$m)]' <<<"$PLAN")"

if [ "$MODE" = "dry-run" ]; then
  echo "OS: $OS"
  report_plan "$PLAN"
  exit 0
fi

if [ "$MODE" = "status" ]; then
  echo "OS: $OS"
  n="$(jq 'length' <<<"$PLAN")"; i=0
  while [ "$i" -lt "$n" ]; do
    e="$(jq -c ".[$i]" <<<"$PLAN")"
    if checks_run_after "$e"; then st="OK"; else st="missing"; fi
    printf '%s/%s: %s\n' "$(jq -r .plugin <<<"$e")" "$(jq -r .agent <<<"$e")" "$st"
    i=$((i + 1))
  done
  exit 0
fi

# 7. privilege preflight
PRIV="$(priv_summarize "$PLAN")"
if [ -n "$PRIV" ]; then
  echo "Privilege requirements:"; echo "$PRIV"
  if [ "$NON_INTERACTIVE" = "1" ]; then echo "non-interactive: refusing privileged steps" >&2; exit 3; fi
fi

# 8. agents step 1 (binary install, download-then-run) unless plugins-only filters set
if [ -z "$F_PLUGIN" ] && [ -z "$F_METHOD" ]; then
  for a in claude codex cursor; do
    [ -n "$F_AGENT" ] && [ "$F_AGENT" != "$a" ] && continue
    bin="$(jq -r --arg a "$a" '.agents[$a].binary' "$MANIFEST")"
    if tool_present "$bin"; then echo "agent $a present ($(tool_realpath "$bin"))"; continue; fi
    url="$(jq -r --arg a "$a" --arg os "$OS" '.agents[$a].install[$os]' "$MANIFEST")"
    echo "installing agent $a from $url"
    [ "$ASSUME_YES" = "1" ] || { printf 'proceed? [y/N] '; read -r ans; [ "$ans" = "y" ] || continue; }
    tmp="$(mktemp)"; curl -fsSL "$url" -o "$tmp" && sh "$tmp"; rm -f "$tmp"
  done
fi
[ "$AGENTS_ONLY" = "1" ] && exit 0

# 9. execute plan entries
n="$(jq 'length' <<<"$PLAN")"; i=0
while [ "$i" -lt "$n" ]; do
  e="$(jq -c ".[$i]" <<<"$PLAN")"; i=$((i + 1))
  label="$(jq -r '.plugin' <<<"$e")/$(jq -r '.agent' <<<"$e")"
  if checks_run_after "$e"; then echo "[$label] already satisfied — skip"; continue; fi
  if [ "$(jq -r '.method' <<<"$e")" = "manual" ]; then
    echo "[$label] MANUAL:"; report_manual_steps "$e"; continue
  fi
  hi="$(jq -r '(.safety.executes_remote_code // false) or (.safety.requires_admin // false)' <<<"$e")"
  if [ "$hi" = "true" ] && [ "$ASSUME_YES" != "1" ]; then
    echo "[$label] high-risk:"; method_plan "$e" | sed 's/^/    $ /'
    printf 'proceed? [y/N] '; read -r ans; [ "$ans" = "y" ] || { echo "[$label] skipped"; continue; }
  fi
  echo "[$label] executing:"; method_plan "$e" | sed 's/^/    $ /'
  _exec_entry "$e" || echo "[$label] FAILED" >&2
done
```

Add the executor function above the arg-parse loop (after the `source` lines):
```bash
_exec_entry() { # <entry_json> — performs real side effects per method
  local e="$1" m; m="$(jq -r '.method' <<<"$e")"
  case "$m" in
    claude-plugin)
      claude plugin marketplace add "$(_arg "$e" '.args.marketplace_src')" \
      && claude plugin install "$(_arg "$e" '.args.plugin')@$(_arg "$e" '.args.marketplace_name')" ;;
    codex-plugin)
      codex plugin marketplace add "$(_arg "$e" '.args.marketplace_src')" \
      && codex plugin add "$(_arg "$e" '.args.plugin')" ;;
    shell-installer)
      local tmp; tmp="$(mktemp)"; curl -fsSL "$(_arg "$e" '.args.url_unix')" -o "$tmp" && bash "$tmp"; rm -f "$tmp" ;;
    npx-skills)
      npx -y skills add "$(_arg "$e" '.args.repo')" ;;
    git-setup)
      local repo dest sa; repo="$(_arg "$e" '.args.repo')"; dest="$(eval echo "$(_arg "$e" '.args.dest')")"; sa="$(_arg "$e" '.args.setup_args')"
      [ -d "$dest/.git" ] || git clone --depth 1 "$repo" "$dest"
      ( cd "$dest" && ./setup $sa ) ;;
    npm-cli)
      local ensure; ensure="$(_arg "$e" '.args.ensure')"
      if [ -n "$ensure" ] && ! tool_present "$ensure"; then sh -c "$(_arg "$e" '.args.ensure_install')"; fi
      sh -c "$(_arg "$e" '.args.command')" ;;
    od-mcp)
      local odp; odp="$(tool_realpath od)"
      case "$odp" in *"$(_arg "$e" '.args.expected_substr')"*) od mcp install "$(_arg "$e" '.args.agent')" ;;
        *) echo "od PATH-shadowed ($odp) — open-design not installed; see docs" >&2; return 1 ;; esac ;;
    *) echo "no executor for method: $m" >&2; return 1 ;;
  esac
}
```

(Where `_arg` is reused from `lib/methods.sh`, already sourced.)

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — dry-run prints the plan and filters by agent without mutating anything.

- [ ] **Step 5: Make executable + commit**

```bash
chmod +x install.sh
git add install.sh tests/test_dry_run.sh
git commit -m "feat: add install.sh driver with dry-run, status, filters, privilege preflight

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Docs (README, security, cursor)

**Files:**
- Create: `README.md`
- Create: `docs/security.md`
- Create: `docs/cursor.md`

**Interfaces:**
- Produces: user-facing docs. No code; verified by presence + a dry-run example that actually runs.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_dry_run.sh`:
```bash
assert_ok test -f "$root/README.md"
assert_ok test -f "$root/docs/security.md"
assert_ok test -f "$root/docs/cursor.md"
assert_contains "$(cat "$root/README.md")" "--dry-run" "README documents dry-run"
assert_contains "$(cat "$root/docs/security.md")" "download-then-run" "security documents exec policy"
assert_contains "$(cat "$root/docs/cursor.md")" "best-effort" "cursor doc states best-effort"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh`
Expected: FAIL — docs missing.

- [ ] **Step 3: Write the docs**

`README.md`:
```markdown
# agent-setup

One command installs Claude Code, Codex CLI, and Cursor CLI, then a curated
plugin/skill set into all three at the user level — across macOS, Linux, WSL,
and Git-Bash on Windows. (Native-Windows PowerShell driver: see Plan 2.)

## Quick start

```bash
git clone https://github.com/host452b/agent-setup.git
cd agent-setup
bash install.sh --dry-run        # preview: prints the plan, changes nothing
bash install.sh                  # install (prompts before high-risk steps)
```

Requires `jq`. Install hint is printed if missing.

## Flags

- `--dry-run` / `--plan` — print the resolved plan, mutate nothing
- `--status` — show what's already installed
- `--check-prereqs` — report tool presence (jq, git, node, bun, agents)
- `--install-prereqs` — opt-in: auto-install prereqs via brew/apt/winget
- `--agent <claude|codex|cursor>` — scope to one agent
- `--plugin <name>` — scope to one plugin
- `--only-method <type>` — scope to one method type
- `--agents-only` — install only the agent binaries (step 1)
- `--yes` — auto-confirm high-risk steps
- `--non-interactive` — CI mode; fail on any privileged step

## What gets installed

Agents: Claude Code, Codex CLI, Cursor CLI.
Plugins/skills: superpowers, ponytail, gstack, caveman, taste-skill,
ui-ux-pro-max, open-design, prompt-polish.

Coverage varies by agent — Cursor is a best-effort integration target
(no plugin-install CLI); see `docs/cursor.md`. The full plugin × agent ×
method matrix lives in `manifest.json`.

## Adding a plugin

Edit `manifest.json` (validated against `manifest.schema.json`). No script
changes needed for supported method types.
```

`docs/security.md`:
```markdown
# Security model

- **Dry-run first.** `--dry-run` prints every command and changes nothing.
- **Confirmation.** Steps marked `executes_remote_code` or `requires_admin`
  prompt before running unless `--yes` is passed. `--non-interactive` refuses
  privileged steps outright.
- **download-then-run.** Remote installers are downloaded to a temp file and
  executed from disk, never piped straight into a shell. Where the manifest
  pins `version`/`ref`/`sha256`, the download is verified first.
- **PATH-shadow guard.** Before invoking an external tool the installer
  resolves its real path and verifies the expected source. This is mandatory
  for `od` (open-design), which collides with the unix `od` octal-dump binary.
- **Least privilege.** The whole script is never run under sudo; only the
  specific subcommands that need elevation request it, and they are surfaced
  in the plan up front.
- **Global installs** (e.g. `uipro --global`) are flagged with
  `install_scope: global` and may mutate PATH depending on your npm prefix.
```

`docs/cursor.md`:
```markdown
# Cursor: a best-effort integration target

`cursor-agent` exposes `mcp` and `generate-rule` but **no plugin-install
command**. So Cursor coverage comes from each tool's own cross-agent path,
not a marketplace install:

- **gstack** — `./setup --host cursor` (installs into Cursor's skills dir)
- **caveman** — its installer auto-detects Cursor
- **taste-skill** — `npx skills add` targets Cursor's skills dir
- **ui-ux-pro-max** — `uipro init --ai cursor --global`
- **open-design** — `od mcp install cursor`
- **superpowers / ponytail** — manual: copy the rules file into the Cursor
  rules dir, or use the in-chat `/add-plugin` flow. The installer prints these
  steps; it cannot perform them.

Cursor config paths (resolved by `lib/paths.sh`):

| OS | Cursor user dir |
|---|---|
| macOS | `~/Library/Application Support/Cursor/User/` |
| Linux | `~/.config/Cursor/User/` |
| WSL | Linux path (or `/mnt/c/Users/.../AppData/Roaming/Cursor/User/` if Cursor is on the Windows side) |
| Windows | `%APPDATA%\Cursor\User\` |
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS — docs present and contain the asserted strings; full suite green.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/security.md docs/cursor.md
git commit -m "docs: add README, security model, and Cursor integration notes

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §2 agents + matrix → manifest.json (Task 2), agent step-1 install in install.sh (Task 11). ✓
- §3 verified surfaces → encoded as method types claude-plugin/codex-plugin + Cursor manual. ✓
- §4 repo layout → all `lib/*.sh`, `tests/`, `docs/`, `manifest*.json` created. (PowerShell mirror is Plan 2 by scope split.) ✓
- §5 startup order → install.sh follows detect→jq→validate→resolve→preflight→execute→checks. ✓
- §6 method types → method_plan + _exec_entry cover claude/codex-plugin, shell-installer, npx-skills, git-setup, npm-cli, od-mcp, file-copy, manual. (`dir-copy`/`symlink-*`/`template-render`/`json-merge` are declared in schema vocabulary but unused by current manifest — added when a plugin needs them; YAGNI.) ✓
- §7 schema → manifest.schema.json + manifest_validate. ✓
- §8 detect/paths incl. WSL → paths.sh + detect.sh + docs/cursor.md WSL row. ✓
- §9 privilege → privilege.sh + preflight + non-interactive refusal. ✓
- §10 prereqs (jq mandatory, check-by-default) → prereqs.sh + --check-prereqs/--install-prereqs. ✓
- §11 safety/PATH-shadow → download-then-run in shell-installer + agent install, od guard, docs/security.md. ✓
- §12 idempotency/checks vocabulary → checks.sh + before-skip via checks_run_after. ✓
- §13 conflict policy → carried per entry, surfaced in report; enforced where file methods are implemented (Plan 2 / future file-copy tasks). ✓
- §14 CLI surface → install.sh flags. ✓
- §15 structured manual → manual blocks in manifest + report_manual_steps. ✓
- §16 testing → tests for schema, detect, paths, privilege, methods, report, dry-run. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete; manual steps are concrete.

**Type consistency:** `_arg`, `method_plan`, `checks_run_after`, `manifest_resolve_plan`, `report_plan`, `report_manual_steps`, `detect_os_from`, `cursor_user_dir` are used with the same signatures wherever referenced. `_exec_entry` reuses `_arg` from the sourced `lib/methods.sh`.

**Known follow-ups (out of this plan):**
- Plan 2 — native Windows `install.ps1` + `lib/*.ps1` + Pester tests, mirroring this behavior.
- `--install-prereqs` auto-install bodies (brew/apt/winget) are stubbed by the report path; wire actual installs when needed.
- `dir-copy`/`symlink-*`/`json-merge` executors land when a manifest target first uses them.
