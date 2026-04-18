# ============================================================
# StatuslineManager.Tests.ps1 - StatuslineManager.psm1 unit tests
# Pester 5.x  /  Issue #184
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\StatuslineManager.psm1') -Force
}

Describe 'Get-GlobalStatusLineConfig' {

    It 'returns found=false when settings file does not exist' {
        $result = Get-GlobalStatusLineConfig -SettingsPath (Join-Path $TestDrive 'nonexistent.json')
        $result.found | Should -Be $false
        $result.statusLine | Should -BeNullOrEmpty
    }

    It 'stores the requested path in the result object' {
        $path = Join-Path $TestDrive 'check-path.json'
        $result = Get-GlobalStatusLineConfig -SettingsPath $path
        $result.path | Should -Be $path
    }

    It 'returns found=true when settings file exists' {
        $path = Join-Path $TestDrive 'settings-exist.json'
        '{"version": 1}' | Set-Content $path -Encoding UTF8
        $result = Get-GlobalStatusLineConfig -SettingsPath $path
        $result.found | Should -Be $true
    }

    It 'returns the statusLine value when present in the JSON' {
        $path = Join-Path $TestDrive 'settings-with-sl.json'
        '{"statusLine": {"enabled": true, "format": "test"}}' | Set-Content $path -Encoding UTF8
        $result = Get-GlobalStatusLineConfig -SettingsPath $path
        $result.statusLine | Should -Not -BeNullOrEmpty
        $result.statusLine.enabled | Should -Be $true
    }

    It 'returns statusLine=null when the JSON has no statusLine key' {
        $path = Join-Path $TestDrive 'settings-no-sl.json'
        '{"other": "value"}' | Set-Content $path -Encoding UTF8
        $result = Get-GlobalStatusLineConfig -SettingsPath $path
        $result.found | Should -Be $true
        $result.statusLine | Should -BeNullOrEmpty
    }

    It 'throws when the settings file contains invalid JSON' {
        $path = Join-Path $TestDrive 'settings-bad.json'
        'NOT VALID JSON {{{{' | Set-Content $path -Encoding UTF8
        { Get-GlobalStatusLineConfig -SettingsPath $path } | Should -Throw
    }

    It 'uses a default path ending with .claude\settings.json when no path is given' {
        $result = Get-GlobalStatusLineConfig
        $result.path | Should -Match '\.claude[/\\]settings\.json$'
    }
}