# ============================================================
# WorktreeManager.Tests.ps1 - WorktreeManager.psm1 unit tests
# Pester 5.x
# Issue #32: Worktree Manager
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\WorktreeManager.psm1') -Force
}

Describe 'Get-WorktreeBasePath' {

    It 'returns .worktrees under the given repo root' {
        $result = Get-WorktreeBasePath -RepoRoot 'C:\fake\repo'
        $result | Should -Be (Join-Path 'C:\fake\repo' '.worktrees')
    }
}

Describe 'Get-Worktree' {

    It 'returns at least the main worktree for the current repo' {
        $result = @(Get-Worktree -RepoRoot $script:RepoRoot)
        $result.Count | Should -BeGreaterOrEqual 1
    }

    It 'main worktree has IsMain = $true' {
        $result = @(Get-Worktree -RepoRoot $script:RepoRoot)
        $main = $result | Where-Object { $_.IsMain }
        $main | Should -Not -BeNullOrEmpty
    }

    It 'each worktree has a Path property' {
        $result = @(Get-Worktree -RepoRoot $script:RepoRoot)
        foreach ($wt in $result) {
            $wt.Path | Should -Not -BeNullOrEmpty
        }
    }

    It 'each worktree has a Commit hash' {
        $result = @(Get-Worktree -RepoRoot $script:RepoRoot)
        foreach ($wt in $result) {
            $wt.Commit | Should -Match '^[0-9a-f]{40}$'
        }
    }
}

Describe 'New-Worktree and Remove-Worktree' {

    BeforeAll {
        # Create a temporary bare-like test repo
        $script:TestRepo = Join-Path $TestDrive 'test-repo'
        git init -b main $script:TestRepo 2>$null | Out-Null
        Push-Location $script:TestRepo
        git config user.email "test@test.com"
        git config user.name "Test"
        Set-Content -Path (Join-Path $script:TestRepo 'README.md') -Value '# Test'
        git -C $script:TestRepo add .
        git -C $script:TestRepo commit -m "init" 2>$null | Out-Null
        Pop-Location
    }

    It 'creates a new worktree with a new branch' {
        $result = New-Worktree -BranchName 'feat/test-wt' -BaseBranch 'main' -RepoRoot $script:TestRepo
        $result.Branch | Should -Be 'feat/test-wt'
        $result.Path | Should -Not -BeNullOrEmpty
        Test-Path $result.Path | Should -Be $true
    }

    It 'lists the newly created worktree' {
        $worktrees = @(Get-Worktree -RepoRoot $script:TestRepo)
        $found = $worktrees | Where-Object { $_.Branch -eq 'feat/test-wt' }
        $found | Should -Not -BeNullOrEmpty
    }

    It 'Switch-Worktree finds the worktree by branch' {
        $result = Switch-Worktree -BranchName 'feat/test-wt' -RepoRoot $script:TestRepo
        $result.Branch | Should -Be 'feat/test-wt'
    }

    It 'throws when creating a duplicate branch' {
        { New-Worktree -BranchName 'feat/test-wt' -BaseBranch 'main' -RepoRoot $script:TestRepo } |
            Should -Throw "*already exists*"
    }

    It 'removes the worktree and optionally deletes the branch' {
        $result = Remove-Worktree -BranchName 'feat/test-wt' -DeleteBranch -RepoRoot $script:TestRepo
        $result.Branch | Should -Be 'feat/test-wt'
        $result.BranchDeleted | Should -Be $true
    }

    It 'worktree is no longer listed after removal' {
        $worktrees = @(Get-Worktree -RepoRoot $script:TestRepo)
        $found = $worktrees | Where-Object { $_.Branch -eq 'feat/test-wt' }
        $found | Should -BeNullOrEmpty
    }
}

Describe 'Switch-Worktree error handling' {

    It 'throws for non-existent branch' {
        { Switch-Worktree -BranchName 'nonexistent-branch-xyz' -RepoRoot $script:RepoRoot } |
            Should -Throw "*No worktree found*"
    }
}

Describe 'Get-WorktreeSummary' {

    It 'returns summary objects with Branch, Commit, Path, Label' {
        $result = @(Get-WorktreeSummary -RepoRoot $script:RepoRoot)
        $result.Count | Should -BeGreaterOrEqual 1
        $result[0].PSObject.Properties.Name | Should -Contain 'Branch'
        $result[0].PSObject.Properties.Name | Should -Contain 'Commit'
        $result[0].PSObject.Properties.Name | Should -Contain 'Path'
        $result[0].PSObject.Properties.Name | Should -Contain 'Label'
    }

    It 'main worktree has [MAIN] label' {
        $result = @(Get-WorktreeSummary -RepoRoot $script:RepoRoot)
        $main = $result | Where-Object { $_.Label -eq '[MAIN]' }
        $main | Should -Not -BeNullOrEmpty
    }
}

