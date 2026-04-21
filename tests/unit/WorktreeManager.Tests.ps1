# ============================================================
# WorktreeManager.Tests.ps1 - WorktreeManager.psm1 unit tests
# Pester 5.x  /  Issue #228
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\lib\WorktreeManager.psm1'
    Import-Module $script:ModulePath -Force
}

# ============================================================
# Get-WorktreeBasePath
# ============================================================
Describe 'Get-WorktreeBasePath' {

    It 'returns path ending with .worktrees when RepoRoot is supplied' {
        $result = Get-WorktreeBasePath -RepoRoot 'C:\repo'
        $result | Should -Match '\.worktrees$'
    }

    It 'joins RepoRoot and .worktrees correctly' {
        $result = Get-WorktreeBasePath -RepoRoot 'D:\projects\myapp'
        $result | Should -Be (Join-Path 'D:\projects\myapp' '.worktrees')
    }

    It 'works with UNC-style or long paths' {
        $result = Get-WorktreeBasePath -RepoRoot 'C:\Users\kensan\repos\my-project'
        $result | Should -Match 'my-project'
        $result | Should -Match '\.worktrees$'
    }

    It 'handles paths with spaces correctly' {
        $result = Get-WorktreeBasePath -RepoRoot 'C:\my repos\project'
        $result | Should -Be (Join-Path 'C:\my repos\project' '.worktrees')
    }

    It 'preserves deep nested paths and appends .worktrees' {
        $result = Get-WorktreeBasePath -RepoRoot 'D:\a\b\c\d\project'
        $result | Should -Match 'project'
        $result | Should -Match '\.worktrees$'
    }
}

# ============================================================
# Get-WorktreeSummary
# ============================================================
Describe 'Get-WorktreeSummary' {

    It 'returns one summary object per worktree' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @(
                [pscustomobject]@{ Path = 'C:\repo'; Commit = 'abc1234def0'; Branch = 'main';       IsBare = $false; IsMain = $true  },
                [pscustomobject]@{ Path = 'C:\repo\.worktrees\feat'; Commit = 'xyz5678abc0'; Branch = 'feat/my-feat'; IsBare = $false; IsMain = $false }
            )
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result.Count | Should -Be 2
    }

    It 'sets Label to [MAIN] for the main worktree' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @([pscustomobject]@{ Path = 'C:\repo'; Commit = 'abc1234def0'; Branch = 'main'; IsBare = $false; IsMain = $true })
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result[0].Label | Should -Be '[MAIN]'
    }

    It 'sets Label to empty string for non-main worktrees' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @([pscustomobject]@{ Path = 'C:\repo\.worktrees\feat'; Commit = 'abc1234def0'; Branch = 'feat/test'; IsBare = $false; IsMain = $false })
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result[0].Label | Should -Be ''
    }

    It 'truncates Commit hash to 7 characters' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @([pscustomobject]@{ Path = 'C:\repo'; Commit = 'abc1234def567'; Branch = 'main'; IsBare = $false; IsMain = $true })
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result[0].Commit | Should -Be 'abc1234'
        $result[0].Commit.Length | Should -Be 7
    }

    It 'returns (detached) when Branch is null' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @([pscustomobject]@{ Path = 'C:\repo\.worktrees\detach'; Commit = 'abc1234def0'; Branch = $null; IsBare = $false; IsMain = $false })
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result[0].Branch | Should -Be '(detached)'
    }

    It 'returns unknown when Commit is null' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @([pscustomobject]@{ Path = 'C:\repo'; Commit = $null; Branch = 'main'; IsBare = $false; IsMain = $true })
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result[0].Commit | Should -Be 'unknown'
    }

    It 'preserves the Path property from worktree data' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @([pscustomobject]@{ Path = 'C:\repo\.worktrees\my-feat'; Commit = 'abc1234def0'; Branch = 'feat/x'; IsBare = $false; IsMain = $false })
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result[0].Path | Should -Be 'C:\repo\.worktrees\my-feat'
    }

    It 'returns empty array when no worktrees exist' {
        Mock -ModuleName WorktreeManager Get-Worktree { @() }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        @($result).Count | Should -Be 0
    }

    It 'each summary object has Branch Commit Path Label properties' {
        Mock -ModuleName WorktreeManager Get-Worktree {
            @([pscustomobject]@{ Path = 'C:\repo'; Commit = 'abc1234def0'; Branch = 'main'; IsBare = $false; IsMain = $true })
        }
        $result = Get-WorktreeSummary -RepoRoot 'C:\repo'
        $result[0].PSObject.Properties.Name | Should -Contain 'Branch'
        $result[0].PSObject.Properties.Name | Should -Contain 'Commit'
        $result[0].PSObject.Properties.Name | Should -Contain 'Path'
        $result[0].PSObject.Properties.Name | Should -Contain 'Label'
    }
}
