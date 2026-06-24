#!/usr/bin/env pwsh
# install.ps1 — manifest-driven installer for coding agents + plugins (native Windows).
# Mirrors install.sh; reads the same manifest.json via ConvertFrom-Json (no jq needed).
[CmdletBinding()]
param(
  [switch] $DryRun,
  [switch] $Plan,
  [switch] $Status,
  [switch] $CheckPrereqs,
  [switch] $SkipPrereqs,
  [string] $Agent,
  [string] $Plugin,
  [string] $OnlyMethod,
  [switch] $AgentsOnly,
  [switch] $Yes,
  [switch] $NonInteractive
)

$ErrorActionPreference = 'Stop'
$HERE = Split-Path -Parent $MyInvocation.MyCommand.Path
$OS = 'windows'

function Test-Cmd($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }

function Expand-Home([string]$s) {
  if ($null -eq $s) { return '' }
  $s = $s -replace '\$\{HOME\}', $HOME
  $s = $s -replace '\$HOME', $HOME
  return $s
}

# --- Cursor (cursor-agent CLI) paths: ~/.cursor on every OS ---
function Get-CursorUserDir { Join-Path $HOME '.cursor' }

# --- OS detection helper (pure; this driver only runs on windows) ---
function Get-OsName { 'windows' }

# --- prereqs ---
function Install-Prereq([string]$name) {
  if (Test-Cmd $name) { return }
  switch ($name) {
    'bun' {
      Write-Host "installing bun (user-level)..."
      try { Invoke-RestMethod https://bun.sh/install.ps1 | Invoke-Expression } catch { Write-Warning "bun install failed: $_" }
      $bunbin = Join-Path $HOME '.bun\bin'
      if (Test-Path $bunbin) { $env:PATH = "$bunbin;$env:PATH" }
    }
    default {
      if (Test-Cmd winget) {
        $id = switch ($name) { 'git' {'Git.Git'} 'node' {'OpenJS.NodeJS'} 'jq' {'jqlang.jq'} default {$name} }
        Write-Host "installing $name -> winget install $id"
        try { winget install --silent --accept-package-agreements --accept-source-agreements $id } catch { Write-Warning "could not auto-install $name" }
      } else {
        Write-Warning "no winget; please install $name manually"
      }
    }
  }
}

# --- manifest ---
function Get-Manifest { Get-Content (Join-Path $HERE 'manifest.json') -Raw | ConvertFrom-Json }

function Get-Present {
  @{
    claude = Test-Cmd 'claude'
    codex  = Test-Cmd 'codex'
    cursor = Test-Cmd 'cursor-agent'
  }
}

function Resolve-Plan($manifest, $present) {
  $entries = @()
  foreach ($p in $manifest.plugins.PSObject.Properties) {
    foreach ($t in $p.Value.targets.PSObject.Properties) {
      $agent = $t.Name; $tg = $t.Value
      if (-not ($tg.platforms -contains $OS)) { continue }
      if (-not $present[$agent]) { continue }
      $entries += [pscustomobject]@{
        plugin          = $p.Name
        agent           = $agent
        method          = $tg.method
        coverage        = $tg.coverage
        requires        = $tg.requires
        args            = $tg.args
        manual          = $tg.manual
        safety          = $tg.safety
        checks          = $tg.checks
        conflict_policy = $tg.conflict_policy
      }
    }
  }
  return $entries
}

# --- checks (after) ---
function Test-Check($c) {
  switch ($c.type) {
    'command_exists' { return (Test-Cmd $c.name) }
    'file_exists'    { return (Test-Path -PathType Leaf (Expand-Home $c.path)) }
    'dir_exists'     { return (Test-Path (Expand-Home $c.path)) }
    'claude_plugin_installed' { if (-not (Test-Cmd claude)) { return $false }; return ([bool]((claude plugin list 2>$null) -match $c.name)) }
    'codex_plugin_installed'  { if (-not (Test-Cmd codex))  { return $false }; return ([bool]((codex plugin list 2>$null)  -match $c.name)) }
    default { return $false }
  }
}
function Has-After($e) { return ($e.checks -and $e.checks.after -and $e.checks.after.Count -gt 0) }
function Run-After($e) {
  if (-not (Has-After $e)) { return $true }
  foreach ($c in $e.checks.after) { if (-not (Test-Check $c)) { return $false } }
  return $true
}

# --- confirm: 3s countdown, default yes ---
function Confirm-Step([string]$prompt) {
  if ($NonInteractive) { return $false }
  if ($Yes) { return $true }
  try { $null = [Console]::KeyAvailable } catch { return $true }  # no console (piped) -> auto-yes
  for ($s = 3; $s -ge 1; $s--) {
    Write-Host -NoNewline ("`r{0}  auto-yes in {1}s (press n to decline) " -f $prompt, $s)
    $waited = 0
    while ($waited -lt 1000) {
      if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true); Write-Host ""
        return -not ($k.KeyChar -eq 'n' -or $k.KeyChar -eq 'N')
      }
      Start-Sleep -Milliseconds 50; $waited += 50
    }
  }
  Write-Host ""
  return $true
}