Describe 'Remove-Worktree safety' {

    It 'refuses to remove the main worktree' {
        $worktrees = @(Get-Worktree -RepoRoot $script:RepoRoot)
        $main = $worktrees | Where-Object { $_.IsMain }
        if ($main -and $main.Branch) {
            { Remove-Worktree -BranchName $main.Branch -RepoRoot $script:RepoRoot } |
                Should -Throw "*Cannot remove the main worktree*"
        }
    }
}

Describe 'Invoke-WorktreeCleanup' {

    BeforeAll {
        $script:CleanupRepo = Join-Path $TestDrive 'cleanup-repo'
        git init -b main $script:CleanupRepo 2>$null | Out-Null
        Push-Location $script:CleanupRepo
        git config user.email "test@test.com"
        git config user.name "Test"
        Set-Content -Path (Join-Path $script:CleanupRepo 'README.md') -Value '# Test'
        git -C $script:CleanupRepo add .
        git -C $script:CleanupRepo commit -m "init" 2>$null | Out-Null
        Pop-Location
    }

    It 'DryRun returns empty when no worktrees to clean' {
        $result = Invoke-WorktreeCleanup -RepoRoot $script:CleanupRepo -DryRun
        $result.Count | Should -Be 0
    }

    It 'cleans up worktrees with merged branches' {
        # Create a worktree with a new branch, commit changes
        $wtBase = Get-WorktreeBasePath -RepoRoot $script:CleanupRepo
        $wtPath = Join-Path $wtBase 'feat-cleanup-test'
        git -C $script:CleanupRepo worktree add -b 'feat/cleanup-test' $wtPath 'main' 2>&1 | Out-Null
        Set-Content -Path (Join-Path $wtPath 'test.txt') -Value 'test'
        git -C $wtPath add .
        git -C $wtPath commit -m "test change" 2>&1 | Out-Null

        # Remove worktree temporarily to allow merge
        git -C $script:CleanupRepo worktree remove $wtPath --force 2>&1 | Out-Null

        # Merge into main
        git -C $script:CleanupRepo merge 'feat/cleanup-test' --no-edit 2>&1 | Out-Null

        # Re-add worktree to simulate stale merged worktree
        git -C $script:CleanupRepo worktree add $wtPath 'feat/cleanup-test' 2>&1 | Out-Null

        # Verify branch is listed as merged
        $merged = git -C $script:CleanupRepo branch --merged main 2>&1
        ($merged -join ' ') | Should -Match 'feat/cleanup-test'

        # DryRun should find it
        $dryResult = Invoke-WorktreeCleanup -RepoRoot $script:CleanupRepo -DryRun
        $dryResult.Count | Should -Be 1

        # Actual cleanup
        $result = Invoke-WorktreeCleanup -RepoRoot $script:CleanupRepo
        $result.Count | Should -Be 1

        # Verify worktree is gone
        $worktrees = @(Get-Worktree -RepoRoot $script:CleanupRepo)
        $found = $worktrees | Where-Object { $_.Branch -eq 'feat/cleanup-test' }
        $found | Should -BeNullOrEmpty
    }

    It 'does not remove unmerged worktrees' {
        # Create worktree with unmerged branch
        $wt = New-Worktree -BranchName 'feat/unmerged-test' -BaseBranch 'main' -RepoRoot $script:CleanupRepo
        Set-Content -Path (Join-Path $wt.Path 'unmerged.txt') -Value 'unmerged'
        git -C $wt.Path add .
        git -C $wt.Path commit -m "unmerged change" 2>$null | Out-Null

        # Should NOT be in cleanup candidates
        $result = Invoke-WorktreeCleanup -RepoRoot $script:CleanupRepo -DryRun
        $found = $result.WouldRemove | Where-Object { $_.Branch -eq 'feat/unmerged-test' }
        $found | Should -BeNullOrEmpty

        # Cleanup
        Remove-Worktree -BranchName 'feat/unmerged-test' -DeleteBranch -Force -RepoRoot $script:CleanupRepo
    }
}
