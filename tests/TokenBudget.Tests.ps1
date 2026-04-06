# ============================================================
# TokenBudget.Tests.ps1 - TokenBudget.psm1 unit tests
# Pester 5.x
# Phase 3: Token Budget auto-control
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\TokenBudget.psm1') -Force
}

Describe 'New-TokenState' {

    It 'creates default state with correct budget' {
        $state = New-TokenState
        $state.total_budget | Should -Be 100
        $state.used | Should -Be 0
        $state.remaining | Should -Be 100
        $state.dynamic_mode | Should -Be $true
    }

    It 'has correct default allocation' {
        $state = New-TokenState
        $state.allocation.monitor | Should -Be 10
        $state.allocation.development | Should -Be 35
        $state.allocation.verify | Should -Be 25
        $state.allocation.improvement | Should -Be 10
        $state.allocation.debug | Should -Be 20
    }
}

Describe 'Get-TokenZone' {

    It 'returns Green for 0%' {
        $zone = Get-TokenZone -UsedPercent 0
        $zone.Label | Should -Be 'Green'
    }

    It 'returns Green for 59%' {
        $zone = Get-TokenZone -UsedPercent 59
        $zone.Label | Should -Be 'Green'
    }

    It 'returns Yellow for 60%' {
        $zone = Get-TokenZone -UsedPercent 60
        $zone.Label | Should -Be 'Yellow'
    }

    It 'returns Yellow for 74%' {
        $zone = Get-TokenZone -UsedPercent 74
        $zone.Label | Should -Be 'Yellow'
    }

    It 'returns Orange for 75%' {
        $zone = Get-TokenZone -UsedPercent 75
        $zone.Label | Should -Be 'Orange'
    }

    It 'returns Orange for 89%' {
        $zone = Get-TokenZone -UsedPercent 89
        $zone.Label | Should -Be 'Orange'
    }

    It 'returns Red for 90%' {
        $zone = Get-TokenZone -UsedPercent 90
        $zone.Label | Should -Be 'Red'
    }

    It 'returns Red for 100%' {
        $zone = Get-TokenZone -UsedPercent 100
        $zone.Label | Should -Be 'Red'
    }
}

Describe 'Get-PhaseAllowance' {

    It 'allows all phases in Green zone' {
        $zone = Get-TokenZone -UsedPercent 30
        $allowance = Get-PhaseAllowance -Zone $zone
        $allowance.monitor | Should -Be $true
        $allowance.development | Should -Be $true
        $allowance.verify | Should -Be $true
        $allowance.improvement | Should -Be $true
        $allowance.debug | Should -Be $true
    }

    It 'disables improvement in Yellow zone' {
        $zone = Get-TokenZone -UsedPercent 65
        $allowance = Get-PhaseAllowance -Zone $zone
        $allowance.improvement | Should -Be $false
        $allowance.development | Should -Be $true
        $allowance.verify | Should -Be $true
    }

    It 'disables development and improvement in Orange zone' {
        $zone = Get-TokenZone -UsedPercent 80
        $allowance = Get-PhaseAllowance -Zone $zone
        $allowance.improvement | Should -Be $false
        $allowance.development | Should -Be $false
        $allowance.verify | Should -Be $true
        $allowance.monitor | Should -Be $true
    }

    It 'only allows monitor and verify in Red zone' {
        $zone = Get-TokenZone -UsedPercent 95
        $allowance = Get-PhaseAllowance -Zone $zone
        $allowance.improvement | Should -Be $false
        $allowance.development | Should -Be $false
        $allowance.debug | Should -Be $false
        $allowance.monitor | Should -Be $true
        $allowance.verify | Should -Be $true
    }
}

