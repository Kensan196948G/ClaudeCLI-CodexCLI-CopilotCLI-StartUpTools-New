# ============================================================
# IssueSyncManager.Tests.ps1 - IssueSyncManager.psm1 unit tests
# Pester 5.x
# Issue #33: Issue / Backlog auto-generation
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\IssueSyncManager.psm1') -Force
}

Describe 'ConvertTo-TaskLine' {

    It 'converts a basic issue to a task line' {
        $issue = [pscustomobject]@{
            number    = 42
            title     = 'Fix login bug'
            labels    = @([pscustomobject]@{ name = 'bug' })
            state     = 'open'
            assignees = @([pscustomobject]@{ login = 'dev1' })
        }
        $result = ConvertTo-TaskLine -Issue $issue -Index 1
        $result | Should -Match '1\.'
        $result | Should -Match 'Priority:P1'
        $result | Should -Match 'Owner:dev1'
        $result | Should -Match 'Source:GitHub#42'
        $result | Should -Match 'Fix login bug'
    }

    It 'sets priority P2 for enhancement label' {
        $issue = [pscustomobject]@{
            number    = 10
            title     = 'Add feature'
            labels    = @([pscustomobject]@{ name = 'enhancement' })
            state     = 'open'
            assignees = @()
        }
        $result = ConvertTo-TaskLine -Issue $issue -Index 1
        $result | Should -Match 'Priority:P2'
        $result | Should -Match 'Owner:Unassigned'
    }

    It 'sets priority P3 for documentation label' {
        $issue = [pscustomobject]@{
            number    = 5
            title     = 'Update docs'
            labels    = @([pscustomobject]@{ name = 'documentation' })
            state     = 'open'
            assignees = @()
        }
        $result = ConvertTo-TaskLine -Issue $issue -Index 1
        $result | Should -Match 'Priority:P3'
    }

    It 'marks closed issues as DONE' {
        $issue = [pscustomobject]@{
            number    = 3
            title     = 'Done task'
            labels    = @()
            state     = 'closed'
            assignees = @()
        }
        $result = ConvertTo-TaskLine -Issue $issue -Index 1
        $result | Should -Match '\[DONE\]'
    }

    It 'handles issues with no labels' {
        $issue = [pscustomobject]@{
            number    = 99
            title     = 'No labels'
            labels    = @()
            state     = 'open'
            assignees = @()
        }
        $result = ConvertTo-TaskLine -Issue $issue -Index 1
        $result | Should -Match 'Priority:P2'
    }
}

Describe 'ConvertFrom-TaskLine' {

    It 'parses a standard task line' {
        $line = '3. [Priority:P1][Owner:dev1][Source:GitHub#42] Fix login bug'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Index | Should -Be 3
        $result.Priority | Should -Be 'P1'
        $result.Owner | Should -Be 'dev1'
        $result.IssueNum | Should -Be 42
        $result.Title | Should -Be 'Fix login bug'
        $result.Done | Should -Be $false
    }

    It 'detects DONE status' {
        $line = '1. [DONE] [Priority:P1][Owner:Ops][Source:Manual] Completed task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Done | Should -Be $true
    }

    It 'handles non-GitHub source' {
        $line = '2. [Priority:P2][Owner:ScrumMaster][Source:AgentTeamsMatrix] worktree task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.IssueNum | Should -BeNullOrEmpty
        $result.Source | Should -Be 'AgentTeamsMatrix'
    }
}

Describe 'Get-TaskSection' {

    BeforeAll {
        $script:TestTasks = Join-Path $TestDrive 'TASKS.md'
        $content = @(
            '# TASKS'
            ''
            'Description line.'
            ''
            '## Manual Backlog'
            ''
            '1. [Priority:P1][Owner:Ops][Source:CI] old task'
            ''
            '## Auto Extracted From Agent Teams Matrix'
            ''
            '1. [Priority:P2][Owner:Ops][Source:AgentTeamsMatrix] worktree task'
            ''
        )
        Set-Content -Path $script:TestTasks -Value ($content -join "`n") -Encoding UTF8
    }

    It 'parses sections correctly' {
        $result = Get-TaskSection -TasksPath $script:TestTasks
        $result.Sections.Keys | Should -Contain 'Manual Backlog'
        $result.Sections.Keys | Should -Contain 'Auto Extracted From Agent Teams Matrix'
    }

    It 'preserves header lines' {
        $result = Get-TaskSection -TasksPath $script:TestTasks
        $result.Header | Should -Contain '# TASKS'
    }

    It 'preserves section order' {
        $result = Get-TaskSection -TasksPath $script:TestTasks
        $result.SectionOrder.Count | Should -Be 2
        $result.SectionOrder[0] | Should -Be 'Manual Backlog'
    }

    It 'returns empty structure for missing file' {
        $result = Get-TaskSection -TasksPath (Join-Path $TestDrive 'nonexistent.md')
        $result.Header | Should -Contain '# TASKS'
        $result.Sections.Count | Should -Be 0
    }
}

Describe 'Sync-IssueToTask DryRun' {

    BeforeAll {
        $script:TestTasks2 = Join-Path $TestDrive 'TASKS2.md'
        $content = @(
            '# TASKS'
            ''
            '## Manual Backlog'
            ''
            '1. Manual task'
            ''
        )
        Set-Content -Path $script:TestTasks2 -Value ($content -join "`n") -Encoding UTF8
    }

    It 'adds GitHub Issues Sync section with DryRun' {
        Mock Get-GitHubIssue -ModuleName IssueSyncManager {
            return @(
                [pscustomobject]@{
                    number    = 10
                    title     = 'Test issue'
                    labels    = @([pscustomobject]@{ name = 'enhancement' })
                    state     = 'open'
                    assignees = @()
                }
            )
        }

        $result = Sync-IssueToTask -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks2 -DryRun
        $result.IssueCount | Should -Be 1
        $result.Content | Should -Contain '## GitHub Issues Sync'
        $result.Content | Should -Contain '## Manual Backlog'
    }
}

Describe 'Sync-TaskToIssue DryRun' {

    BeforeAll {
        $script:TestTasks3 = Join-Path $TestDrive 'TASKS3.md'
        $content = @(
            '# TASKS'
            ''
            '## Manual Backlog'
            ''
            '1. [Priority:P1][Owner:Ops][Source:CI] new task without issue'
            '2. [DONE] [Priority:P1][Owner:Ops][Source:Manual] completed task'
            '3. [Priority:P1][Owner:Ops][Source:GitHub#10] already linked'
            ''
        )
        Set-Content -Path $script:TestTasks3 -Value ($content -join "`n") -Encoding UTF8
    }

    It 'identifies tasks that need GitHub Issues' {
        $result = Sync-TaskToIssue -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks3 -DryRun
        $result.Count | Should -Be 1
        $result.WouldCreate | Should -Contain 'new task without issue'
    }

    It 'skips DONE tasks' {
        $result = Sync-TaskToIssue -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks3 -DryRun
        $result.WouldCreate | Should -Not -Contain 'completed task'
    }

    It 'skips tasks already linked to GitHub' {
        $result = Sync-TaskToIssue -Owner 'test' -Repo 'test' -TasksPath $script:TestTasks3 -DryRun
        $result.WouldCreate | Should -Not -Contain 'already linked'
    }
}
