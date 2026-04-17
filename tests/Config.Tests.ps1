# ============================================================
# Config.Tests.ps1 - Config.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\Config.psm1" -Force
}

Describe 'Import-StartupConfig' {

    Context '有効な config.json を読み込む場合' {

        BeforeAll {
            $script:TempDir = Join-Path $TestDrive 'config'
            New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
            $script:ValidConfigPath = Join-Path $script:TempDir 'config.json'
            $validJson = @{
                version   = '2.0.0'
                linuxHost = 'testhost'
                linuxBase = '/home/kensan/Projects'
                tools     = @{
                    defaultTool = 'claude'
                    claude      = @{ enabled = $true; command = 'claude' }
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $script:ValidConfigPath -Value $validJson -Encoding UTF8
        }

        It '読み込んだオブジェクトが $null でないこと' {
            $result = Import-StartupConfig -ConfigPath $script:ValidConfigPath
            $result | Should -Not -BeNullOrEmpty
        }

        It 'linuxHost フィールドが正しく読み込まれること' {
            $result = Import-StartupConfig -ConfigPath $script:ValidConfigPath
            $result.linuxHost | Should -Be 'testhost'
        }

        It 'linuxBase フィールドが正しく読み込まれること' {
            $result = Import-StartupConfig -ConfigPath $script:ValidConfigPath
            $result.linuxBase | Should -Be '/home/kensan/Projects'
        }

        It 'tools.defaultTool が正しく読み込まれること' {
            $result = Import-StartupConfig -ConfigPath $script:ValidConfigPath
            $result.tools.defaultTool | Should -Be 'claude'
        }

        It 'tools.claude.enabled が true であること' {
            $result = Import-StartupConfig -ConfigPath $script:ValidConfigPath
            $result.tools.claude.enabled | Should -Be $true
        }
    }

    Context 'ファイルが存在しない場合' {

        It '例外をスローすること' {
            { Import-StartupConfig -ConfigPath 'C:\nonexistent\config.json' } |
                Should -Throw -ExceptionType ([System.Exception])
        }
    }

    Context '必須フィールドが欠けている場合' {

        It 'version が欠けている場合に例外をスローすること' {
            $tempPath = Join-Path $TestDrive 'missing-version.json'
            @{ linuxHost = 'host'; tools = @{ defaultTool = 'claude' } } |
                ConvertTo-Json | Set-Content $tempPath
            { Import-StartupConfig -ConfigPath $tempPath } | Should -Throw
        }

        It 'linuxHost が欠けている場合に例外をスローすること' {
            $tempPath = Join-Path $TestDrive 'missing-host.json'
            @{ version = '2.0.0'; tools = @{ defaultTool = 'claude' } } |
                ConvertTo-Json | Set-Content $tempPath
            { Import-StartupConfig -ConfigPath $tempPath } | Should -Throw
        }

        It 'tools が欠けている場合に例外をスローすること' {
            $tempPath = Join-Path $TestDrive 'missing-tools.json'
            @{ version = '2.0.0'; linuxHost = 'host' } |
                ConvertTo-Json | Set-Content $tempPath
            { Import-StartupConfig -ConfigPath $tempPath } | Should -Throw
        }
    }

    Context '後方互換エイリアス' {

        BeforeAll {
            $script:TempDir2 = Join-Path $TestDrive 'config2'
            New-Item -ItemType Directory -Path $script:TempDir2 -Force | Out-Null
            $script:AliasConfigPath = Join-Path $script:TempDir2 'config.json'
            $validJson = @{
                version   = '2.0.0'
                linuxHost = 'alias-testhost'
                linuxBase = '/home/kensan/Projects'
                tools     = @{ defaultTool = 'claude'; claude = @{ enabled = $true } }
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $script:AliasConfigPath -Value $validJson -Encoding UTF8
        }

        It 'Import-DevToolsConfig エイリアスが動作すること' {
            $result = Import-DevToolsConfig -ConfigPath $script:AliasConfigPath
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Backup-ConfigFile' {

    Context 'バックアップが正常に作成される場合' {

        BeforeAll {
            $script:BackupTempDir = Join-Path $TestDrive 'backup_test'
            New-Item -ItemType Directory -Path $script:BackupTempDir -Force | Out-Null
            $script:SourceConfig = Join-Path $script:BackupTempDir 'config.json'
            $script:BackupDir = Join-Path $script:BackupTempDir 'backups'
            @{ version = '2.0.0'; linuxHost = 'host'; tools = @{} } |
                ConvertTo-Json | Set-Content $script:SourceConfig -Encoding UTF8
        }

        It 'バックアップファイルが作成されること' {
            Backup-ConfigFile -ConfigPath $script:SourceConfig -BackupDir $script:BackupDir
            $backups = Get-ChildItem $script:BackupDir -Filter '*.json' -ErrorAction SilentlyContinue
            $backups.Count | Should -BeGreaterThan 0
        }
    }

    Context 'ファイルが存在しない場合' {

        It '警告を出力してエラーにならないこと' {
            { Backup-ConfigFile -ConfigPath 'C:\nonexistent.json' -BackupDir $TestDrive } |
                Should -Not -Throw
        }
    }
}

Describe 'Test-StartupConfigSchema and Assert-StartupConfigSchema' {

    Context 'template 相当の設定を検証する場合' {

        It '必要なキーが揃っていればエラーなしで通ること' {
            $config = @{
                version        = '2.0.0'
                projectsDir    = 'X:\'
                sshProjectsDir = 'Z:\'
                projectsDirUnc = '\\server\share'
                linuxHost      = 'host'
                linuxBase      = '/home/kensan/Projects'
                tools          = @{
                    defaultTool = 'claude'
                    claude      = @{
                        enabled        = $true
                        command        = 'claude'
                        args           = @()
                        installCommand = 'install-claude'
                        env            = @{}
                        apiKeyEnvVar   = 'ANTHROPIC_API_KEY'
                    }
                    codex       = @{
                        enabled        = $true
                        command        = 'codex'
                        args           = @()
                        installCommand = 'install-codex'
                        env            = @{ OPENAI_API_KEY = '' }
                        apiKeyEnvVar   = 'OPENAI_API_KEY'
                    }
                    copilot     = @{
                        enabled        = $true
                        command        = 'copilot'
                        args           = @('--yolo')
                        installCommand = 'install-copilot'
                        env            = @{}
                    }
                }
            }

            $errors = Test-StartupConfigSchema -Config $config
            $errors | Should -BeNullOrEmpty
        }

        It 'Assert-StartupConfigSchema が template 相当ファイルを受け入れること' {
            $configPath = Join-Path $TestDrive 'template-config.json'
            $config = @{
                version        = '2.0.0'
                projectsDir    = 'X:\'
                sshProjectsDir = 'Z:\'
                projectsDirUnc = '\\server\share'
                linuxHost      = 'host'
                linuxBase      = '/home/kensan/Projects'
                tools          = @{
                    defaultTool = 'claude'
                    claude      = @{
                        enabled        = $true
                        command        = 'claude'
                        args           = @()
                        installCommand = 'install-claude'
                        env            = @{}
                        apiKeyEnvVar   = 'ANTHROPIC_API_KEY'
                    }
                    codex       = @{
                        enabled        = $true
                        command        = 'codex'
                        args           = @()
                        installCommand = 'install-codex'
                        env            = @{ OPENAI_API_KEY = '' }
                        apiKeyEnvVar   = 'OPENAI_API_KEY'
                    }
                    copilot     = @{
                        enabled        = $true
                        command        = 'copilot'
                        args           = @('--yolo')
                        installCommand = 'install-copilot'
                        env            = @{}
                    }
                }
            } | ConvertTo-Json -Depth 10

            Set-Content -Path $configPath -Value $config -Encoding UTF8
            { Assert-StartupConfigSchema -ConfigPath $configPath } | Should -Not -Throw
        }

        It '必要キーが不足していればエラーを返すこと' {
            $config = @{
                version = '2.0.0'
                tools   = @{
                    defaultTool = 'claude'
                }
            }

            $errors = Test-StartupConfigSchema -Config $config
            $errors | Should -Not -BeNullOrEmpty
            ($errors -join "`n") | Should -Match 'projectsDir'
        }

        It 'defaultTool の値域が不正ならエラーを返すこと' {
            $config = @{
                version        = '2.0.0'
                projectsDir    = 'X:\'
                sshProjectsDir = 'Z:\'
                projectsDirUnc = '\\server\share'
                linuxHost      = 'host'
                linuxBase      = '/home/kensan/Projects'
                tools          = @{
                    defaultTool = 'invalid'
                    claude      = @{
                        enabled        = $true
                        command        = 'claude'
                        args           = @()
                        installCommand = 'install-claude'
                        env            = @{}
                        apiKeyEnvVar   = 'ANTHROPIC_API_KEY'
                    }
                    codex       = @{
                        enabled        = $true
                        command        = 'codex'
                        args           = @()
                        installCommand = 'install-codex'
                        env            = @{ OPENAI_API_KEY = '' }
                        apiKeyEnvVar   = 'OPENAI_API_KEY'
                    }
                    copilot     = @{
                        enabled        = $true
                        command        = 'copilot'
                        args           = @('--yolo')
                        installCommand = 'install-copilot'
                        env            = @{}
                    }
                }
                recentProjects = @{
                    enabled = $true
                    maxHistory = 10
                    historyFile = '%USERPROFILE%\\.ai-startup\\recent.json'
                }
            }

            $errors = Test-StartupConfigSchema -Config $config
            ($errors -join "`n") | Should -Match 'defaultTool'
        }

        It 'recentProjects.maxHistory が不正ならエラーを返すこと' {
            $config = @{
                version        = '2.0.0'
                projectsDir    = 'X:\'
                sshProjectsDir = 'Z:\'
                projectsDirUnc = '\\server\share'
                linuxHost      = 'host'
                linuxBase      = '/home/kensan/Projects'
                tools          = @{
                    defaultTool = 'claude'
                    claude      = @{
                        enabled        = $true
                        command        = 'claude'
                        args           = @()
                        installCommand = 'install-claude'
                        env            = @{}
                        apiKeyEnvVar   = 'ANTHROPIC_API_KEY'
                    }
                    codex       = @{
                        enabled        = $true
                        command        = 'codex'
                        args           = @()
                        installCommand = 'install-codex'
                        env            = @{ OPENAI_API_KEY = '' }
                        apiKeyEnvVar   = 'OPENAI_API_KEY'
                    }
                    copilot     = @{
                        enabled        = $true
                        command        = 'copilot'
                        args           = @('--yolo')
                        installCommand = 'install-copilot'
                        env            = @{}
                    }
                }
                recentProjects = @{
                    enabled = $true
                    maxHistory = 0
                    historyFile = '%USERPROFILE%\\.ai-startup\\recent.json'
                }
            }

            $errors = Test-StartupConfigSchema -Config $config
            ($errors -join "`n") | Should -Match 'recentProjects.maxHistory'
        }

        It 'logging.successKeepDays が不正ならエラーを返すこと' {
            $config = @{
                version        = '2.0.0'
                projectsDir    = 'X:\'
                sshProjectsDir = 'Z:\'
                projectsDirUnc = '\\server\share'
                linuxHost      = 'host'
                linuxBase      = '/home/kensan/Projects'
                tools          = @{
                    defaultTool = 'claude'
                    claude      = @{ enabled = $true; command = 'claude'; args = @(); installCommand = 'install-claude'; env = @{}; apiKeyEnvVar = 'ANTHROPIC_API_KEY' }
                    codex       = @{ enabled = $true; command = 'codex'; args = @(); installCommand = 'install-codex'; env = @{ OPENAI_API_KEY = '' }; apiKeyEnvVar = 'OPENAI_API_KEY' }
                    copilot     = @{ enabled = $true; command = 'copilot'; args = @('--yolo'); installCommand = 'install-copilot'; env = @{} }
                }
                logging = @{
                    enabled = $true
                    successKeepDays = 0
                    failureKeepDays = 90
                }
            }

            $errors = Test-StartupConfigSchema -Config $config
            ($errors -join "`n") | Should -Match 'logging.successKeepDays'
        }

        It 'backupConfig.maxBackups が不正ならエラーを返すこと' {
            $config = @{
                version        = '2.0.0'
                projectsDir    = 'X:\'
                sshProjectsDir = 'Z:\'
                projectsDirUnc = '\\server\share'
                linuxHost      = 'host'
                linuxBase      = '/home/kensan/Projects'
                tools          = @{
                    defaultTool = 'claude'
                    claude      = @{ enabled = $true; command = 'claude'; args = @(); installCommand = 'install-claude'; env = @{}; apiKeyEnvVar = 'ANTHROPIC_API_KEY' }
                    codex       = @{ enabled = $true; command = 'codex'; args = @(); installCommand = 'install-codex'; env = @{ OPENAI_API_KEY = '' }; apiKeyEnvVar = 'OPENAI_API_KEY' }
                    copilot     = @{ enabled = $true; command = 'copilot'; args = @('--yolo'); installCommand = 'install-copilot'; env = @{} }
                }
                backupConfig = @{
                    enabled = $true
                    backupDir = 'config/backups'
                    maxBackups = 0
                    maskSensitive = $true
                    sensitiveKeys = @()
                }
            }

            $errors = Test-StartupConfigSchema -Config $config
            ($errors -join "`n") | Should -Match 'backupConfig.maxBackups'
        }
    }
}

Describe 'Get-RecentProject and Update-RecentProject' {

    Context '履歴ファイルが存在しない場合' {

        It 'Get-RecentProject が空配列を返すこと' {
            $result = Get-RecentProject -HistoryPath (Join-Path $TestDrive 'nonexistent.json')
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Update-RecentProject のテスト' {

        BeforeAll {
            $script:HistoryPath = Join-Path $TestDrive 'recent.json'
        }

        BeforeEach {
            Remove-Item $script:HistoryPath -Force -ErrorAction SilentlyContinue
        }

        It 'プロジェクトが追加されること' {
            Update-RecentProject -ProjectName 'TestProject' -Tool 'claude' -Mode 'local' -Result 'success' -ElapsedMs 100 -HistoryPath $script:HistoryPath
            $result = Get-RecentProject -HistoryPath $script:HistoryPath
            $result.project | Should -Contain 'TestProject'
            $result[0].tool | Should -Be 'claude'
            $result[0].mode | Should -Be 'local'
            $result[0].result | Should -Be 'success'
            $result[0].elapsedMs | Should -Be 100
            $result[0].timestamp | Should -Not -BeNullOrEmpty
        }

        It '重複が削除されること' {
            Update-RecentProject -ProjectName 'TestProject' -Tool 'codex' -Mode 'ssh' -HistoryPath $script:HistoryPath
            Update-RecentProject -ProjectName 'TestProject' -Tool 'codex' -Mode 'ssh' -HistoryPath $script:HistoryPath
            $result = Get-RecentProject -HistoryPath $script:HistoryPath
            ($result | Where-Object { $_.project -eq 'TestProject' }).Count | Should -Be 1
        }

        It 'MaxHistory を超えた場合に古いエントリが削除されること' {
            1..12 | ForEach-Object {
                Update-RecentProject -ProjectName "Project$_" -Tool 'claude' -Mode 'ssh' -HistoryPath $script:HistoryPath -MaxHistory 3
            }
            $result = Get-RecentProject -HistoryPath $script:HistoryPath
            $result.Count | Should -BeLessOrEqual 3
        }

        It '旧形式の文字列配列も正規化して読み込めること' {
            $legacyPath = Join-Path $TestDrive 'recent-legacy.json'
            @{ projects = @('LegacyProject') } | ConvertTo-Json -Depth 5 | Set-Content -Path $legacyPath -Encoding UTF8
            $result = Get-RecentProject -HistoryPath $legacyPath
            $result[0].project | Should -Be 'LegacyProject'
            $result[0].tool | Should -BeNullOrEmpty
            $result[0].mode | Should -BeNullOrEmpty
        }
    }
}
