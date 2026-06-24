#!/usr/bin/env pwsh
# bootstrap.ps1 — one-line installer for agent-setup (native Windows).
#   irm https://raw.githubusercontent.com/host452b/agent-setup/main/bootstrap.ps1 | iex
# To pass installer flags, download then run:
#   irm .../bootstrap.ps1 -OutFile bootstrap.ps1; ./bootstrap.ps1 -DryRun
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)] $Rest)

$ErrorActionPreference = 'Stop'

$slug   = if ($env:AGENT_SETUP_REPO_SLUG) { $env:AGENT_SETUP_REPO_SLUG } else { 'host452b/agent-setup' }
$branch = if ($env:AGENT_SETUP_BRANCH)    { $env:AGENT_SETUP_BRANCH }    else { 'main' }
$cache  = if ($env:AGENT_SETUP_HOME)      { $env:AGENT_SETUP_HOME }      else { Join-Path $HOME '.agent-setup' }

function Test-Cmd($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }

Write-Host "agent-setup: fetching $slug@$branch -> $cache"
if (Test-Cmd git) {
  if (Test-Path (Join-Path $cache '.git')) {
    git -C $cache pull --ff-only --quiet
  } else {
    if (Test-Path $cache) { Remove-Item -Recurse -Force $cache }
    git clone --depth 1 --branch $branch "https://github.com/$slug.git" $cache --quiet
  }
} else {
  # no git: download the branch zip and extract (download-then-extract, not pipe-to-shell)
  $zip = "https://github.com/$slug/archive/refs/heads/$branch.zip"
  $tmp = [System.IO.Path]::GetTempFileName()
  Invoke-WebRequest -Uri $zip -OutFile $tmp
  if (Test-Path $cache) { Remove-Item -Recurse -Force $cache }
  $extract = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-setup-" + [guid]::NewGuid())
  Expand-Archive -Path $tmp -DestinationPath $extract -Force
  $inner = Get-ChildItem $extract | Select-Object -First 1
  Move-Item $inner.FullName $cache
  Remove-Item -Recurse -Force $extract; Remove-Item $tmp
}

$installer = Join-Path $cache 'install.ps1'
if (-not (Test-Path $installer)) {
  Write-Error "agent-setup: install.ps1 not found in fetched repo (is the Windows driver on $branch?)"
  exit 1
}
& $installer @Rest
