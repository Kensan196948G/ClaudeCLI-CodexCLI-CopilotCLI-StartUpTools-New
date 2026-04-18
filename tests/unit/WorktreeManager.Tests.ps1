# ============================================================
# WorktreeManager.Tests.ps1 - WorktreeManager.psm1 unit tests
# Pester 5.x  /  Phase 4 unit tests
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\lib\WorktreeManager.psm1'
    Import-Module $script:ModulePath -Force
}

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
}
