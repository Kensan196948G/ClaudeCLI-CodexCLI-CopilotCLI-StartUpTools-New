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

    # Fixture: ensure .claude/session-anchor.json exists for Step 8 Loop Engine
    # probe. CI has no running Claude Code session and session-anchor.json is
    # gitignored, so create a synthetic anchor and clean it up in AfterAll.
    $script:AnchorPath = Join-Path $script:RepoRoot '.claude\session-anchor.json'
    $script:AnchorWasMissing = -not (Test-Path $script:AnchorPath)
    if ($script:AnchorWasMissing) {
        $anchorDir = Split-Path $script:AnchorPath -Parent
        if (-not (Test-Path $anchorDir)) {
            New-Item -ItemType Directory -Path $anchorDir -Force | Out-Null
        }
        $fixtureContent = @{
            session_id          = 'pester-fixture'
            source              = 'Pester-BeforeAll'
            wall_clock_start    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
            wall_clock_deadline = (Get-Date).AddHours(5).ToString('yyyy-MM-ddTHH:mm:sszzz')
            max_duration_minutes = 300
        } | ConvertTo-Json
        Set-Content -Path $script:AnchorPath -Value $fixtureContent -Encoding UTF8
    }
}

AfterAll {
    # Clean up fixture anchor only if BeforeAll created it
    if ($script:AnchorWasMissing -and (Test-Path $script:AnchorPath)) {
        Remove-Item $script:AnchorPath -Force -ErrorAction SilentlyContinue
    }
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
        # After PR-B + PR-C + PR-D, Boot Summary reflects 8 OK steps: 1, 2, 3, 4, 6, 7, 8, 9
        $output | Should -Match 'OK\s*:\s*8'
    }
}

Describe 'Start-ClaudeOS.ps1 — Step 6 Management Init (PR-D)' {
    It 'IssueSyncManager.psm1 dependency should exist' {
        $module = Join-Path $script:RepoRoot 'scripts\lib\IssueSyncManager.psm1'
        Test-Path $module | Should -BeTrue
    }

    It 'config/agent-teams-backlog-rules.json should exist' {
        $rules = Join-Path $script:RepoRoot 'config\agent-teams-backlog-rules.json'
        Test-Path $rules | Should -BeTrue
    }

    It 'Step 6 should no longer emit the placeholder SKIP reason' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Not -Match 'Backlog / Scrum Master integration pending'
    }

    It 'Step 6 should report IssueSyncManager as loaded' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Match 'Backlog Module\s*:\s*\[OK\] IssueSyncManager loaded'
    }
}

Describe 'Start-ClaudeOS.ps1 — Step 8 Loop Engine Start (PR-D)' {
    It 'Step 8 should no longer emit the old placeholder reason' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Not -Match 'Loop orchestration handled by Claude Code /loop harness\s*\r?\n.*\[SKIP\]'
    }

    It 'Step 8 should detect the active session anchor' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Match 'Loop Engine\s*:\s*\[OK\] active session anchor detected'
    }
}

Describe 'Start-ClaudeOS.ps1 — E2E integration (PR-D)' {
    It 'all 9 step labels should appear in boot output (including OK and SKIP markers)' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Match '\[Step 1\].*Environment Check'
        $output | Should -Match '\[Step 2\].*Project Detection'
        $output | Should -Match '\[Step 3\].*Memory Restore'
        $output | Should -Match '\[Step 4\].*System Init'
        $output | Should -Match '\[Step 5\].*Executive Init'
        $output | Should -Match '\[Step 6\].*Management Init'
        $output | Should -Match '\[Step 7\].*Agent Init'
        $output | Should -Match '\[Step 8\].*Loop Engine Start'
        $output | Should -Match '\[Step 9\].*Dashboard'
    }

    It 'Boot Summary math should satisfy OK + SKIP + FAIL == 9' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        if ($output -match 'OK\s*:\s*(\d+)\s*[\r\n]+\s*SKIP\s*:\s*(\d+)\s*[\r\n]+\s*FAIL\s*:\s*(\d+)') {
            $ok   = [int]$Matches[1]
            $skip = [int]$Matches[2]
            $fail = [int]$Matches[3]
            ($ok + $skip + $fail) | Should -Be 9
        } else {
            throw 'Boot Summary pattern not found in output'
        }
    }

    It 'should complete with exit code 0 and success message' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'Boot sequence completed successfully'
    }
}

Describe 'Start-ClaudeOS.ps1 — Step 3 Memory Restore (PR-C)' {
    It '.mcp.json dependency should exist' {
        $mcpJson = Join-Path $script:RepoRoot '.mcp.json'
        Test-Path $mcpJson | Should -BeTrue
    }

    It '.mcp.json should contain memory MCP server entry' {
        $mcpJson = Join-Path $script:RepoRoot '.mcp.json'
        $config = Get-Content $mcpJson -Raw | ConvertFrom-Json
        $serverNames = @($config.mcpServers.PSObject.Properties.Name)
        $serverNames | Should -Contain 'memory'
    }

    It 'Step 3 should no longer emit the placeholder SKIP reason' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Not -Match 'Memory MCP persistence not yet integrated'
    }

    It 'Step 3 should report Memory MCP as configured' {
        $output = & $script:BootScript -DryRun -NonInteractive 6>&1 | Out-String
        $output | Should -Match 'Memory MCP\s*:\s*configured'
    }
}

Describe 'Start-ClaudeOS.ps1 — Exit Code' {
    It 'should set $LASTEXITCODE to 0 on successful run' {
        & $script:BootScript -DryRun -NonInteractive 6>$null
        $LASTEXITCODE | Should -Be 0
    }
}
