# ============================================================
# ArchitectureCheck.Tests.ps1 - ArchitectureCheck.psm1 unit tests
# Pester 5.x  /  Phase 4 unit tests
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\lib\ArchitectureCheck.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Invoke-ArchitectureCheck' {

    Context '空ディレクトリ' {

        It 'CheckedFiles = 0 で Passed = true を返す' {
            $dir = Join-Path $TestDrive 'arch-empty'
            New-Item -ItemType Directory -Path $dir | Out-Null
            $result = Invoke-ArchitectureCheck -Path $dir
            $result.CheckedFiles    | Should -Be 0
            $result.TotalViolations | Should -Be 0
            $result.Passed          | Should -Be $true
        }
    }

    Context '結果オブジェクト構造' {

        It '必要なプロパティを持つ' {
            $dir = Join-Path $TestDrive 'arch-props'
            New-Item -ItemType Directory -Path $dir | Out-Null
            $result = Invoke-ArchitectureCheck -Path $dir
            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'CheckedFiles'
            $props | Should -Contain 'TotalViolations'
            $props | Should -Contain 'CriticalCount'
            $props | Should -Contain 'WarningCount'
            $props | Should -Contain 'Violations'
            $props | Should -Contain 'Passed'
        }
    }

    Context 'クリーンなファイル' {

        It 'Set-StrictMode あり / 違反なしで Passed = true' {
            $dir = Join-Path $TestDrive 'arch-clean'
            New-Item -ItemType Directory -Path $dir | Out-Null
            $content = "Set-StrictMode -Version Latest`nfunction Get-Something { return 'ok' }"
            Set-Content -Path (Join-Path $dir 'clean.ps1') -Value $content -Encoding UTF8
            $result = Invoke-ArchitectureCheck -Path $dir
            $result.Passed | Should -Be $true
        }
    }

    Context 'HARDCODED_SECRET ルール' {

        It 'パスワードハードコードを CRITICAL で検出する' {
            $dir = Join-Path $TestDrive 'arch-secret1'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'bad.ps1') `
                -Value '$password = "SuperSecret1234"' -Encoding UTF8 # gitleaks:allow
            $result = Invoke-ArchitectureCheck -Path $dir
            $result.Violations.RuleId | Should -Contain 'HARDCODED_SECRET'
        }

        It 'HARDCODED_SECRET の severity は CRITICAL' {
            $dir = Join-Path $TestDrive 'arch-secret2'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'bad.ps1') `
                -Value '$api_key = "sk-abcdef1234567890"' -Encoding UTF8 # gitleaks:allow
            $result = Invoke-ArchitectureCheck -Path $dir
            $v = $result.Violations | Where-Object { $_.RuleId -eq 'HARDCODED_SECRET' }
            $v.Severity | Should -Be 'CRITICAL'
        }

        It 'CRITICAL 検出時 Passed = false' {
            $dir = Join-Path $TestDrive 'arch-secret3'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'bad.ps1') `
                -Value '$token = "ghp_abc123xyz789"' -Encoding UTF8 # gitleaks:allow
            $result = Invoke-ArchitectureCheck -Path $dir
            $result.Passed | Should -Be $false
        }
    }

    Context 'DIRECT_PUSH_MAIN ルール' {

        It 'git push origin main を CRITICAL で検出する' {
            $dir = Join-Path $TestDrive 'arch-push'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'deploy.ps1') `
                -Value 'git push origin main' -Encoding UTF8
            $result = Invoke-ArchitectureCheck -Path $dir
            $result.Violations.RuleId | Should -Contain 'DIRECT_PUSH_MAIN'
        }
    }

    Context 'MISSING_STRICT_MODE ルール' {

        It 'Set-StrictMode なし .psm1 で WARNING を検出する' {
            $dir = Join-Path $TestDrive 'arch-nostrictmode'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'module.psm1') `
                -Value 'function Do-Something { return 1 }' -Encoding UTF8
            $result = Invoke-ArchitectureCheck -Path $dir
            $result.Violations.RuleId | Should -Contain 'MISSING_STRICT_MODE'
        }

        It 'MISSING_STRICT_MODE の severity は WARNING' {
            $dir = Join-Path $TestDrive 'arch-warn-sev'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'mod.psm1') `
                -Value 'function Foo { }' -Encoding UTF8
            $result = Invoke-ArchitectureCheck -Path $dir
            $v = $result.Violations | Where-Object { $_.RuleId -eq 'MISSING_STRICT_MODE' }
            $v.Severity | Should -Be 'WARNING'
        }

        It 'WARNING のみでは Passed = true のまま' {
            $dir = Join-Path $TestDrive 'arch-warn-pass'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'mod.psm1') `
                -Value 'function Bar { }' -Encoding UTF8
            $result = Invoke-ArchitectureCheck -Path $dir
            $result.Passed | Should -Be $true
        }
    }
}

Describe 'Get-ArchitectureViolation' {

    Context 'Severity フィルタリング' {

        BeforeAll {
            $script:FilterDir = Join-Path $TestDrive 'arch-filter'
            New-Item -ItemType Directory -Path $script:FilterDir | Out-Null
            # CRITICAL (HARDCODED_SECRET) + WARNING (MISSING_STRICT_MODE) 両方含むファイル
            Set-Content -Path (Join-Path $script:FilterDir 'mixed.psm1') `
                -Value '$secret = "hardcoded-password-123"' -Encoding UTF8 # gitleaks:allow
        }

        It 'Severity=CRITICAL で CRITICAL のみ返す' {
            $result = @(Get-ArchitectureViolation -Path $script:FilterDir -Severity 'CRITICAL')
            $result | Where-Object { $_.Severity -eq 'WARNING' } | Should -BeNullOrEmpty
        }

        It 'Severity=WARNING で WARNING のみ返す' {
            $result = @(Get-ArchitectureViolation -Path $script:FilterDir -Severity 'WARNING')
            $result | Where-Object { $_.Severity -eq 'CRITICAL' } | Should -BeNullOrEmpty
        }

        It 'Severity=ALL で全件返す' {
            $all      = @(Get-ArchitectureViolation -Path $script:FilterDir -Severity 'ALL')
            $critical = @(Get-ArchitectureViolation -Path $script:FilterDir -Severity 'CRITICAL')
            $warning  = @(Get-ArchitectureViolation -Path $script:FilterDir -Severity 'WARNING')
            $all.Count | Should -Be ($critical.Count + $warning.Count)
        }
    }
}
