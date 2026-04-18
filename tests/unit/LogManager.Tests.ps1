# ============================================================
# LogManager.Tests.ps1 - LogManager.psm1 unit tests
# Pester 5.x  /  Issue #182
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\LogManager.psm1') -Force

    function script:New-TestLogConfig {
        param(
            [string]$LogDir,
            [string]$Prefix = 'testlog',
            [int]$SuccessKeepDays  = 30,
            [int]$FailureKeepDays  = 90,
            [int]$LegacyKeepDays   = 7,
            [int]$ArchiveAfterDays = 60
        )
        return [pscustomobject]@{
            logging = [pscustomobject]@{
                enabled           = $true
                logDir            = $LogDir
                logPrefix         = $Prefix
                successKeepDays   = $SuccessKeepDays
                failureKeepDays   = $FailureKeepDays
                legacyKeepDays    = $LegacyKeepDays
                archiveAfterDays  = $ArchiveAfterDays
            }
        }
    }
}

Describe 'Get-LogSummary' {

    It 'returns zero counts when log directory is empty' {
        $logDir = Join-Path $TestDrive 'empty-logs'
        New-Item -ItemType Directory -Path $logDir | Out-Null
        $cfg = New-TestLogConfig -LogDir $logDir

        $summary = Get-LogSummary -Config $cfg
        $summary.TotalFiles   | Should -Be 0
        $summary.SuccessCount | Should -Be 0
        $summary.FailureCount | Should -Be 0
    }

    It 'returns zero counts when log directory does not exist' {
        $cfg = New-TestLogConfig -LogDir (Join-Path $TestDrive 'nonexistent')

        $summary = Get-LogSummary -Config $cfg
        $summary.TotalFiles | Should -Be 0
    }

    It 'counts SUCCESS, FAILURE, and legacy files separately' {
        $logDir = Join-Path $TestDrive 'mixed-logs'
        New-Item -ItemType Directory -Path $logDir | Out-Null

        'x' | Set-Content (Join-Path $logDir 'testlog-proj-SUCCESS.log')
        'x' | Set-Content (Join-Path $logDir 'testlog-proj-FAILURE.log')
        'x' | Set-Content (Join-Path $logDir 'testlog-proj-legacy.log')

        $cfg = New-TestLogConfig -LogDir $logDir

        $summary = Get-LogSummary -Config $cfg
        $summary.TotalFiles   | Should -Be 3
        $summary.SuccessCount | Should -Be 1
        $summary.FailureCount | Should -Be 1
        $summary.LegacyCount  | Should -Be 1
    }

    It 'sums total size correctly' {
        $logDir = Join-Path $TestDrive 'size-logs'
        New-Item -ItemType Directory -Path $logDir | Out-Null

        [System.IO.File]::WriteAllBytes((Join-Path $logDir 'testlog-a-SUCCESS.log'), [byte[]]@(1,2,3,4,5))
        [System.IO.File]::WriteAllBytes((Join-Path $logDir 'testlog-b-SUCCESS.log'), [byte[]]@(1,2,3,4,5,6,7,8,9,10))

        $cfg = New-TestLogConfig -LogDir $logDir

        $summary = Get-LogSummary -Config $cfg
        $summary.TotalSizeBytes | Should -Be 15
    }

    It 'sets OldestLog and NewestLog based on LastWriteTime' {
        $logDir = Join-Path $TestDrive 'date-logs'
        New-Item -ItemType Directory -Path $logDir | Out-Null

        $old = Join-Path $logDir 'testlog-old-SUCCESS.log'
        $new = Join-Path $logDir 'testlog-new-SUCCESS.log'
        'x' | Set-Content $old
        'x' | Set-Content $new

        (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-10)
        (Get-Item $new).LastWriteTime = (Get-Date).AddDays(-1)

        $cfg = New-TestLogConfig -LogDir $logDir

        $summary = Get-LogSummary -Config $cfg
        $summary.OldestLog | Should -Be 'testlog-old-SUCCESS.log'
        $summary.NewestLog | Should -Be 'testlog-new-SUCCESS.log'
    }

    It 'returns zero counts when logging config is null' {
        $cfg = [pscustomobject]@{ logging = $null }
        $summary = Get-LogSummary -Config $cfg
        $summary.TotalFiles | Should -Be 0
    }
}

