# ============================================================
# CronManager.Tests.ps1 - CronManager.psm1 unit tests
# Pester 5.x  /  Issue #182
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\CronManager.psm1') -Force
}

Describe 'Format-CronExpression' {

    It 'generates correct cron for a single weekday' {
        $result = Format-CronExpression -DayOfWeek @(1) -Time '21:00'
        $result | Should -Be '0 21 * * 1'
    }

    It 'generates correct cron for multiple weekdays' {
        $result = Format-CronExpression -DayOfWeek @(0, 6) -Time '09:30'
        $result | Should -Be '30 9 * * 0,6'
    }

    It 'zero-pads minute correctly (hour 8, minute 5)' {
        $result = Format-CronExpression -DayOfWeek @(2) -Time '08:05'
        $result | Should -Be '5 8 * * 2'
    }

    It 'sorts and deduplicates day-of-week values' {
        $result = Format-CronExpression -DayOfWeek @(5, 1, 3, 1) -Time '00:00'
        $result | Should -Be '0 0 * * 1,3,5'
    }

    It 'accepts boundary time 23:59' {
        $result = Format-CronExpression -DayOfWeek @(0) -Time '23:59'
        $result | Should -Be '59 23 * * 0'
    }

    It 'throws on invalid time format' {
        { Format-CronExpression -DayOfWeek @(1) -Time '9am' } | Should -Throw
    }

    It 'throws on hour out of range' {
        { Format-CronExpression -DayOfWeek @(1) -Time '24:00' } | Should -Throw
    }

    It 'throws on minute out of range' {
        { Format-CronExpression -DayOfWeek @(1) -Time '12:60' } | Should -Throw
    }

    It 'throws on day-of-week out of range' {
        { Format-CronExpression -DayOfWeek @(7) -Time '12:00' } | Should -Throw
    }

    It 'throws on negative day-of-week' {
        { Format-CronExpression -DayOfWeek @(-1) -Time '12:00' } | Should -Throw
    }
}

Describe 'Get-DayOfWeekLabel' {

    It 'returns correct label for Sunday (0)' {
        Get-DayOfWeekLabel -Dow 0 | Should -Be '日'
    }

    It 'returns correct label for Monday (1)' {
        Get-DayOfWeekLabel -Dow 1 | Should -Be '月'
    }

    It 'returns correct label for Saturday (6)' {
        Get-DayOfWeekLabel -Dow 6 | Should -Be '土'
    }

    It 'returns correct labels for all weekdays' {
        $expected = @('日', '月', '火', '水', '木', '金', '土')
        for ($i = 0; $i -le 6; $i++) {
            Get-DayOfWeekLabel -Dow $i | Should -Be $expected[$i]
        }
    }

    It 'returns question mark for out-of-range value' {
        Get-DayOfWeekLabel -Dow 7  | Should -Be '?'
        Get-DayOfWeekLabel -Dow -1 | Should -Be '?'
    }
}

Describe 'New-CronEntryId' {

    It 'returns an 8-character string' {
        $id = New-CronEntryId
        $id.Length | Should -Be 8
    }

    It 'returns only alphanumeric characters' {
        $id = New-CronEntryId
        $id | Should -Match '^[0-9a-f]{8}$'
    }

    It 'returns unique IDs on repeated calls' {
        $ids = 1..20 | ForEach-Object { New-CronEntryId }
        $unique = $ids | Select-Object -Unique
        $unique.Count | Should -Be 20
    }
}

Describe 'Format-CronEntryForDisplay' {

    BeforeAll {
        $script:SampleEntry = [pscustomobject]@{
            Id       = 'abcd1234'
            Project  = 'myproject'
            CronExpr = '30 21 * * 1,5'
            Duration = 300
            Created  = '2026-04-18T12:00:00'
        }
    }

    It 'includes the entry ID' {
        $result = Format-CronEntryForDisplay -Entry $script:SampleEntry
        $result | Should -Match 'abcd1234'
    }

    It 'includes the project name' {
        $result = Format-CronEntryForDisplay -Entry $script:SampleEntry
        $result | Should -Match 'myproject'
    }

    It 'includes the time formatted correctly' {
        $result = Format-CronEntryForDisplay -Entry $script:SampleEntry
        $result | Should -Match '21:30'
    }

    It 'includes the duration' {
        $result = Format-CronEntryForDisplay -Entry $script:SampleEntry
        $result | Should -Match 'duration=300m'
    }

    It 'includes the created timestamp' {
        $result = Format-CronEntryForDisplay -Entry $script:SampleEntry
        $result | Should -Match '2026-04-18T12:00:00'
    }
}

