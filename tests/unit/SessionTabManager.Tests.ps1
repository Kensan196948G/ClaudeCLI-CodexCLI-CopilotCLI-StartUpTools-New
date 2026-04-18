# ============================================================
# SessionTabManager.Tests.ps1 - SessionTabManager.psm1 unit tests
# Pester 5.x  /  Issue #183
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\SessionTabManager.psm1') -Force
}

Describe 'Get-SessionDir' {

    It 'returns explicit config dir when provided' {
        $result = Get-SessionDir -ConfigSessionsDir 'C:\custom\sessions'
        $result | Should -Be 'C:\custom\sessions'
    }

    It 'returns default dir ending with .claudeos\sessions when no config given' {
        $result = Get-SessionDir
        $result | Should -Match '\.claudeos[/\\]sessions$'
    }

    It 'returns default dir when config is whitespace' {
        $result = Get-SessionDir -ConfigSessionsDir '   '
        $result | Should -Match '\.claudeos[/\\]sessions$'
    }

    It 'expands environment variables in config dir' {
        $result = Get-SessionDir -ConfigSessionsDir '%TEMP%\sessions'
        $result | Should -Not -Match '%TEMP%'
        $result | Should -Match 'sessions$'
    }
}

Describe 'New-SessionId' {

    It 'returns a string matching yyyyMMdd-HHmmss-project pattern' {
        $id = New-SessionId -Project 'myproj'
        $id | Should -Match '^\d{8}-\d{6}-myproj$'
    }

    It 'sanitizes spaces to underscores' {
        $id = New-SessionId -Project 'my project'
        $id | Should -Match '-my_project$'
    }

    It 'sanitizes dots to underscores' {
        $id = New-SessionId -Project 'v3.2.0'
        $id | Should -Match '-v3_2_0$'
    }

    It 'preserves alphanumeric, hyphen, and underscore' {
        $id = New-SessionId -Project 'proj-A_1'
        $id | Should -Match '-proj-A_1$'
    }
}

Describe 'New-SessionInfo, Save-SessionInfo, Get-SessionInfo' {

    It 'New-SessionInfo creates a session with status running' {
        $session = New-SessionInfo -Project 'testproj' -DurationMinutes 60 `
            -Trigger 'manual' -ConfigSessionsDir (Join-Path $TestDrive 'sessions1')
        $session.status  | Should -Be 'running'
        $session.project | Should -Be 'testproj'
        $session.max_duration_minutes | Should -Be 60
        $session.trigger | Should -Be 'manual'
    }

    It 'New-SessionInfo writes a JSON file to the sessions directory' {
        $sessDir = Join-Path $TestDrive 'sessions2'
        $null = New-SessionInfo -Project 'filepersist' -ConfigSessionsDir $sessDir
        $file = Get-ChildItem -Path $sessDir -Filter '*.json' | Select-Object -First 1
        $file | Should -Not -BeNullOrEmpty
    }

    It 'Get-SessionInfo returns null when session does not exist' {
        $result = Get-SessionInfo -SessionId 'nonexistent-id' `
            -ConfigSessionsDir (Join-Path $TestDrive 'sessions3')
        $result | Should -BeNullOrEmpty
    }

    It 'Save-SessionInfo then Get-SessionInfo round-trips the project field' {
        $sessDir = Join-Path $TestDrive 'sessions4'
        New-Item -ItemType Directory -Path $sessDir | Out-Null
        $session = New-SessionInfo -Project 'roundtrip' -ConfigSessionsDir $sessDir
        $loaded  = Get-SessionInfo -SessionId $session.sessionId -ConfigSessionsDir $sessDir
        $loaded.project | Should -Be 'roundtrip'
        $loaded.status  | Should -Be 'running'
    }
}

Describe 'Get-ActiveSession' {

    It 'returns null when sessions directory does not exist' {
        $result = Get-ActiveSession -ConfigSessionsDir (Join-Path $TestDrive 'no-sessions')
        $result | Should -BeNullOrEmpty
    }

    It 'returns null when no running sessions exist' {
        $sessDir = Join-Path $TestDrive 'active-empty'
        New-Item -ItemType Directory -Path $sessDir | Out-Null
        $result = Get-ActiveSession -ConfigSessionsDir $sessDir
        $result | Should -BeNullOrEmpty
    }

    It 'returns the running session when one exists' {
        $sessDir = Join-Path $TestDrive 'active-one'
        $null = New-SessionInfo -Project 'active-test' -ConfigSessionsDir $sessDir
        $result = Get-ActiveSession -ConfigSessionsDir $sessDir
        $result.project | Should -Be 'active-test'
        $result.status  | Should -Be 'running'
    }
}