Describe 'Invoke-LogRotation' {

    It 'deletes SUCCESS logs older than successKeepDays' {
        $logDir = Join-Path $TestDrive 'rotate-success'
        New-Item -ItemType Directory -Path $logDir | Out-Null

        $old    = Join-Path $logDir 'testlog-proj-SUCCESS.log'
        $recent = Join-Path $logDir 'testlog-proj2-SUCCESS.log'
        'x' | Set-Content $old
        'x' | Set-Content $recent

        (Get-Item $old).LastWriteTime    = (Get-Date).AddDays(-31)
        (Get-Item $recent).LastWriteTime = (Get-Date).AddDays(-1)

        $cfg = New-TestLogConfig -LogDir $logDir -SuccessKeepDays 30

        Invoke-LogRotation -Config $cfg

        (Test-Path $old)    | Should -Be $false
        (Test-Path $recent) | Should -Be $true
    }

    It 'deletes FAILURE logs older than failureKeepDays' {
        $logDir = Join-Path $TestDrive 'rotate-failure'
        New-Item -ItemType Directory -Path $logDir | Out-Null

        $old    = Join-Path $logDir 'testlog-proj-FAILURE.log'
        $recent = Join-Path $logDir 'testlog-proj2-FAILURE.log'
        'x' | Set-Content $old
        'x' | Set-Content $recent

        (Get-Item $old).LastWriteTime    = (Get-Date).AddDays(-91)
        (Get-Item $recent).LastWriteTime = (Get-Date).AddDays(-1)

        $cfg = New-TestLogConfig -LogDir $logDir -FailureKeepDays 90

        Invoke-LogRotation -Config $cfg

        (Test-Path $old)    | Should -Be $false
        (Test-Path $recent) | Should -Be $true
    }

    It 'deletes legacy logs older than legacyKeepDays' {
        $logDir = Join-Path $TestDrive 'rotate-legacy'
        New-Item -ItemType Directory -Path $logDir | Out-Null

        $old    = Join-Path $logDir 'testlog-proj-legacy.log'
        $recent = Join-Path $logDir 'testlog-proj2-legacy.log'
        'x' | Set-Content $old
        'x' | Set-Content $recent

        (Get-Item $old).LastWriteTime    = (Get-Date).AddDays(-8)
        (Get-Item $recent).LastWriteTime = (Get-Date).AddDays(-1)

        $cfg = New-TestLogConfig -LogDir $logDir -LegacyKeepDays 7

        Invoke-LogRotation -Config $cfg

        (Test-Path $old)    | Should -Be $false
        (Test-Path $recent) | Should -Be $true
    }

    It 'does nothing when logging is disabled' {
        $logDir = Join-Path $TestDrive 'rotate-disabled'
        New-Item -ItemType Directory -Path $logDir | Out-Null

        $file = Join-Path $logDir 'testlog-old-SUCCESS.log'
        'x' | Set-Content $file
        (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-100)

        $cfg = [pscustomobject]@{
            logging = [pscustomobject]@{ enabled = $false; logDir = $logDir; logPrefix = 'testlog' }
        }

        Invoke-LogRotation -Config $cfg

        (Test-Path $file) | Should -Be $true
    }

    It 'does nothing when log directory does not exist' {
        $cfg = New-TestLogConfig -LogDir (Join-Path $TestDrive 'nonexistent-rotate')
        { Invoke-LogRotation -Config $cfg } | Should -Not -Throw
    }
}