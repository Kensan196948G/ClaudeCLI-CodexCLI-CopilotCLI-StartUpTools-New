# ============================================================
# TokenBudget.psm1 - Token Budget Manager
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.8.0
# Phase 3: Token Budget auto-control
# ============================================================

Set-StrictMode -Version Latest

$script:DefaultStatePath = 'state.json'

$script:Zones = @{
    Green  = @{ Min = 0;  Max = 60;  Label = 'Green';  Status = 'Normal development' }
    Yellow = @{ Min = 60; Max = 75;  Label = 'Yellow'; Status = 'Reduced build activity' }
    Orange = @{ Min = 75; Max = 90;  Label = 'Orange'; Status = 'Monitor priority' }
    Red    = @{ Min = 90; Max = 100; Label = 'Red';    Status = 'Development stopped' }
}

$script:DefaultAllocation = @{
    monitor     = 10
    development = 35
    verify      = 25
    improvement = 10
    debug       = 20
}

function Get-StateFilePath {
    param([string]$RepoRoot)
    if (-not $RepoRoot) {
        $RepoRoot = (git rev-parse --show-toplevel 2>$null)
        if (-not $RepoRoot) { $RepoRoot = '.' }
    }
    return Join-Path $RepoRoot $script:DefaultStatePath
}

function Get-TokenState {
    <#
    .SYNOPSIS
        Reads token budget state from state.json.
    .PARAMETER StatePath
        Path to state.json. Auto-detected if not provided.
    #>
    param([string]$StatePath)

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    if (-not (Test-Path $StatePath)) {
        return New-TokenState
    }

    $state = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not ($state.PSObject.Properties.Name -contains 'token') -or $null -eq $state.token) {
        return New-TokenState
    }

    return $state.token
}

function New-TokenState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function returns in-memory object; no persistent system state is modified')]
    param()
    <#
    .SYNOPSIS
        Creates a fresh token budget state with default allocation.
    #>
    return [pscustomobject]@{
        total_budget         = 100
        used                 = 0
        remaining            = 100
        allocation           = [pscustomobject]$script:DefaultAllocation
        dynamic_mode         = $true
        current_phase_budget = 0
        current_phase_used   = 0
    }
}

function Get-TokenZone {
    <#
    .SYNOPSIS
        Determines the current budget zone based on usage percentage.
    .PARAMETER UsedPercent
        Usage percentage (0-100).
    #>
    param(
        [Parameter(Mandatory)]
        [double]$UsedPercent
    )

    if ($UsedPercent -lt 60) {
        return [pscustomobject]$script:Zones.Green
    }
    elseif ($UsedPercent -lt 75) {
        return [pscustomobject]$script:Zones.Yellow
    }
    elseif ($UsedPercent -lt 90) {
        return [pscustomobject]$script:Zones.Orange
    }
    else {
        return [pscustomobject]$script:Zones.Red
    }
}

function Get-PhaseAllowance {
    <#
    .SYNOPSIS
        Returns which phases are allowed/restricted based on current zone.
    .PARAMETER Zone
        Current budget zone object.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Zone
    )

    $result = [ordered]@{
        monitor     = $true
        development = $true
        verify      = $true
        improvement = $true
        debug       = $true
    }

    switch ($Zone.Label) {
        'Yellow' {
            $result.improvement = $false
        }
        'Orange' {
            $result.improvement = $false
            $result.development = $false
        }
        'Red' {
            $result.improvement = $false
            $result.development = $false
            $result.debug       = $false
        }
    }

    return [pscustomobject]$result
}

function Update-TokenUsage {
    <#
    .SYNOPSIS
        Updates token usage in state.json and returns the new state.
    .PARAMETER Phase
        The phase that consumed tokens.
    .PARAMETER Amount
        Amount of tokens consumed (percentage points).
    .PARAMETER StatePath
        Path to state.json.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal autonomous CLI function; ShouldProcess disrupts unattended operation')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('monitor', 'development', 'verify', 'improvement', 'debug')]
        [string]$Phase,

        [Parameter(Mandatory)]
        [double]$Amount,

        [string]$StatePath
    )

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    $state = $null
    if (Test-Path $StatePath) {
        $state = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        $state = [pscustomobject]@{}
    }

    $hasToken = $false
    try { $hasToken = $null -ne $state.token } catch { $hasToken = $false }
    if (-not $hasToken) {
        $tokenState = New-TokenState
        if ($state -is [hashtable]) {
            $state = [pscustomobject]$state
        }
        $state | Add-Member -NotePropertyName 'token' -NotePropertyValue $tokenState -Force
    }

    $state.token.used = [math]::Min(100, $state.token.used + $Amount)
    $state.token.remaining = [math]::Max(0, $state.token.total_budget - $state.token.used)
    $state.token | Add-Member -NotePropertyName 'current_phase' -NotePropertyValue $Phase -Force
    $state.token.current_phase_used = $state.token.current_phase_used + $Amount

    $json = $state | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($StatePath, $json, [System.Text.UTF8Encoding]::new($false))

    return $state.token
}

