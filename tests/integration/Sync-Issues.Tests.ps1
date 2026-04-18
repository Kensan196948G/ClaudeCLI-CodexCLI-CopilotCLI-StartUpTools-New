# ============================================================
# Sync-Issues.Tests.ps1 - Sync-Issues.ps1 integration tests
# Pester 5.x
# Issue sync CI/hooks integration
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\IssueSyncManager.psm1') -Force
    $script:SyncScript = Join-Path $script:RepoRoot 'scripts\tools\Sync-Issues.ps1'
}

Describe 'Sync-Issues check action' {

    BeforeAll {
        $script:TestTasks = Join-Path $TestDrive 'TASKS-check.md'
    }

    It 'passes validation for well-formed TASKS.md' {
        $content = @(
            '# TASKS'
            ''
            '## Manual Backlog'
            ''
            '1. [Priority:P1][Owner:Ops][Source:CI] task one'
            '2. [DONE] [Priority:P2][Owner:Dev][Source:Manual] task two'
            ''
            '## GitHub Issues Sync'
            ''
            '1. [Priority:P2][Owner:Unassigned][Source:GitHub#34] milestone issue'
            ''
        )
        Set-Content -Path $script:TestTasks -Value ($content -join "`n") -Encoding UTF8

        # Test by directly calling the module functions (check logic)
        $parsed = Get-TaskSection -TasksPath $script:TestTasks
        $parsed.Sections.Keys | Should -Contain 'Manual Backlog'
        $parsed.Sections.Keys | Should -Contain 'GitHub Issues Sync'

        $manualLines = @($parsed.Sections['Manual Backlog'] | Where-Object { $_ -match '^\d+\.\s' })
        $issueLines = @($parsed.Sections['GitHub Issues Sync'] | Where-Object { $_ -match '^\d+\.\s' })

        $manualLines.Count | Should -Be 2
        $issueLines.Count | Should -Be 1

        # Validate format
        foreach ($line in ($manualLines + $issueLines)) {
            $line | Should -Match '\[Priority:P[1-3]\]'
            $line | Should -Match '\[Owner:[^\]]+\]'
            $line | Should -Match '\[Source:[^\]]+\]'
        }

        # Issue section lines must have GitHub# source
        foreach ($line in $issueLines) {
            $line | Should -Match '\[Source:GitHub#\d+\]'
        }
    }

    It 'detects invalid priority format' {
        $content = @(
            '# TASKS'
            ''
            '## Manual Backlog'
            ''
            '1. [Priority:High][Owner:Ops][Source:CI] bad priority'
            ''
        )
        Set-Content -Path $script:TestTasks -Value ($content -join "`n") -Encoding UTF8

        $parsed = Get-TaskSection -TasksPath $script:TestTasks
        $manualLines = @($parsed.Sections['Manual Backlog'] | Where-Object { $_ -match '^\d+\.\s' })
        $manualLines[0] | Should -Not -Match '\[Priority:P[1-3]\]'
    }

    It 'detects issue sync line without GitHub# source' {
        $content = @(
            '# TASKS'
            ''
            '## GitHub Issues Sync'
            ''
            '1. [Priority:P2][Owner:Ops][Source:Manual] should have GitHub source'
            ''
        )
        Set-Content -Path $script:TestTasks -Value ($content -join "`n") -Encoding UTF8

        $parsed = Get-TaskSection -TasksPath $script:TestTasks
        $issueLines = @($parsed.Sections['GitHub Issues Sync'] | Where-Object { $_ -match '^\d+\.\s' })
        $issueLines[0] | Should -Not -Match '\[Source:GitHub#\d+\]'
    }

    It 'handles TASKS.md without GitHub Issues Sync section' {
        $content = @(
            '# TASKS'
            ''
            '## Manual Backlog'
            ''
            '1. [Priority:P1][Owner:Ops][Source:CI] task only'
            ''
        )
        Set-Content -Path $script:TestTasks -Value ($content -join "`n") -Encoding UTF8

        $parsed = Get-TaskSection -TasksPath $script:TestTasks
        $parsed.Sections.Keys | Should -Not -Contain 'GitHub Issues Sync'
    }
}

Describe 'Sync-Issues sync action with DryRun' {

    BeforeAll {
        $script:TestTasks2 = Join-Path $TestDrive 'TASKS-sync.md'
        $content = @(
            '# TASKS'
            ''
            '## Manual Backlog'
            ''
            '1. [Priority:P1][Owner:Ops][Source:CI] existing task'
            ''
        )
        Set-Content -Path $script:TestTasks2 -Value ($content -join "`n") -Encoding UTF8
    }

    It 'creates GitHub Issues Sync section via DryRun' {
        Mock Get-GitHubIssue -ModuleName IssueSyncManager {
            return @(
                [pscustomobject]@{
                    number    = 34
                    title     = 'v3.0.0 release plan'
                    labels    = @([pscustomobject]@{ name = 'documentation' })
                    state     = 'open'
                    assignees = @([pscustomobject]@{ login = 'Kensan196948G' })
                }
            )
        }

        $result = Sync-IssueToTask -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks2 -DryRun
        $result.IssueCount | Should -Be 1
        $result.Content | Should -Contain '## GitHub Issues Sync'
        $joined = $result.Content -join "`n"
        $joined | Should -Match 'Source:GitHub#34'
        $joined | Should -Match 'Priority:P3'
        $joined | Should -Match 'Owner:Kensan196948G'
    }

    It 'preserves existing sections when adding issue sync' {
        Mock Get-GitHubIssue -ModuleName IssueSyncManager {
            return @()
        }

        $result = Sync-IssueToTask -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks2 -DryRun
        $result.Content | Should -Contain '## Manual Backlog'
        $result.Content | Should -Contain '## GitHub Issues Sync'
    }
}

Describe 'Get-SyncStatus' {

    BeforeAll {
        $script:TestTasks3 = Join-Path $TestDrive 'TASKS-status.md'
        $content = @(
            '# TASKS'
            ''
            '## GitHub Issues Sync'
            ''
            '1. [Priority:P3][Owner:Kensan196948G][Source:GitHub#34] milestone issue'
            ''
        )
        Set-Content -Path $script:TestTasks3 -Value ($content -join "`n") -Encoding UTF8
    }

    It 'reports in-sync when issues match' {
        Mock Get-GitHubIssue -ModuleName IssueSyncManager {
            return @(
                [pscustomobject]@{
                    number    = 34
                    title     = 'milestone issue'
                    labels    = @()
                    state     = 'open'
                    assignees = @()
                }
            )
        }

        $result = Get-SyncStatus -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks3
        $result.InSync | Should -Be $true
        $result.MissingInTasks.Count | Should -Be 0
        $result.StaleInTasks.Count | Should -Be 0
    }

    It 'detects missing issues' {
        Mock Get-GitHubIssue -ModuleName IssueSyncManager {
            return @(
                [pscustomobject]@{ number = 34; title = 'a'; labels = @(); state = 'open'; assignees = @() },
                [pscustomobject]@{ number = 50; title = 'b'; labels = @(); state = 'open'; assignees = @() }
            )
        }

        $result = Get-SyncStatus -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks3
        $result.InSync | Should -Be $false
        $result.MissingInTasks | Should -Contain 50
    }

    It 'detects stale entries' {
        Mock Get-GitHubIssue -ModuleName IssueSyncManager {
            return @()
        }

        $result = Get-SyncStatus -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks3
        $result.InSync | Should -Be $false
        $result.StaleInTasks | Should -Contain 34
    }
}
