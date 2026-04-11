<#
.SYNOPSIS
    ClaudeOS Boot Sequence entry point (MVP scaffold).

.DESCRIPTION
    Implements the 9-step ClaudeOS Boot Sequence specified in
    .claude/claudeos/system/boot.md. This MVP scaffold executes
    steps 1 (Environment Check), 2 (Project Detection), 4 (System
    Init), and 9 (Dashboard). Steps 3, 5, 6, 7, 8 are placeholders
    that emit SKIP status until their dependencies land.

    Related Issue: #68 (Phase 3: Boot Sequence 完全自動化)

.PARAMETER DryRun
    Report what would be done without applying any side effects.

.PARAMETER NonInteractive
    Suppress all interactive prompts. Intended for CI / automated runs.

.EXAMPLE
    .\Start-ClaudeOS.ps1
    Run the full boot sequence with default settings.

.EXAMPLE
    .\Start-ClaudeOS.ps1 -DryRun
    Preview the boot sequence without side effects.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force

function Write-BootStep {
    param(
        [int]$Number,
        [string]$Name,
        [ValidateSet('RUN', 'OK', 'SKIP', 'FAIL')]
        [string]$Status = 'RUN'
    )
    $color = switch ($Status) {
        'OK'   { 'Green' }
        'SKIP' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host ('[Step {0}] {1,-28} [{2}]' -f $Number, $Name, $Status) -ForegroundColor $color
}

function Write-BootBanner {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host '          ClaudeOS Boot Sequence v1.0 (MVP)'                   -ForegroundColor Magenta
    Write-Host '   Claude Code Autonomous Development System Entry Point'     -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host ''
    if ($DryRun) {
        Write-Host '[DRY RUN] No side effects will be applied.' -ForegroundColor Yellow
        Write-Host ''
    }
}

function Invoke-StepEnvironmentCheck {
    Write-BootStep 1 'Environment Check'
    $required = @('git', 'node', 'pwsh')
    $status = @{}
    $missing = @()
    foreach ($tool in $required) {
        $available = [bool](Get-Command $tool -ErrorAction SilentlyContinue)
        $status[$tool] = $available
        if (-not $available) { $missing += $tool }
        $mark = if ($available) { '[OK]' } else { '[NG]' }
        $color = if ($available) { 'Green' } else { 'Red' }
        Write-Host ('  {0} {1}' -f $mark, $tool) -ForegroundColor $color
    }
    Write-Host ''
    $stepStatus = if ($missing.Count -eq 0) { 'OK' } else { 'FAIL' }
    $detail = if ($missing.Count -eq 0) {
        $status
    } else {
        @{ Tools = $status; Missing = $missing }
    }
    return @{ Step = 1; Name = 'Environment Check'; Status = $stepStatus; Detail = $detail }
}

function Invoke-StepProjectDetection {
    param([string]$Root)
    Write-BootStep 2 'Project Detection'
    $claudeMdPath = Join-Path $Root 'CLAUDE.md'
    $hasClaudeMd  = Test-Path $claudeMdPath
    $configPath   = Get-StartupConfigPath -StartupRoot $Root
    $hasConfig    = Test-Path $configPath

    $claudeLabel = if ($hasClaudeMd) { '[OK] found' } else { '[NG] missing' }
    $configLabel = if ($hasConfig)   { '[OK] found' } else { '[NG] missing (using template)' }
    $claudeColor = if ($hasClaudeMd) { 'Green' } else { 'Yellow' }
    $configColor = if ($hasConfig)   { 'Green' } else { 'Yellow' }

    Write-Host ('  CLAUDE.md        : {0}' -f $claudeLabel) -ForegroundColor $claudeColor
    Write-Host ('  config.json      : {0}' -f $configLabel) -ForegroundColor $configColor
    Write-Host ''
    return @{
        Step = 2; Name = 'Project Detection'; Status = 'OK'
        Detail = @{ ClaudeMd = $hasClaudeMd; Config = $hasConfig }
    }
}

function Invoke-StepSystemInit {
    Write-BootStep 4 'System Init'
    try {
        $token = Get-LauncherTokenBudgetStatus
        $zone    = if ($null -ne $token.Zone)    { $token.Zone }    else { 'unknown' }
        $percent = if ($null -ne $token.Percent) { "$($token.Percent)%" } else { 'n/a' }
        $state   = if ($null -ne $token.Status)  { $token.Status }  else { 'n/a' }
        Write-Host ('  Token Budget     : zone={0} percent={1} status={2}' -f $zone, $percent, $state) -ForegroundColor Cyan
        Write-Host ''
        return @{ Step = 4; Name = 'System Init'; Status = 'OK'; Detail = $token }
    }
    catch {
        Write-Host ('  [FAIL] System Init failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return @{ Step = 4; Name = 'System Init'; Status = 'FAIL'; Detail = $_.Exception.Message }
    }
}

function Invoke-StepPlaceholder {
    param([int]$Number, [string]$Name, [string]$Reason)
    Write-BootStep $Number $Name 'SKIP'
    Write-Host ('  [SKIP] {0}' -f $Reason) -ForegroundColor DarkGray
    Write-Host ''
    return @{ Step = $Number; Name = $Name; Status = 'SKIP'; Detail = $Reason }
}

function Invoke-StepAgentInit {
    param([string]$Root)
    Write-BootStep 7 'Agent Init'
    try {
        $agentsDir = Join-Path $Root '.claude\claudeos\agents'
        if (-not (Test-Path $agentsDir)) {
            Write-Host ('  [SKIP] Agents directory not found: {0}' -f $agentsDir) -ForegroundColor Yellow
            Write-Host ''
            return @{ Step = 7; Name = 'Agent Init'; Status = 'SKIP'; Detail = 'agents directory missing' }
        }

        $agentTeamsModule = Join-Path $Root 'scripts\lib\AgentTeams.psm1'
        if (-not (Test-Path $agentTeamsModule)) {
            Write-Host ('  [SKIP] AgentTeams.psm1 not found: {0}' -f $agentTeamsModule) -ForegroundColor Yellow
            Write-Host ''
            return @{ Step = 7; Name = 'Agent Init'; Status = 'SKIP'; Detail = 'AgentTeams module missing' }
        }

        Import-Module $agentTeamsModule -Force -DisableNameChecking -Global

        $agents = @(Import-AgentDefinitions -AgentsDir $agentsDir)
        $count = $agents.Count

        if ($count -eq 0) {
            Write-Host '  [FAIL] No agents loaded' -ForegroundColor Red
            Write-Host ''
            return @{ Step = 7; Name = 'Agent Init'; Status = 'FAIL'; Detail = 'zero agents loaded' }
        }

        Write-Host ('  Agents Loaded    : {0}' -f $count) -ForegroundColor Green
        $sample = @($agents | Select-Object -First 5 | ForEach-Object { $_.id })
        Write-Host ('  Sample           : {0}' -f ($sample -join ', ')) -ForegroundColor DarkGray
        if ($count -gt 5) {
            Write-Host ('  ... and {0} more agents' -f ($count - 5)) -ForegroundColor DarkGray
        }
        Write-Host ''

        return @{
            Step = 7
            Name = 'Agent Init'
            Status = 'OK'
            Detail = @{
                Count  = $count
                Sample = $sample
            }
        }
    }
    catch {
        Write-Host ('  [FAIL] Agent Init failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return @{ Step = 7; Name = 'Agent Init'; Status = 'FAIL'; Detail = $_.Exception.Message }
    }
}

function Write-BootDashboard {
    param([array]$Results)
    Write-BootStep 9 'Dashboard'
    $ok   = @($Results | Where-Object { $_.Status -eq 'OK'   }).Count
    $skip = @($Results | Where-Object { $_.Status -eq 'SKIP' }).Count
    $fail = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
    Write-Host ''
    Write-Host '  Boot Summary:' -ForegroundColor White
    Write-Host ('    OK   : {0}' -f $ok)   -ForegroundColor Green
    Write-Host ('    SKIP : {0}' -f $skip) -ForegroundColor Yellow
    Write-Host ('    FAIL : {0}' -f $fail) -ForegroundColor Red
    Write-Host ''
    return @{ OK = $ok; SKIP = $skip; FAIL = $fail }
}

# ============================================================
# Main boot flow
# ============================================================

Write-BootBanner

$results = @()
$results += Invoke-StepEnvironmentCheck
$results += Invoke-StepProjectDetection -Root $ScriptRoot
$results += Invoke-StepPlaceholder -Number 3 -Name 'Memory Restore' `
    -Reason 'Memory MCP persistence not yet integrated'
$results += Invoke-StepSystemInit
$results += Invoke-StepPlaceholder -Number 5 -Name 'Executive Init' `
    -Reason 'Runtime CTO / Strategy Engine is a conceptual layer (Claude itself)'
$results += Invoke-StepPlaceholder -Number 6 -Name 'Management Init' `
    -Reason 'Backlog / Scrum Master integration pending'
$results += Invoke-StepAgentInit -Root $ScriptRoot
$results += Invoke-StepPlaceholder -Number 8 -Name 'Loop Engine Start' `
    -Reason 'Loop orchestration handled by Claude Code /loop harness'

$summary = Write-BootDashboard -Results $results

if ($summary.FAIL -gt 0) {
    Write-Host 'Boot sequence completed with errors.' -ForegroundColor Red
    exit 1
}

Write-Host 'Boot sequence completed successfully.' -ForegroundColor Green
exit 0
