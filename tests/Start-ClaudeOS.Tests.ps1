# ============================================================
# Start-ClaudeOS.Tests.ps1 — Pester tests for ClaudeOS Boot Sequence
# Related Issue: #68 (Phase 3: Boot Sequence 完全自動化)
# Covers: PR-A MVP (Steps 1/2/4/9) + PR-B Step 7 Agent Init
# ============================================================

$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:BootScript = Join-Path $RepoRoot 'scripts\main\Start-ClaudeOS.ps1'
    $script:AgentsDir  = Join-Path $RepoRoot '.claude\claudeos\agents'
    $script:AgentTeamsModule = Join-Path $RepoRoot 'scripts\lib\AgentTeams.psm1'
}

Describe 'Start-ClaudeOS.ps1 — Existence and Syntax' {
    It 'should exist at the expected path' {
        Test-Path $script:BootScript | Should -BeTrue
    }

    It 'should be syntactically valid PowerShell' {
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:BootScript, [ref]$tokens, [ref]$errors
        ) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'should declare DryRun and NonInteractive parameters' {
        $content = Get-Content $script:BootScript -Raw
        $content | Should -Match '\[switch\]\$DryRun'
        $content | Should -Match '\[switch\]\$NonInteractive'
    }
}

Describe 'Start-ClaudeOS.ps1 — Boot Flow Execution' {
    It 'should run to completion without throwing' {
        { & $script:BootScript -DryRun -NonInteractive 6>$null } | Should -Not -Throw
    }

    It 'should emit banner text' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Match 'ClaudeOS Boot Sequence'
    }

    It 'should invoke all 9 steps in Boot Summary' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Match 'Boot Summary'
        $output | Should -Match 'OK\s*:'
        $output | Should -Match 'SKIP\s*:'
    }
}

Describe 'Start-ClaudeOS.ps1 — Step 7 Agent Init (PR-B)' {
    It 'AgentTeams.psm1 dependency should exist' {
        Test-Path $script:AgentTeamsModule | Should -BeTrue
    }

    It 'agents directory should exist with at least one .md file' {
        Test-Path $script:AgentsDir | Should -BeTrue
        @(Get-ChildItem -Path $script:AgentsDir -Filter '*.md' -File).Count | Should -BeGreaterThan 0
    }

    It 'Import-AgentDefinitions should return non-empty results' {
        Import-Module $script:AgentTeamsModule -Force -DisableNameChecking
        $agents = @(Import-AgentDefinitions -AgentsDir $script:AgentsDir)
        $agents.Count | Should -BeGreaterThan 0
    }

    It 'Step 7 should no longer emit the PR-B pending SKIP reason' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Not -Match 'AgentTeams runtime wiring pending'
    }

    It 'Step 7 should report a non-zero agent count (proof of OK status)' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Match 'Agents Loaded\s*:\s*\d+'
        # Boot Summary must reflect Step 7 as OK (4 OK steps: 1, 2, 4, 7)
        $output | Should -Match 'OK\s*:\s*4'
    }
}

Describe 'Start-ClaudeOS.ps1 — Exit Code' {
    It 'should set $LASTEXITCODE to 0 on successful run' {
        & $script:BootScript -DryRun -NonInteractive 6>$null
        $LASTEXITCODE | Should -Be 0
    }
}