Describe 'Get-ClaudeOSCronEntry' {

    It 'returns empty array when crontab is empty' {
        Mock Invoke-RemoteCrontab { return '' } -ModuleName CronManager
        $result = Get-ClaudeOSCronEntry -LinuxHost 'testhost'
        $result | Should -HaveCount 0
    }

    It 'parses a single CLAUDEOS entry correctly' {
        $fakeCrontab = "# CLAUDEOS:abc12345 project=testproj duration=300 created=2026-04-01T00:00:00`n0 21 * * 1 /home/kensan/.claudeos/cron-launcher.sh testproj 300 >> /dev/null 2>&1`n"
        Mock Invoke-RemoteCrontab { return $fakeCrontab } -ModuleName CronManager

        $result = Get-ClaudeOSCronEntry -LinuxHost 'testhost'
        $result | Should -HaveCount 1
        $result[0].Id      | Should -Be 'abc12345'
        $result[0].Project | Should -Be 'testproj'
        $result[0].Duration | Should -Be 300
        $result[0].CronExpr | Should -Be '0 21 * * 1'
    }

    It 'parses multiple CLAUDEOS entries' {
        $fakeCrontab = "# CLAUDEOS:id000001 project=alpha duration=120 created=2026-04-01T00:00:00`n0 9 * * 1 /home/kensan/.claudeos/cron-launcher.sh alpha 120 >> /dev/null`n# CLAUDEOS:id000002 project=beta duration=60 created=2026-04-02T00:00:00`n30 18 * * 5 /home/kensan/.claudeos/cron-launcher.sh beta 60 >> /dev/null`n"
        Mock Invoke-RemoteCrontab { return $fakeCrontab } -ModuleName CronManager

        $result = Get-ClaudeOSCronEntry -LinuxHost 'testhost'
        $result | Should -HaveCount 2
        $result[0].Id | Should -Be 'id000001'
        $result[1].Id | Should -Be 'id000002'
    }

    It 'ignores non-CLAUDEOS cron lines' {
        $fakeCrontab = "# standard comment`n0 12 * * * /usr/bin/some-job`n# CLAUDEOS:myentry01 project=proj1 duration=300 created=2026-04-01T00:00:00`n0 21 * * 1 /home/kensan/.claudeos/cron-launcher.sh proj1 300 >> /dev/null`n"
        Mock Invoke-RemoteCrontab { return $fakeCrontab } -ModuleName CronManager

        $result = Get-ClaudeOSCronEntry -LinuxHost 'testhost'
        $result | Should -HaveCount 1
        $result[0].Id | Should -Be 'myentry01'
    }
}

Describe 'Get-LocalCronRegistry (P1-3)' {

    BeforeEach {
        # テスト用一時ディレクトリにレジストリパスを向ける（$TestDrive を先に変数に捕捉してからスコープに渡す）
        $tmpDir = Join-Path $TestDrive 'claudeos-registry'
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $tmpRegistry = Join-Path $tmpDir 'cron-registry.json'
        # 前回テストの残骸を削除
        Remove-Item $tmpRegistry -Force -ErrorAction SilentlyContinue
        # モジュールスコープ変数を差し替え
        InModuleScope CronManager -Parameters @{ RegPath = $tmpRegistry } {
            param($RegPath)
            $script:LocalRegistryPath = $RegPath
        }
    }

    It 'returns empty array when registry file does not exist' {
        $result = Get-LocalCronRegistry
        $result | Should -HaveCount 0
    }

    It 'returns entries written by Add-LocalCronRegistryEntry' {
        Add-LocalCronRegistryEntry -Id 'test001' -Project 'MyProj' -LinuxHost 'server1' `
            -DayOfWeek @(1, 3) -Time '21:00' -DurationMinutes 300

        $result = Get-LocalCronRegistry
        $result | Should -HaveCount 1
        $result[0].Project | Should -Be 'MyProj'
        $result[0].Id | Should -Be 'test001'
        $result[0].LinuxHost | Should -Be 'server1'
        $result[0].DurationMinutes | Should -Be 300
    }

    It 'Remove-LocalCronRegistryEntry removes the specified entry' {
        Add-LocalCronRegistryEntry -Id 'del001' -Project 'DelProj' -LinuxHost 'srv' `
            -DayOfWeek @(5) -Time '09:00' -DurationMinutes 120
        Add-LocalCronRegistryEntry -Id 'keep001' -Project 'KeepProj' -LinuxHost 'srv' `
            -DayOfWeek @(6) -Time '10:00' -DurationMinutes 60

        Remove-LocalCronRegistryEntry -Id 'del001'

        $result = Get-LocalCronRegistry
        $result | Should -HaveCount 1
        $result[0].Id | Should -Be 'keep001'
    }

    It 'Add-LocalCronRegistryEntry overwrites existing entry with same Id' {
        Add-LocalCronRegistryEntry -Id 'upd001' -Project 'OldName' -LinuxHost 'h' `
            -DayOfWeek @(1) -Time '08:00' -DurationMinutes 60
        Add-LocalCronRegistryEntry -Id 'upd001' -Project 'NewName' -LinuxHost 'h' `
            -DayOfWeek @(1) -Time '09:00' -DurationMinutes 120

        $result = Get-LocalCronRegistry
        $result | Should -HaveCount 1
        $result[0].Project | Should -Be 'NewName'
        $result[0].DurationMinutes | Should -Be 120
    }

    It 'Remove-LocalCronRegistryEntry on last entry writes empty array' {
        Add-LocalCronRegistryEntry -Id 'only001' -Project 'Solo' -LinuxHost 'h' `
            -DayOfWeek @(2) -Time '12:00' -DurationMinutes 300

        Remove-LocalCronRegistryEntry -Id 'only001'

        $result = Get-LocalCronRegistry
        $result | Should -HaveCount 0
    }

    It 'RegisteredAt is set automatically' {
        Add-LocalCronRegistryEntry -Id 'ts001' -Project 'TimeTest' -LinuxHost 'h' `
            -DayOfWeek @(1) -Time '00:00' -DurationMinutes 300

        $result = Get-LocalCronRegistry
        $result[0].RegisteredAt | Should -Not -BeNullOrEmpty
    }
}