# --- method command planning (pure, for dry-run) ---
function Get-MethodPlan($e) {
  $a = $e.args
  switch ($e.method) {
    'claude-plugin' { @("claude plugin marketplace add $($a.marketplace_src)", "claude plugin install $($a.plugin)@$($a.marketplace_name)") }
    'codex-plugin'  { $spec = $a.plugin; if ($a.marketplace_name) { $spec = "$($a.plugin)@$($a.marketplace_name)" }; @("codex plugin marketplace add $($a.marketplace_src)", "codex plugin add $spec") }
    'shell-installer' { @("download-then-run $($a.url_win)") }
    'npx-skills'    { @("npx -y skills add $($a.repo) $($a.extra)") }
    'git-setup'     { @("git clone --depth 1 $($a.repo) $($a.dest)", "bash ./setup $($a.setup_args)") }
    'git-symlink'   { @("git clone --depth 1 $($a.repo) $($a.clone_dest)", "link -> $($a.link)") }
    'npm-cli'       { @($a.command) }
    'od-mcp'        { @("od mcp install $($a.agent)") }
    'manual'        { @("MANUAL: $($e.manual.reason)") }
    'unsupported'   { @("N/A: $($e.manual.reason)") }
    default         { @("UNKNOWN METHOD $($e.method)") }
  }
}

# --- executor: returns 0 ok / 3 skip / 1 fail ---
function Invoke-Entry($e) {
  $a = $e.args
  try {
    switch ($e.method) {
      'claude-plugin' {
        claude plugin marketplace add $a.marketplace_src
        claude plugin install "$($a.plugin)@$($a.marketplace_name)"
        return 0
      }
      'codex-plugin' {
        $spec = $a.plugin; if ($a.marketplace_name) { $spec = "$($a.plugin)@$($a.marketplace_name)" }
        codex plugin marketplace add $a.marketplace_src 2>$null | Out-Null
        codex plugin add $spec
        if ($LASTEXITCODE -eq 0) { return 0 }
        Write-Host "  codex plugin add '$spec' failed - install via codex /plugins, or upgrade codex"
        return 3
      }
      'shell-installer' {
        if (-not $a.url_win) { Write-Host "  no Windows installer for this tool"; return 3 }
        $tmp = [System.IO.Path]::GetTempFileName() + '.ps1'
        Invoke-WebRequest -Uri $a.url_win -OutFile $tmp
        & pwsh -NoProfile -File $tmp
        Remove-Item $tmp -ErrorAction SilentlyContinue
        return 0
      }
      'npx-skills' {
        & cmd /c "npx -y skills add $($a.repo) $($a.extra)"
        return 0
      }
      'git-setup' {
        $dest = Expand-Home $a.dest
        if (-not (Test-Path (Join-Path $dest '.git'))) { git clone --depth 1 $a.repo $dest }
        if (-not (Test-Cmd bash)) { Write-Host "  gstack setup needs bash (install Git for Windows)"; return 3 }
        $env:PATH = "$(Join-Path $HOME '.bun\bin');$env:PATH"
        Push-Location $dest; try { bash -lc "./setup $($a.setup_args)" } finally { Pop-Location }
        return 0
      }
      'git-symlink' {
        $clone = Expand-Home $a.clone_dest; $link = Expand-Home $a.link
        if (-not (Test-Path (Join-Path $clone '.git'))) { git clone --depth 1 $a.repo $clone }
        $parent = Split-Path -Parent $link
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        if (Test-Path $link) { Remove-Item -Recurse -Force $link }
        # symlink needs admin/dev-mode on Windows; fall back to a copy
        try { New-Item -ItemType SymbolicLink -Path $link -Target $clone -ErrorAction Stop | Out-Null }
        catch { Copy-Item -Recurse -Force $clone $link }
        return 0
      }
      'npm-cli' {
        Push-Location $HOME; try { & cmd /c $a.command } finally { Pop-Location }
        return 0
      }
      'od-mcp' {
        $od = Get-Command od -ErrorAction SilentlyContinue
        if (-not $od) { Write-Host "  open-design: 'od' not installed - skipping"; return 3 }
        od mcp install $a.agent; return 0
      }
      default { Write-Host "  no executor for method: $($e.method)"; return 1 }
    }
  } catch {
    Write-Host "  error: $_"
    return 1
  }
}

# ===== main =====
if ($env:AGENT_SETUP_PS_NOMAIN) { return }   # tests dot-source for function access only
if (-not $SkipPrereqs -and -not $DryRun -and -not $Status -and -not $CheckPrereqs) {
  foreach ($t in @('git','node','bun')) { Install-Prereq $t }
}

if ($CheckPrereqs) {
  foreach ($t in @('git','node','bun','claude','codex','cursor-agent')) {
    if (Test-Cmd $t) { Write-Host "${t}: present" } else { Write-Host "${t}: MISSING" }
  }
  return
}

$manifest = Get-Manifest
$present  = Get-Present
$entries     = Resolve-Plan $manifest $present

