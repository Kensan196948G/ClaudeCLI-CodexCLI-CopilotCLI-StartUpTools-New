# ============================================================
# ArchitectureCheck.Tests.ps1 - Pester tests for ArchitectureCheck module
# ============================================================

BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\scripts\lib\ArchitectureCheck.psm1'
    Import-Module $ModulePath -Force -DisableNameChecking
}

Describe 'ArchitectureCheck Module' {

    Describe 'Invoke-ArchitectureCheck' {
        It 'プロジェクトルートが存在する場合に結果を返す' {
            $result = Invoke-ArchitectureCheck -Path $PSScriptRoot
            $result | Should -Not -BeNullOrEmpty
            $result.CheckedFiles | Should -BeGreaterThan 0
            $result.PSObject.Properties.Name | Should -Contain 'Violations'
            $result.PSObject.Properties.Name | Should -Contain 'Passed'
        }

        It 'CriticalCount と WarningCount プロパティを持つ' {
            $result = Invoke-ArchitectureCheck -Path $PSScriptRoot
            $result.PSObject.Properties.Name | Should -Contain 'CriticalCount'
            $result.PSObject.Properties.Name | Should -Contain 'WarningCount'
        }

        It 'TotalViolations は CriticalCount + WarningCount と一致する' {
            $result = Invoke-ArchitectureCheck -Path $PSScriptRoot
            $result.TotalViolations | Should -Be ($result.CriticalCount + $result.WarningCount)
        }

        It 'Timestamp プロパティが含まれる' {
            $result = Invoke-ArchitectureCheck -Path $PSScriptRoot
            $result.Timestamp | Should -Not -BeNullOrEmpty
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'
        }

        It '存在しないパスに例外を投げる' {
            { Invoke-ArchitectureCheck -Path 'C:\nonexistent\path\xyz' } | Should -Throw
        }

        Context '一時ディレクトリでの違反検出テスト' {
            BeforeAll {
                $TempDir = Join-Path $env:TEMP "arch-check-test-$(Get-Random)"
                New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
            }
            AfterAll {
                Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            It 'ハードコード秘密情報を検出する' {
                $testFile = Join-Path $TempDir 'test-secret.ps1'
                'Set-StrictMode -Version Latest' | Set-Content $testFile
                # 文字列を分割して書き込み、テストファイル自体の誤検知を防ぐ
                ('$s' + 'ecret = "my-api-key-1234"') | Add-Content $testFile
                'Write-Host $secret' | Add-Content $testFile

                $result = Invoke-ArchitectureCheck -Path $TempDir
                $secretViolations = @($result.Violations | Where-Object { $_.RuleId -eq 'HARDCODED_SECRET' })
                $secretViolations | Should -Not -BeNullOrEmpty
            }

            It 'StrictMode未設定ファイルを検出する' {
                $testFile = Join-Path $TempDir 'no-strict.psm1'
                'function Test-Func { Write-Host "hello" }' | Set-Content $testFile
                'Export-ModuleMember -Function Test-Func' | Add-Content $testFile

                $result = Invoke-ArchitectureCheck -Path $TempDir
                $strictViolations = $result.Violations | Where-Object { $_.RuleId -eq 'MISSING_STRICT_MODE' }
                $strictViolations | Should -Not -BeNullOrEmpty
            }

            It '違反ゼロのクリーンなファイルはPassedになる' {
                $cleanFile = Join-Path $TempDir 'clean.ps1'
                'Set-StrictMode -Version Latest' | Set-Content $cleanFile
                'Write-Host "clean file"' | Add-Content $cleanFile

                $result = Invoke-ArchitectureCheck -Path $TempDir -Extensions @('.ps1')
                # StrictMode違反は .psm1 のみ対象なので、.ps1のみ確認
                $criticals = $result.Violations | Where-Object { $_.Severity -eq 'CRITICAL' -and $_.File -match 'clean' }
                $criticals | Should -BeNullOrEmpty
            }

            It 'Invoke-Expression の使用を警告として検出する' {
                $iexFile = Join-Path $TempDir 'iex-test.ps1'
                'Set-StrictMode -Version Latest' | Set-Content $iexFile
                'Invoke-Expression $userInput' | Add-Content $iexFile

                $result = Invoke-ArchitectureCheck -Path $TempDir -Extensions @('.ps1')
                $iexViolations = $result.Violations | Where-Object { $_.RuleId -eq 'MISSING_ERROR_HANDLING' }
                $iexViolations | Should -Not -BeNullOrEmpty
                $iexViolations[0].Severity | Should -Be 'WARNING'
            }
        }
    }

    Describe 'Get-ArchitectureViolation' {
        It 'Severity=ALL で全違反を返す' {
            $violations = Get-ArchitectureViolation -Path $PSScriptRoot -Severity ALL
            $violations | Should -Not -BeNullOrEmpty -Because "testsディレクトリには違反がある可能性がある"
        }

        It 'Severity=CRITICAL でCRITICALのみ返す' {
            $violations = Get-ArchitectureViolation -Path $PSScriptRoot -Severity CRITICAL
            foreach ($v in $violations) {
                $v.Severity | Should -Be 'CRITICAL'
            }
        }

        It 'Severity=WARNING でWARNINGのみ返す' {
            $violations = Get-ArchitectureViolation -Path $PSScriptRoot -Severity WARNING
            foreach ($v in $violations) {
                $v.Severity | Should -Be 'WARNING'
            }
        }
    }

    Describe 'Show-ArchitectureCheckReport' {
        It 'レポートを表示してresultオブジェクトを返す' {
            $result = Show-ArchitectureCheckReport -Path $PSScriptRoot
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Passed'
            $result.PSObject.Properties.Name | Should -Contain 'TotalViolations'
        }
    }

    Describe 'Test-ModuleDependency' {
        It 'プロジェクトルートでモジュール依存関係をチェックする' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $results = Test-ModuleDependency -Path $projectRoot
            $results | Should -Not -BeNullOrEmpty
        }

        It '結果にScript, Module, Status プロパティが含まれる' {
            $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $results = Test-ModuleDependency -Path $projectRoot
            if ($results.Count -gt 0) {
                $results[0].PSObject.Properties.Name | Should -Contain 'Script'
                $results[0].PSObject.Properties.Name | Should -Contain 'Module'
                $results[0].PSObject.Properties.Name | Should -Contain 'Status'
            }
        }
    }
}
