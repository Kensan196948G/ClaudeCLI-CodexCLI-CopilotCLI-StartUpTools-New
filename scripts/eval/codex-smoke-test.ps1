#Requires -Version 7.0
<#
.SYNOPSIS
  Codex Plugin smoke-test harness for ClaudeOS Evaluation Methodology §9.

.DESCRIPTION
  Attempts to invoke codex-companion.mjs setup and probes availability of
  /codex:* slash commands referenced by CLAUDE.md. Writes a machine-readable
  JSON artifact and a human-readable summary.

.OUTPUTS
  .claude/claudeos/system/codex-availability.json
#>

param(
    [string]$OutputPath = ".claude/claudeos/system/codex-availability.json"
)

$ErrorActionPreference = 'Continue'

function Get-IsoLocal {
    (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
}

$result = [ordered]@{
    schema_version = "1.0"
    timestamp      = Get-IsoLocal
    host           = [System.Net.Dns]::GetHostName()
    checks         = [ordered]@{}
    overall        = "unknown"
    notes          = @()
}

# Check 1: codex-companion.mjs setup
$companion = "$env:USERPROFILE/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/codex-companion.mjs"
if (Test-Path $companion) {
    try {
        $json = node $companion setup --json 2>$null
        $parsed = $json | ConvertFrom-Json
        $result.checks["companion_setup"] = [ordered]@{
            status        = "ok"
            ready         = $parsed.ready
            node_version  = $parsed.node.detail
            codex_version = $parsed.codex.detail
            authenticated = $parsed.auth.loggedIn
        }
    } catch {
        $result.checks["companion_setup"] = [ordered]@{
            status = "error"
            error  = $_.Exception.Message
        }
    }
} else {
    $result.checks["companion_setup"] = [ordered]@{
        status = "missing"
        path   = $companion
    }
}

# Check 2: slash commands probe (via skills directory heuristic)
$skillsDir = "$env:USERPROFILE/.claude/plugins/cache/openai-codex/codex/1.0.2"
$expectedCommands = @("review", "rescue", "adversarial-review", "status", "result", "setup")
$commandAvailability = [ordered]@{}

foreach ($cmd in $expectedCommands) {
    $found = $false
    if (Test-Path $skillsDir) {
        $matches = Get-ChildItem -Path $skillsDir -Recurse -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match "codex.*$cmd" -or $_.Name -match "$cmd\.md" }
        $found = ($matches.Count -gt 0)
    }
    $commandAvailability[$cmd] = if ($found) { "available" } else { "not_detected" }
}
$result.checks["slash_commands"] = $commandAvailability

# Check 3: relevant skills list
$skillToolAvailable = $null -ne (Get-Command codex -ErrorAction SilentlyContinue)
$result.checks["codex_cli_in_path"] = if ($skillToolAvailable) { "yes" } else { "no" }

# Overall verdict
$companionOk = ($result.checks["companion_setup"].status -eq "ok" -and $result.checks["companion_setup"].ready -eq $true)
$someCommandsMissing = ($commandAvailability.Values | Where-Object { $_ -eq "not_detected" }).Count -gt 0

if ($companionOk -and -not $someCommandsMissing) {
    $result.overall = "fully_available"
} elseif ($companionOk -and $someCommandsMissing) {
    $result.overall = "partial"
    $result.notes += "codex-companion ready but some slash commands not detected in skill registry."
} else {
    $result.overall = "unavailable"
}

# Write output
$dir = Split-Path $OutputPath -Parent
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
$result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "[codex-smoke-test] overall=$($result.overall)"
Write-Host "[codex-smoke-test] written: $OutputPath"

if ($result.overall -eq "unavailable") { exit 2 }
if ($result.overall -eq "partial") { exit 1 }
exit 0
