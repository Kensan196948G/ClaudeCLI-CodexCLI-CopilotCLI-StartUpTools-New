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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DryRun', Justification = 'Planned for Boot Sequence Phase 3 implementation')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NonInteractive', Justification = 'Planned for Boot Sequence Phase 3 implementation')]
param(
    [switch]$DryRun,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force
Import-Module (Join-Path $ScriptRoot 'scripts\lib\AgentTeams.psm1') -Force
Import-Module (Join-Path $ScriptRoot 'scripts\lib\McpHealthCheck.psm1') -Force

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

function Invoke-StepMemoryRestore {
    param([string]$Root)
    Write-BootStep 3 'Memory Restore'
    try {
        $report = Get-McpHealthReport -ProjectRoot $Root
        if (-not $report.configured) {
            Write-Host '  [SKIP] .mcp.json not found' -ForegroundColor DarkGray
            Write-Host ''
            return @{ Step = 3; Name = 'Memory Restore'; Status = 'SKIP'; Detail = 'no mcp config' }
        }

        $memoryConn = @($report.connections | Where-Object { $_.kind -eq 'memory' }) | Select-Object -First 1
        if (-not $memoryConn) {
            Write-Host '  [SKIP] memory server not configured in .mcp.json' -ForegroundColor DarkGray
            Write-Host ''
            return @{ Step = 3; Name = 'Memory Restore'; Status = 'SKIP'; Detail = 'no memory server' }
        }

        $filePath = $env:CLAUDE_MEMORY_FILE_PATH
        $entryCount = 0
        if ($filePath -and (Test-Path $filePath)) {
            try {
                $data = Get-Content $filePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                $entryCount = if ($data.entities) { @($data.entities).Count } else { 0 }
            }
            catch { $entryCount = 0 }
        }

        $fileLabel = if ($filePath -and (Test-Path $filePath)) {
            'found ({0} entries)' -f $entryCount
        }
        elseif ($filePath) {
            'configured (file not yet created)'
        }
        else {
            'CLAUDE_MEMORY_FILE_PATH not set'
        }
        Write-Host ('  [OK] Memory MCP : configured' ) -ForegroundColor Green
        Write-Host ('  Memory file      : {0}' -f $fileLabel) -ForegroundColor Cyan
        Write-Host ''
        return @{
            Step   = 3
            Name   = 'Memory Restore'
            Status = 'OK'
            Detail = @{ entryCount = $entryCount; filePath = $filePath; configured = $true }
        }
    }
    catch {
        Write-Host ('  [FAIL] Memory Restore: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return @{ Step = 3; Name = 'Memory Restore'; Status = 'FAIL'; Detail = $_.Exception.Message }
    }
}

function Invoke-StepPlaceholder {
    param([int]$Number, [string]$Name, [string]$Reason)
    Write-BootStep -Number $Number -Name $Name -Status 'SKIP'
    Write-Host ('  [SKIP] {0}' -f $Reason) -ForegroundColor DarkGray
    Write-Host ''
    return @{ Step = $Number; Name = $Name; Status = 'SKIP'; Detail = $Reason }
}

function Invoke-StepAgentInit {
    param([string]$Root)
    Write-BootStep 7 'Agent Init'
    try {
        $report = Get-AgentTeamReport -ProjectRoot $Root
        if ($report.agentsDirExists) {
            Write-Host ('  [OK] Agent definitions: {0} agents loaded' -f $report.agentCount) -ForegroundColor Green
            Write-Host ('       Path: {0}' -f $report.agentsDir) -ForegroundColor DarkGray
        }
        else {
            Write-Host ('  [WARN] Agent definitions directory not found: {0}' -f $report.agentsDir) -ForegroundColor Yellow
        }
        $rulesLabel = if ($report.rulesExist) { '[OK] found' } else { '[WARN] not found' }
        $rulesColor = if ($report.rulesExist) { 'Green' } else { 'Yellow' }
        Write-Host ('  Backlog rules : {0}' -f $rulesLabel) -ForegroundColor $rulesColor
        Write-Host ''
        $stepStatus = if ($report.agentsDirExists) { 'OK' } else { 'SKIP' }
        return @{ Step = 7; Name = 'Agent Init'; Status = $stepStatus; Detail = $report }
    }
    catch {
        Write-Host ('  [FAIL] Agent Init failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        return @{ Step = 7; Name = 'Agent Init'; Status = 'FAIL'; Detail = $_.Exception.Message }
    }
}

function Get-StateJsonDashboard {
    param([string]$Root)
    $statePath = Join-Path $Root 'state.json'
    if (-not (Test-Path $statePath)) {
        return $null
    }
    try {
        return Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-BootDashboard {
    param(
        [array]$Results,
        [string]$Root
    )
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

    # state.json integration (Issue #71)
    $state = if ($Root) { Get-StateJsonDashboard -Root $Root } else { $null }
    if ($state) {
        try {
            $stateProps = $state.PSObject.Properties.Name

            Write-Host '  ── Goal & KPI ──────────────────────────────' -ForegroundColor Magenta
            if (($stateProps -contains 'goal') -and $state.goal -and $state.goal.title) {
                Write-Host ('    Goal  : {0}' -f $state.goal.title) -ForegroundColor White
            }
            if (($stateProps -contains 'kpi') -and $state.kpi) {
                $kpi        = $state.kpi
                $kpiProps   = $kpi.PSObject.Properties.Name
                $successTarget = if ($kpiProps -contains 'success_rate_target') { '{0:P0}' -f $kpi.success_rate_target } else { 'n/a' }
                $ciTarget      = if ($kpiProps -contains 'ci_pass_rate')        { '{0:P0}' -f $kpi.ci_pass_rate }        else { 'n/a' }
                $openP1        = if ($kpiProps -contains 'open_p1_issues')      { $kpi.open_p1_issues }                  else { 'n/a' }
                Write-Host ("    KPI   : success>={0}  CI>={1}  P1-issues={2}" -f $successTarget, $ciTarget, $openP1) -ForegroundColor Cyan
            }

            if (($stateProps -contains 'execution') -and $state.execution) {
                $exec       = $state.execution
                $execProps  = $exec.PSObject.Properties.Name
                $phase     = if ($execProps -contains 'phase')              { $exec.phase }              else { 'unknown' }
                $remaining = if ($execProps -contains 'remaining_minutes')  { "$($exec.remaining_minutes)min" } else { 'n/a' }
                $elapsed   = if ($execProps -contains 'elapsed_minutes')    { "$($exec.elapsed_minutes)min" }   else { 'n/a' }
                Write-Host ''
                Write-Host '  ── Execution Status ────────────────────────' -ForegroundColor Magenta
                Write-Host ("    Phase     : {0}" -f $phase)     -ForegroundColor White
                Write-Host ("    Elapsed   : {0} / Remaining: {1}" -f $elapsed, $remaining) -ForegroundColor White
            }

            if (($stateProps -contains 'token') -and $state.token) {
                $tok       = $state.token
                $tokProps  = $tok.PSObject.Properties.Name
                $used      = if ($tokProps -contains 'used')         { $tok.used }         else { '?' }
                $remaining = if ($tokProps -contains 'remaining')    { $tok.remaining }    else { '?' }
                $total     = if ($tokProps -contains 'total_budget') { $tok.total_budget } else { '?' }
                Write-Host ''
                Write-Host '  ── Token Budget ────────────────────────────' -ForegroundColor Magenta
                Write-Host ("    Used/Total: {0}/{1}  Remaining: {2}%" -f $used, $total, $remaining) -ForegroundColor White
            }

            if (($stateProps -contains 'current_work') -and $state.current_work) {
                $work      = $state.current_work
                $workProps = $work.PSObject.Properties.Name
                Write-Host ''
                Write-Host '  ── Current Work ────────────────────────────' -ForegroundColor Magenta
                if ($workProps -contains 'issue') {
                    $issueTitle = if ($workProps -contains 'title') { $work.title } else { '' }
                    Write-Host ("    Issue #{0}: {1}" -f $work.issue, $issueTitle) -ForegroundColor White
                }
                if ($workProps -contains 'pr') {
                    $branch = if ($workProps -contains 'branch') { $work.branch } else { '' }
                    Write-Host ("    PR    #{0} [{1}]" -f $work.pr, $branch) -ForegroundColor Cyan
                }
            }

            if (($stateProps -contains 'loop_history') -and $state.loop_history -and @($state.loop_history).Count -gt 0) {
                $lastLoop      = @($state.loop_history)[-1]
                $loopProps     = $lastLoop.PSObject.Properties.Name
                $loopNum       = if ($loopProps -contains 'loop')    { $lastLoop.loop }    else { '?' }
                $loopPhase     = if ($loopProps -contains 'phase')   { $lastLoop.phase }   else { '?' }
                $loopOutcome   = if ($loopProps -contains 'outcome') { $lastLoop.outcome } else { '' }
                Write-Host ''
                Write-Host '  ── Last Loop ───────────────────────────────' -ForegroundColor Magenta
                Write-Host ("    Loop {0} [{1}]: {2}" -f $loopNum, $loopPhase, $loopOutcome) -ForegroundColor DarkGray
            }
            Write-Host ''
        }
        catch {
            Write-Host ('  [WARN] Dashboard state.json read error: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
            Write-Host ''
        }
    }

    return @{ OK = $ok; SKIP = $skip; FAIL = $fail }
}

# ============================================================
# Main boot flow
# ============================================================

Write-BootBanner

$results = @()
$results += Invoke-StepEnvironmentCheck
$results += Invoke-StepProjectDetection -Root $ScriptRoot
$results += Invoke-StepMemoryRestore -Root $ScriptRoot
$results += Invoke-StepSystemInit
$results += Invoke-StepPlaceholder -Number 5 -Name 'Executive Init' `
    -Reason 'Runtime CTO / Strategy Engine is a conceptual layer (Claude itself)'
$results += Invoke-StepPlaceholder -Number 6 -Name 'Management Init' `
    -Reason 'Backlog / Scrum Master integration pending'
$results += Invoke-StepAgentInit -Root $ScriptRoot
$results += Invoke-StepPlaceholder -Number 8 -Name 'Loop Engine Start' `
    -Reason 'Loop orchestration handled by Claude Code /loop harness'

$summary = Write-BootDashboard -Results $results -Root $ScriptRoot

if ($summary.FAIL -gt 0) {
    Write-Host 'Boot sequence completed with errors.' -ForegroundColor Red
    exit 1
}

Write-Host 'Boot sequence completed successfully.' -ForegroundColor Green
exit 0
