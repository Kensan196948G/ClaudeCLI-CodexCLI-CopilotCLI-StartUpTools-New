# ============================================================
# IssueSyncManager.Tests.ps1 - IssueSyncManager.psm1 unit tests
# Pester 5.x  /  Phase 4 unit tests
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\lib\IssueSyncManager.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-TasksFilePath' {

    It 'returns path ending with TASKS.md for a given RepoRoot' {
        $result = Get-TasksFilePath -RepoRoot 'C:\repo'
        $result | Should -Be 'C:\repo\TASKS.md'
    }

    It 'joins RepoRoot and TASKS.md correctly on Windows paths' {
        $result = Get-TasksFilePath -RepoRoot 'D:\projects\myapp'
        $result | Should -Match 'TASKS\.md$'
    }
}

Describe 'ConvertTo-TaskLine' {

    Context 'ラベルなし Issue' {

        It 'Priority は P2 (デフォルト)' {
            $issue = [pscustomobject]@{ number = 10; title = 'Fix something'; labels = @(); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match '\[Priority:P2\]'
        }

        It 'Owner は Unassigned (デフォルト)' {
            $issue = [pscustomobject]@{ number = 10; title = 'Fix something'; labels = @(); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match '\[Owner:Unassigned\]'
        }

        It 'Source に Issue 番号が含まれる' {
            $issue = [pscustomobject]@{ number = 42; title = 'Add feature'; labels = @(); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match '\[Source:GitHub#42\]'
        }

        It 'title がそのまま末尾に出力される' {
            $issue = [pscustomobject]@{ number = 5; title = 'My task title'; labels = @(); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match 'My task title$'
        }
    }

    Context 'bug ラベルの場合' {

        It 'Priority が P1 になる' {
            $label = [pscustomobject]@{ name = 'bug' }
            $issue = [pscustomobject]@{ number = 7; title = 'Bug report'; labels = @($label); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match '\[Priority:P1\]'
        }
    }

    Context 'enhancement ラベルの場合' {

        It 'Priority が P2 になる' {
            $label = [pscustomobject]@{ name = 'enhancement' }
            $issue = [pscustomobject]@{ number = 8; title = 'New feature'; labels = @($label); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match '\[Priority:P2\]'
        }
    }

    Context 'documentation ラベルの場合' {

        It 'Priority が P3 になる' {
            $label = [pscustomobject]@{ name = 'documentation' }
            $issue = [pscustomobject]@{ number = 9; title = 'Update docs'; labels = @($label); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match '\[Priority:P3\]'
        }
    }

    Context 'closed Issue の場合' {

        It '[DONE] プレフィックスが付く' {
            $issue = [pscustomobject]@{ number = 3; title = 'Completed'; labels = @(); state = 'closed'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 2
            $line | Should -Match '\[DONE\]'
        }
    }

    Context 'assignee がある場合' {

        It 'Owner に assignee の login が設定される' {
            $assignee = [pscustomobject]@{ login = 'alice' }
            $issue = [pscustomobject]@{ number = 11; title = 'Assigned task'; labels = @(); state = 'open'; assignees = @($assignee) }
            $line = ConvertTo-TaskLine -Issue $issue -Index 1
            $line | Should -Match '\[Owner:alice\]'
        }
    }

    Context 'Index が 0 の場合' {

        It '番号プレフィックスが出力されない' {
            $issue = [pscustomobject]@{ number = 1; title = 'No index'; labels = @(); state = 'open'; assignees = @() }
            $line = ConvertTo-TaskLine -Issue $issue -Index 0
            $line | Should -Not -Match '^\d+\.'
        }
    }
}

Describe 'ConvertFrom-TaskLine' {

    It '行番号を正しく解析する' {
        $line = '5. [Priority:P1][Owner:Developer][Source:GitHub#33] Title here'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Index | Should -Be 5
    }

    It '[DONE] フラグを検出する' {
        $line = '3. [DONE] [Priority:P2][Owner:Ops][Source:Manual] Completed task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Done | Should -Be $true
    }

    It 'Done でない行は Done = false' {
        $line = '4. [Priority:P2][Owner:Developer][Source:Manual] Active task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Done | Should -Be $false
    }

    It 'Priority を正しく解析する' {
        $line = '1. [Priority:P1][Owner:Architect][Source:Manual] High priority'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Priority | Should -Be 'P1'
    }

    It 'Owner を正しく解析する' {
        $line = '2. [Priority:P2][Owner:DevOps][Source:CI] Deploy task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Owner | Should -Be 'DevOps'
    }

    It 'Source を正しく解析する' {
        $line = '6. [Priority:P3][Owner:Developer][Source:GitHub#99] Issue task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Source | Should -Be 'GitHub#99'
    }

    It 'GitHub Issue 番号を IssueNum として解析する' {
        $line = '6. [Priority:P3][Owner:Developer][Source:GitHub#99] Issue task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.IssueNum | Should -Be 99
    }

    It 'タイトルを正しく解析する' {
        $line = '7. [Priority:P2][Owner:Developer][Source:Manual] My task title'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Title | Should -Be 'My task title'
    }

    It 'GitHub 以外の Source は IssueNum が null' {
        $line = '8. [Priority:P2][Owner:Ops][Source:Manual] Manual task'
        $result = ConvertFrom-TaskLine -Line $line
        $result.IssueNum | Should -BeNullOrEmpty
    }

    It 'Raw フィールドに元の行が格納される' {
        $line = '9. [Priority:P1][Owner:CTO][Source:Manual] Raw test'
        $result = ConvertFrom-TaskLine -Line $line
        $result.Raw | Should -Be $line
    }
}

Describe 'ConvertTo-TaskLine と ConvertFrom-TaskLine のラウンドトリップ' {

    It 'open Issue → TaskLine → parse で title が一致する' {
        $issue = [pscustomobject]@{ number = 55; title = 'Round-trip test'; labels = @(); state = 'open'; assignees = @() }
        $line   = ConvertTo-TaskLine -Issue $issue -Index 10
        $parsed = ConvertFrom-TaskLine -Line $line
        $parsed.Title | Should -Be 'Round-trip test'
    }

    It 'bug Issue → TaskLine → parse で Priority P1 が保持される' {
        $label = [pscustomobject]@{ name = 'bug' }
        $issue = [pscustomobject]@{ number = 56; title = 'Bug rt'; labels = @($label); state = 'open'; assignees = @() }
        $line   = ConvertTo-TaskLine -Issue $issue -Index 11
        $parsed = ConvertFrom-TaskLine -Line $line
        $parsed.Priority | Should -Be 'P1'
    }
}
