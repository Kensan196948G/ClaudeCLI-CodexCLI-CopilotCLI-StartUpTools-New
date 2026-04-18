# ============================================================
# McpHealthCheck.Tests.ps1 - McpHealthCheck.psm1 unit tests
# Pester 5.x  /  Issue #184
# ============================================================

# Import at script scope so InModuleScope can reference the module during discovery
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $script:RepoRoot 'scripts\lib\McpHealthCheck.psm1') -Force

InModuleScope McpHealthCheck {

    Describe 'ConvertTo-McpProcessArgumentString' {

        It 'returns empty string for an empty arguments array' {
            $result = ConvertTo-McpProcessArgumentString -Arguments @()
            $result | Should -Be ''
        }

        It 'returns a single simple argument unchanged' {
            $result = ConvertTo-McpProcessArgumentString -Arguments @('node')
            $result | Should -Be 'node'
        }

        It 'wraps an argument containing a space in double quotes' {
            $result = ConvertTo-McpProcessArgumentString -Arguments @('my server')
            $result | Should -Be '"my server"'
        }

        It 'escapes a double quote inside an argument' {
            $result = ConvertTo-McpProcessArgumentString -Arguments @('say "hi"')
            $result | Should -Be '"say \"hi\""'
        }

        It 'joins multiple simple arguments with a single space' {
            $result = ConvertTo-McpProcessArgumentString -Arguments @('node', 'server.js', '--port', '3000')
            $result | Should -Be 'node server.js --port 3000'
        }

        It 'handles mixed simple and space-containing arguments' {
            $result = ConvertTo-McpProcessArgumentString -Arguments @('node', 'my server.js')
            $result | Should -Be 'node "my server.js"'
        }
    }
}