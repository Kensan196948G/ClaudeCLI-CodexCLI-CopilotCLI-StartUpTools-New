# ============================================================
# MenuCommon.Tests.ps1 - MenuCommon.psm1 unit tests
# Pester 5.x  /  Issue #183
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\MenuCommon.psm1') -Force
}

Describe 'ConvertTo-MenuRecentToolFilter' {

    It 'returns empty string for empty input' {
        ConvertTo-MenuRecentToolFilter -ToolFilter '' | Should -Be ''
    }

    It 'returns empty string for whitespace input' {
        ConvertTo-MenuRecentToolFilter -ToolFilter '   ' | Should -Be ''
    }

    It 'returns empty string for "all"' {
        ConvertTo-MenuRecentToolFilter -ToolFilter 'all' | Should -Be ''
    }

    It 'returns "claude" for valid tool' {
        ConvertTo-MenuRecentToolFilter -ToolFilter 'claude' | Should -Be 'claude'
    }

    It 'returns "codex" for valid tool' {
        ConvertTo-MenuRecentToolFilter -ToolFilter 'codex' | Should -Be 'codex'
    }

    It 'returns "copilot" for valid tool' {
        ConvertTo-MenuRecentToolFilter -ToolFilter 'copilot' | Should -Be 'copilot'
    }

    It 'returns empty string for unknown tool' {
        ConvertTo-MenuRecentToolFilter -ToolFilter 'cursor' | Should -Be ''
    }

    It 'returns empty string when no parameter (default)' {
        ConvertTo-MenuRecentToolFilter | Should -Be ''
    }
}

Describe 'ConvertTo-MenuRecentSortMode' {

    It 'returns "success" for valid mode' {
        ConvertTo-MenuRecentSortMode -SortMode 'success' | Should -Be 'success'
    }

    It 'returns "timestamp" for valid mode' {
        ConvertTo-MenuRecentSortMode -SortMode 'timestamp' | Should -Be 'timestamp'
    }

    It 'returns "elapsed" for valid mode' {
        ConvertTo-MenuRecentSortMode -SortMode 'elapsed' | Should -Be 'elapsed'
    }

    It 'returns "success" for unknown mode' {
        ConvertTo-MenuRecentSortMode -SortMode 'random' | Should -Be 'success'
    }

    It 'returns "success" when no parameter (default)' {
        ConvertTo-MenuRecentSortMode | Should -Be 'success'
    }
}

Describe 'Get-MenuRecentFilterSummary' {

    It 'returns defaults when no parameters given' {
        $s = Get-MenuRecentFilterSummary
        $s.tool   | Should -Be 'all'
        $s.search | Should -Be 'none'
        $s.sort   | Should -Be 'success'
    }

    It 'sets tool when valid filter provided' {
        $s = Get-MenuRecentFilterSummary -ToolFilter 'claude'
        $s.tool | Should -Be 'claude'
    }

    It 'sets search when search query provided' {
        $s = Get-MenuRecentFilterSummary -SearchQuery 'myproject'
        $s.search | Should -Be 'myproject'
    }

    It 'returns "none" for whitespace search query' {
        $s = Get-MenuRecentFilterSummary -SearchQuery '   '
        $s.search | Should -Be 'none'
    }

    It 'normalizes invalid sort mode to "success"' {
        $s = Get-MenuRecentFilterSummary -SortMode 'invalid'
        $s.sort | Should -Be 'success'
    }

    It 'combines all parameters correctly' {
        $s = Get-MenuRecentFilterSummary -ToolFilter 'codex' -SearchQuery 'proj' -SortMode 'timestamp'
        $s.tool   | Should -Be 'codex'
        $s.search | Should -Be 'proj'
        $s.sort   | Should -Be 'timestamp'
    }
}