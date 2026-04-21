# ============================================================
# RecentProjects.Tests.ps1 - RecentProjects.ps1 unit tests
# Pester 5.x  /  Issue #230
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\lib\RecentProjects.ps1'
    . $script:ScriptPath
}

# ============================================================
# Get-RecentProject
# ============================================================
Describe 'Get-RecentProject' {

    It 'returns empty array when history file does not exist' {
        $result = Get-RecentProject -HistoryPath 'C:\nonexistent\path\recent.json'
        @($result).Count | Should -Be 0
    }

    It 'returns empty array when projects property is null' {
        $tmpFile = Join-Path $TestDrive 'no-projects.json'
        '{"projects":null}' | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        @($result).Count | Should -Be 0
    }

    It 'returns empty array when projects key is missing' {
        $tmpFile = Join-Path $TestDrive 'empty-root.json'
        '{}' | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        @($result).Count | Should -Be 0
    }

    It 'normalizes a legacy string entry to pscustomobject with null optional fields' {
        $tmpFile = Join-Path $TestDrive 'legacy-string.json'
        '{"projects":["MyProject"]}' | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        $result[0].project   | Should -Be 'MyProject'
        $result[0].tool      | Should -BeNullOrEmpty
        $result[0].mode      | Should -BeNullOrEmpty
        $result[0].timestamp | Should -BeNullOrEmpty
        $result[0].result    | Should -BeNullOrEmpty
        $result[0].elapsedMs | Should -BeNullOrEmpty
    }

    It 'normalizes an object entry with all fields' {
        $tmpFile = Join-Path $TestDrive 'full-object.json'
        $json = '{"projects":[{"project":"Proj","tool":"claude","mode":"local","timestamp":"2026-01-01T00:00:00Z","result":"success","elapsedMs":1234}]}'
        $json | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        $result[0].project   | Should -Be 'Proj'
        $result[0].tool      | Should -Be 'claude'
        $result[0].mode      | Should -Be 'local'
        $result[0].result    | Should -Be 'success'
        $result[0].elapsedMs | Should -Be 1234
    }

    It 'sets optional fields to null when missing from object entry' {
        $tmpFile = Join-Path $TestDrive 'partial-object.json'
        '{"projects":[{"project":"PartialProj"}]}' | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        $result[0].project | Should -Be 'PartialProj'
        $result[0].tool    | Should -BeNullOrEmpty
        $result[0].mode    | Should -BeNullOrEmpty
    }

    It 'casts elapsedMs to int' {
        $tmpFile = Join-Path $TestDrive 'elapsed.json'
        '{"projects":[{"project":"P","elapsedMs":500}]}' | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        $result[0].elapsedMs | Should -Be 500
        $result[0].elapsedMs | Should -BeOfType [int]
    }

    It 'normalizes empty string tool/mode/result fields to null' {
        $tmpFile = Join-Path $TestDrive 'empty-strings.json'
        '{"projects":[{"project":"P","tool":"","mode":"","result":""}]}' | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        $result[0].tool   | Should -BeNullOrEmpty
        $result[0].mode   | Should -BeNullOrEmpty
        $result[0].result | Should -BeNullOrEmpty
    }

    It 'returns empty array on invalid JSON (error suppressed)' {
        $tmpFile = Join-Path $TestDrive 'bad.json'
        'NOT_VALID_JSON{{{' | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Get-RecentProject -HistoryPath $tmpFile
        @($result).Count | Should -Be 0
    }

    It 'expands environment variable in HistoryPath' {
        $tmpDir  = Join-Path $TestDrive 'env-expand'
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $tmpFile = Join-Path $tmpDir 'recent.json'
        '{"projects":["EnvProj"]}' | Set-Content -Path $tmpFile -Encoding UTF8
        $env:PESTER_TEST_DIR_RP = $tmpDir
        try {
            $result = Get-RecentProject -HistoryPath '%PESTER_TEST_DIR_RP%\recent.json'
            $result[0].project | Should -Be 'EnvProj'
        }
        finally {
            Remove-Item Env:\PESTER_TEST_DIR_RP -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# Update-RecentProject
# ============================================================
Describe 'Update-RecentProject' {

    It 'creates directory and file when they do not exist' {
        $histPath = Join-Path $TestDrive 'new-dir\sub\recent.json'
        Update-RecentProject -ProjectName 'NewProj' -HistoryPath $histPath
        Test-Path $histPath | Should -BeTrue
        $result = Get-RecentProject -HistoryPath $histPath
        $result[0].project | Should -Be 'NewProj'
    }

    It 'inserts new entry at the front of the list' {
        $histPath = Join-Path $TestDrive 'insert-front.json'
        Update-RecentProject -ProjectName 'First'  -HistoryPath $histPath
        Update-RecentProject -ProjectName 'Second' -HistoryPath $histPath
        $result = Get-RecentProject -HistoryPath $histPath
        $result[0].project | Should -Be 'Second'
        $result[1].project | Should -Be 'First'
    }

    It 'removes duplicate entry before re-adding at front' {
        $histPath = Join-Path $TestDrive 'dedup.json'
        Update-RecentProject -ProjectName 'Alpha' -HistoryPath $histPath
        Update-RecentProject -ProjectName 'Beta'  -HistoryPath $histPath
        Update-RecentProject -ProjectName 'Alpha' -HistoryPath $histPath
        $result = Get-RecentProject -HistoryPath $histPath
        $result[0].project | Should -Be 'Alpha'
        $result[1].project | Should -Be 'Beta'
        @($result).Count   | Should -Be 2
    }

    It 'trims list to MaxHistory entries' {
        $histPath = Join-Path $TestDrive 'maxhist.json'
        1..5 | ForEach-Object { Update-RecentProject -ProjectName "P$_" -HistoryPath $histPath }
        Update-RecentProject -ProjectName 'OverflowProject' -HistoryPath $histPath -MaxHistory 3
        $result = Get-RecentProject -HistoryPath $histPath
        @($result).Count   | Should -Be 3
        $result[0].project | Should -Be 'OverflowProject'
    }
}

# ============================================================
# Test-RecentProjectsEnabled
# ============================================================
Describe 'Test-RecentProjectsEnabled' {

    It 'returns true when enabled=true and historyFile is set' {
        $config = [pscustomobject]@{
            recentProjects = [pscustomobject]@{ enabled = $true; historyFile = 'some\path.json' }
        }
        Test-RecentProjectsEnabled -Config $config | Should -BeTrue
    }

    It 'returns false when recentProjects is null' {
        $config = [pscustomobject]@{ recentProjects = $null }
        Test-RecentProjectsEnabled -Config $config | Should -BeFalse
    }

    It 'returns false when enabled is false' {
        $config = [pscustomobject]@{
            recentProjects = [pscustomobject]@{ enabled = $false; historyFile = 'some\path.json' }
        }
        Test-RecentProjectsEnabled -Config $config | Should -BeFalse
    }
}
