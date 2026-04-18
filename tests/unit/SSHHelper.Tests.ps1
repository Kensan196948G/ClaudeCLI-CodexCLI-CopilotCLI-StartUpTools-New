# ============================================================
# SSHHelper.Tests.ps1 - SSHHelper.psm1 unit tests
# Pester 5.x  /  Issue #183
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\SSHHelper.psm1') -Force
}

Describe 'ConvertTo-EscapedSSHArgument' {

    It 'wraps a simple word in single quotes' {
        ConvertTo-EscapedSSHArgument -Value 'hello' | Should -Be "'hello'"
    }

    It 'throws for empty string (Mandatory parameter rejects it)' {
        { ConvertTo-EscapedSSHArgument -Value '' } | Should -Throw
    }

    It 'wraps a string with spaces in single quotes' {
        ConvertTo-EscapedSSHArgument -Value 'hello world' | Should -Be "'hello world'"
    }

    It 'escapes a single quote inside the value' {
        # Input: it's  ->  Expected: 'it'\''s'
        ConvertTo-EscapedSSHArgument -Value "it's" | Should -Be "'it'\''s'"
    }

    It 'escapes multiple single quotes' {
        # Input: a'b'c  ->  Expected: 'a'\''b'\''c'
        ConvertTo-EscapedSSHArgument -Value "a'b'c" | Should -Be "'a'\''b'\''c'"
    }

    It 'does not alter dollar sign characters (they stay literal inside single quotes)' {
        # Use backtick-dollar to prevent PowerShell variable expansion in double-quoted string
        ConvertTo-EscapedSSHArgument -Value '$HOME' | Should -Be "'`$HOME'"
    }

    It 'does not alter backslash characters' {
        ConvertTo-EscapedSSHArgument -Value 'back\slash' | Should -Be "'back\slash'"
    }
}