function Get-TokenBudgetStatus {
    <#
    .SYNOPSIS
        Returns a comprehensive token budget status report.
    .PARAMETER StatePath
        Path to state.json.
    #>
    param([string]$StatePath)

    $token = Get-TokenState -StatePath $StatePath
    $usedPercent = if ($token.total_budget -gt 0) { ($token.used / $token.total_budget) * 100 } else { 0 }
    $zone = Get-TokenZone -UsedPercent $usedPercent
    $allowance = Get-PhaseAllowance -Zone $zone

    return [pscustomobject]@{
        Used           = $token.used
        Remaining      = $token.remaining
        TotalBudget    = $token.total_budget
        UsedPercent    = [math]::Round($usedPercent, 1)
        Zone           = $zone
        Allowance      = $allowance
        Allocation     = $token.allocation
        DynamicMode    = $token.dynamic_mode
        ShouldStop     = ($zone.Label -eq 'Red')
        ShouldSkipImprovement = ($zone.Label -ne 'Green')
        ShouldVerifyOnly = ($zone.Label -eq 'Orange' -or $zone.Label -eq 'Red')
    }
}

function Invoke-DynamicReallocation {
    <#
    .SYNOPSIS
        Dynamically reallocates phase budgets based on current conditions.
    .PARAMETER Condition
        The condition triggering reallocation: 'ci_failure', 'stable', 'time_pressure'
    .PARAMETER StatePath
        Path to state.json.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ci_failure', 'stable', 'time_pressure')]
        [string]$Condition,

        [string]$StatePath
    )

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    $state = $null
    if (Test-Path $StatePath) {
        $state = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        return $null
    }

    if (-not ($state.PSObject.Properties.Name -contains 'token') -or $null -eq $state.token -or -not $state.token.dynamic_mode) {
        return $null
    }

    $alloc = $state.token.allocation

    switch ($Condition) {
        'ci_failure' {
            # Shift budget from development to verify
            $alloc.verify = [math]::Min(50, $alloc.verify + 20)
            $alloc.development = [math]::Max(15, $alloc.development - 20)
        }
        'stable' {
            # Shift budget from development to improvement
            $alloc.improvement = [math]::Min(20, $alloc.improvement + 10)
            $alloc.development = [math]::Max(25, $alloc.development - 10)
        }
        'time_pressure' {
            # Remove improvement, minimize verify
            $alloc.improvement = 0
            $alloc.verify = [math]::Max(15, $alloc.verify - 10)
            $alloc.development = $alloc.development + 10
        }
    }

    $state.token.allocation = $alloc
    $json = $state | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($StatePath, $json, [System.Text.UTF8Encoding]::new($false))

    return $alloc
}

function Show-TokenBudgetStatus {
    <#
    .SYNOPSIS
        Displays token budget status in formatted output.
    .PARAMETER StatePath
        Path to state.json.
    #>
    param([string]$StatePath)

    $status = Get-TokenBudgetStatus -StatePath $StatePath

    Write-Host "Token Budget Status:" -ForegroundColor Cyan
    Write-Host "  Used: $($status.UsedPercent)% ($($status.Used)/$($status.TotalBudget))"
    Write-Host "  Remaining: $($status.Remaining)"

    $zoneColor = switch ($status.Zone.Label) {
        'Green'  { 'Green' }
        'Yellow' { 'Yellow' }
        'Orange' { 'DarkYellow' }
        'Red'    { 'Red' }
    }
    Write-Host "  Zone: $($status.Zone.Label) - $($status.Zone.Status)" -ForegroundColor $zoneColor

    Write-Host "  Phases:" -ForegroundColor Cyan
    $phases = @('monitor', 'development', 'verify', 'improvement', 'debug')
    foreach ($phase in $phases) {
        $allowed = $status.Allowance.$phase
        $icon = if ($allowed) { '[OK]' } else { '[--]' }
        $color = if ($allowed) { 'Green' } else { 'DarkGray' }
        $budget = $status.Allocation.$phase
        Write-Host "    $icon $phase`: ${budget}%" -ForegroundColor $color
    }
}

Export-ModuleMember -Function @(
    'Get-TokenState'
    'New-TokenState'
    'Get-TokenZone'
    'Get-PhaseAllowance'
    'Update-TokenUsage'
    'Get-TokenBudgetStatus'
    'Invoke-DynamicReallocation'
    'Show-TokenBudgetStatus'
    'Get-StateFilePath'
)