Describe 'Get-TokenState' {

    It 'returns default state when file does not exist' {
        $state = Get-TokenState -StatePath (Join-Path $TestDrive 'nonexistent.json')
        $state.total_budget | Should -Be 100
        $state.used | Should -Be 0
    }

    It 'reads token state from state.json' {
        $statePath = Join-Path $TestDrive 'state-read.json'
        $data = @{
            token = @{
                total_budget = 100
                used = 45
                remaining = 55
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true
                current_phase_budget = 35
                current_phase_used = 12
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $state = Get-TokenState -StatePath $statePath
        $state.used | Should -Be 45
        $state.remaining | Should -Be 55
    }
}

Describe 'Update-TokenUsage' {

    BeforeAll {
        $script:TestState = Join-Path $TestDrive 'state-update.json'
        $data = @{
            token = @{
                total_budget = 100
                used = 30
                remaining = 70
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true
                current_phase_budget = 35
                current_phase_used = 5
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $script:TestState -Value $data -Encoding UTF8
    }

    It 'increments usage correctly' {
        $result = Update-TokenUsage -Phase 'development' -Amount 10 -StatePath $script:TestState
        $result.used | Should -Be 40
        $result.remaining | Should -Be 60
    }

    It 'caps usage at 100' {
        $statePath = Join-Path $TestDrive 'state-cap.json'
        $data = @{
            token = @{
                total_budget = 100; used = 95; remaining = 5
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true; current_phase_budget = 0; current_phase_used = 0
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $result = Update-TokenUsage -Phase 'verify' -Amount 20 -StatePath $statePath
        $result.used | Should -Be 100
        $result.remaining | Should -Be 0
    }

    It 'creates token state if missing in state.json' {
        $statePath = Join-Path $TestDrive 'state-empty.json'
        Set-Content -Path $statePath -Value '{}' -Encoding UTF8

        $result = Update-TokenUsage -Phase 'monitor' -Amount 5 -StatePath $statePath
        $result.used | Should -Be 5
        $result.remaining | Should -Be 95
    }
}

Describe 'Get-TokenBudgetStatus' {

    It 'returns comprehensive status for Green zone' {
        $statePath = Join-Path $TestDrive 'state-status.json'
        $data = @{
            token = @{
                total_budget = 100; used = 25; remaining = 75
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true; current_phase_budget = 0; current_phase_used = 0
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $status = Get-TokenBudgetStatus -StatePath $statePath
        $status.UsedPercent | Should -Be 25
        $status.Zone.Label | Should -Be 'Green'
        $status.ShouldStop | Should -Be $false
        $status.ShouldSkipImprovement | Should -Be $false
        $status.ShouldVerifyOnly | Should -Be $false
    }

    It 'flags ShouldStop in Red zone' {
        $statePath = Join-Path $TestDrive 'state-red.json'
        $data = @{
            token = @{
                total_budget = 100; used = 95; remaining = 5
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true; current_phase_budget = 0; current_phase_used = 0
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $status = Get-TokenBudgetStatus -StatePath $statePath
        $status.Zone.Label | Should -Be 'Red'
        $status.ShouldStop | Should -Be $true
        $status.ShouldVerifyOnly | Should -Be $true
    }
}

Describe 'Invoke-DynamicReallocation' {

    It 'shifts budget on ci_failure' {
        $statePath = Join-Path $TestDrive 'state-realloc-ci.json'
        $data = @{
            token = @{
                total_budget = 100; used = 40; remaining = 60
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true; current_phase_budget = 0; current_phase_used = 0
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $alloc = Invoke-DynamicReallocation -Condition 'ci_failure' -StatePath $statePath
        $alloc.verify | Should -Be 45
        $alloc.development | Should -Be 15
    }

    It 'shifts budget on stable' {
        $statePath = Join-Path $TestDrive 'state-realloc-stable.json'
        $data = @{
            token = @{
                total_budget = 100; used = 40; remaining = 60
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true; current_phase_budget = 0; current_phase_used = 0
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $alloc = Invoke-DynamicReallocation -Condition 'stable' -StatePath $statePath
        $alloc.improvement | Should -Be 20
        $alloc.development | Should -Be 25
    }

    It 'removes improvement on time_pressure' {
        $statePath = Join-Path $TestDrive 'state-realloc-time.json'
        $data = @{
            token = @{
                total_budget = 100; used = 80; remaining = 20
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $true; current_phase_budget = 0; current_phase_used = 0
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $alloc = Invoke-DynamicReallocation -Condition 'time_pressure' -StatePath $statePath
        $alloc.improvement | Should -Be 0
        $alloc.development | Should -Be 45
        $alloc.verify | Should -Be 15
    }

    It 'returns null when dynamic_mode is false' {
        $statePath = Join-Path $TestDrive 'state-realloc-off.json'
        $data = @{
            token = @{
                total_budget = 100; used = 40; remaining = 60
                allocation = @{ monitor = 10; development = 35; verify = 25; improvement = 10; debug = 20 }
                dynamic_mode = $false; current_phase_budget = 0; current_phase_used = 0
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path $statePath -Value $data -Encoding UTF8

        $result = Invoke-DynamicReallocation -Condition 'stable' -StatePath $statePath
        $result | Should -BeNullOrEmpty
    }
}
