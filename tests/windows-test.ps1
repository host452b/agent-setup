#!/usr/bin/env pwsh
# Dependency-free unit tests for install.ps1's pure functions (no Pester needed).
# Run: pwsh -NoProfile -File tests/windows-test.ps1
$ErrorActionPreference = 'Stop'
$script:fails = 0
function Assert-Eq($expected, $actual, $msg) {
  if ("$expected" -ne "$actual") { Write-Host "FAIL: $msg`n  expected: $expected`n  actual:   $actual"; $script:fails++ }
}
function Assert-True($cond, $msg) { if (-not $cond) { Write-Host "FAIL: $msg"; $script:fails++ } }

$root = Split-Path -Parent $PSScriptRoot
$env:AGENT_SETUP_PS_NOMAIN = '1'
. (Join-Path $root 'install.ps1')

# OS
Assert-Eq 'windows' (Get-OsName) 'Get-OsName is windows'

# cursor-cli home (uses the read-only automatic $HOME)
Assert-Eq (Join-Path $HOME '.cursor') (Get-CursorUserDir) 'cursor user dir is ~/.cursor'

# home expansion
Assert-Eq "$HOME/x" (Expand-Home '${HOME}/x') 'Expand-Home ${HOME}'
Assert-Eq "$HOME/y" (Expand-Home '$HOME/y') 'Expand-Home $HOME'

# method planning
$cp = [pscustomobject]@{ method='claude-plugin'; args=[pscustomobject]@{ marketplace_src='obra/superpowers-marketplace'; marketplace_name='superpowers-marketplace'; plugin='superpowers' } }
$lines = Get-MethodPlan $cp
Assert-True ($lines -contains 'claude plugin install superpowers@superpowers-marketplace') 'claude-plugin install line'

$cx = [pscustomobject]@{ method='codex-plugin'; args=[pscustomobject]@{ marketplace_src='obra/superpowers'; marketplace_name='superpowers-dev'; plugin='superpowers' } }
$lines = Get-MethodPlan $cx
Assert-True ($lines -contains 'codex plugin add superpowers@superpowers-dev') 'codex-plugin @marketplace line'

$sy = [pscustomobject]@{
  method='git-symlink'
  args=[pscustomobject]@{
    repo='https://github.com/host452b/polish.git'
    clone_dest='${HOME}/.agent-setup/repos/polish'
    link_subpath='skills/prompt-polish'
    link='${HOME}/.cursor/skills/prompt-polish'
  }
}
$lines = Get-MethodPlan $sy
Assert-True ($lines -contains 'git clone --depth 1 https://github.com/host452b/polish.git ${HOME}/.agent-setup/repos/polish') 'git-symlink clone line'
Assert-True ($lines -contains 'link ${HOME}/.agent-setup/repos/polish/skills/prompt-polish -> ${HOME}/.cursor/skills/prompt-polish') 'git-symlink subpath line'

$mn = [pscustomobject]@{ method='manual'; manual=[pscustomobject]@{ reason='no cli' } }
Assert-True ((Get-MethodPlan $mn) -contains 'MANUAL: no cli') 'manual line'

$na = [pscustomobject]@{ method='unsupported'; manual=[pscustomobject]@{ reason='nope' } }
Assert-True ((Get-MethodPlan $na) -contains 'N/A: nope') 'unsupported line'

# resolve plan from real manifest
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
$present = @{ claude=$true; codex=$false; cursor=$true }
$resolved = Resolve-Plan $manifest $present
Assert-True (($resolved | Where-Object { $_.plugin -eq 'superpowers' -and $_.agent -eq 'claude' }).Count -ge 1) 'plan includes superpowers/claude'
Assert-True (($resolved | Where-Object { $_.agent -eq 'codex' }).Count -eq 0) 'no codex entries when codex absent'
Assert-True (($resolved | Where-Object { $_.coverage -eq $null }).Count -eq 0) 'every entry has coverage'

if ($script:fails -gt 0) { Write-Host "`nFAILED: $($script:fails)"; exit 1 } else { Write-Host "windows-test: all assertions passed"; exit 0 }