if ($Agent)      { $entries = $entries | Where-Object { $_.agent  -eq $Agent } }
if ($Plugin)     { $entries = $entries | Where-Object { $_.plugin -eq $Plugin } }
if ($OnlyMethod) { $entries = $entries | Where-Object { $_.method -eq $OnlyMethod } }

if ($DryRun -or $Plan) {
  Write-Host "OS: $OS"
  foreach ($e in $entries) {
    Write-Host "$($e.plugin)/$($e.agent) [$($e.coverage)]"
    foreach ($l in (Get-MethodPlan $e)) { Write-Host "    `$ $l" }
  }
  return
}

if ($Status) {
  Write-Host "OS: $OS"
  foreach ($e in $entries) {
    if (-not (Has-After $e)) { $st = 'no-check' } elseif (Run-After $e) { $st = 'OK' } else { $st = 'missing' }
    Write-Host "$($e.plugin)/$($e.agent): $st"
  }
  return
}

# agent step-1 (binary install) unless plugin/method filters set
if (-not $Plugin -and -not $OnlyMethod) {
  foreach ($an in @('claude','codex','cursor')) {
    if ($Agent -and $Agent -ne $an) { continue }
    $bin = $manifest.agents.$an.binary
    if (Test-Cmd $bin) { Write-Host "agent $an present"; continue }
    $url = $manifest.agents.$an.install.$OS
    Write-Host "installing agent $an from $url"
    if (Confirm-Step "  install agent $an?") {
      try { Invoke-RestMethod $url | Invoke-Expression } catch { Write-Warning "agent $an install failed: $_" }
    } else { Write-Host "agent $an skipped" }
  }
}
if ($AgentsOnly) { return }

# execute
$report = @()
foreach ($e in $entries) {
  $label = "$($e.plugin)/$($e.agent)"
  if ((Has-After $e) -and (Run-After $e)) { Write-Host "[$label] already satisfied - skip"; $report += @{s='ok';l=$label;r='already installed'}; continue }
  if ($e.method -eq 'unsupported') { $r = $e.manual.reason; Write-Host "[$label] N/A - $r"; $report += @{s='na';l=$label;r=$r}; continue }
  if ($e.method -eq 'manual') {
    Write-Host "[$label] MANUAL:"; if ($e.manual.steps) { $i=1; foreach ($st in $e.manual.steps) { Write-Host ("    {0}. {1}" -f $i,$st); $i++ } }
    $report += @{s='manual';l=$label;r=$e.manual.reason}; continue
  }
  $hi = ($e.safety.executes_remote_code -or $e.safety.requires_admin)
  if ($hi) {
    Write-Host "[$label] high-risk:"; foreach ($l in (Get-MethodPlan $e)) { Write-Host "    `$ $l" }
    if (-not (Confirm-Step "[$label] proceed?")) { Write-Host "[$label] skipped"; $report += @{s='skip';l=$label;r='declined'}; continue }
  }
  Write-Host "[$label] executing:"; foreach ($l in (Get-MethodPlan $e)) { Write-Host "    `$ $l" }
  $rc = Invoke-Entry $e
  if ($rc -eq 0) { $report += @{s='ok';l=$label;r='installed'} }
  elseif ($rc -eq 3) { Write-Host "[$label] skipped"; $report += @{s='skip';l=$label;r='skipped'} }
  else { Write-Host "[$label] FAILED"; $report += @{s='fail';l=$label;r='error'} }
}

# report
$runDir = if ($env:AGENT_SETUP_HOME) { $env:AGENT_SETUP_HOME } else { Join-Path $HOME '.agent-setup' }
if (-not (Test-Path $runDir)) { New-Item -ItemType Directory -Force -Path $runDir | Out-Null }
$reportFile = Join-Path $runDir 'last-install-report.txt'
$lines = @('================ agent-setup report ================', "OS: $OS")
function Add-Group($key, $head) {
  $g = $report | Where-Object { $_.s -eq $key }
  if (-not $g) { return }
  $script:lines += ''; $script:lines += ("{0} ({1}):" -f $head, $g.Count)
  foreach ($x in $g) { $script:lines += ("  {0,-22} {1}" -f $x.l, $x.r) }
}
Add-Group 'ok' 'OK'; Add-Group 'skip' 'SKIPPED'; Add-Group 'manual' 'MANUAL'; Add-Group 'na' 'N/A'; Add-Group 'fail' 'FAILED'
$lines += '===================================================='
$colors = @{ 'OK'='Green'; 'SKIPPED'='Yellow'; 'MANUAL'='Cyan'; 'N/A'='DarkGray'; 'FAILED'='Red' }
foreach ($l in $lines) {
  $c = 'Gray'; foreach ($k in $colors.Keys) { if ($l -like "$k (*") { $c = $colors[$k] } }
  Write-Host $l -ForegroundColor $c
}
$lines | Set-Content -Path $reportFile
Write-Host "report saved: $reportFile"
if ($report | Where-Object { $_.s -eq 'fail' }) { exit 1 }
