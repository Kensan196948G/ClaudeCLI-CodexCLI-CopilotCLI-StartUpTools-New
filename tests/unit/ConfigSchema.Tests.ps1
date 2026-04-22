# ============================================================
# ConfigSchema.Tests.ps1 - ConfigSchema.ps1 unit tests
# Pester 5.x  /  Issue #232
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\lib\ConfigSchema.ps1'
    . $script:ScriptPath

    function Get-ValidConfig {
        [PSCustomObject]@{
            version        = '2.0.0'
            projectsDir    = 'D:\'
            sshProjectsDir = 'auto'
            projectsDirUnc = '\\192.168.0.1\Projects'
            linuxHost      = '192.168.0.1'
            linuxBase      = '/home/user/Projects'
            tools          = [PSCustomObject]@{
                defaultTool = 'claude'
                claude      = [PSCustomObject]@{
                    enabled        = $true
                    command        = 'claude'
                    args           = @('--dangerously-skip-permissions')
                    installCommand = 'npm install -g @anthropic-ai/claude-code'
                    env            = [PSCustomObject]@{}
                    apiKeyEnvVar   = 'ANTHROPIC_API_KEY'
                }
                codex       = [PSCustomObject]@{
                    enabled        = $true
                    command        = 'codex'
                    args           = @('--full-auto')
                    installCommand = 'npm install -g @openai/codex'
                    env            = [PSCustomObject]@{}
                    apiKeyEnvVar   = 'OPENAI_API_KEY'
                }
                copilot     = [PSCustomObject]@{
                    enabled        = $true
                    command        = 'copilot'
                    args           = @('--yolo')
                    installCommand = 'npm install -g @github/copilot'
                    env            = [PSCustomObject]@{}
                }
            }
        }
    }
}

# ============================================================
# Test-IntegerValueInRange
# ============================================================
Describe 'Test-IntegerValueInRange' {

    It 'returns false when value is null' {
        Test-IntegerValueInRange -Value $null -Minimum 1 | Should -BeFalse
    }

    It 'returns false when value is a non-numeric string' {
        Test-IntegerValueInRange -Value 'abc' -Minimum 1 | Should -BeFalse
    }

    It 'returns true when value equals minimum' {
        Test-IntegerValueInRange -Value 1 -Minimum 1 | Should -BeTrue
    }

    It 'returns false when value is below minimum' {
        Test-IntegerValueInRange -Value 0 -Minimum 1 | Should -BeFalse
    }

    It 'returns true when value equals maximum' {
        Test-IntegerValueInRange -Value 100 -Minimum 1 -Maximum 100 | Should -BeTrue
    }

    It 'returns false when value exceeds maximum' {
        Test-IntegerValueInRange -Value 101 -Minimum 1 -Maximum 100 | Should -BeFalse
    }

    It 'returns true for value within range' {
        Test-IntegerValueInRange -Value 50 -Minimum 1 -Maximum 100 | Should -BeTrue
    }

    It 'returns true when no maximum is specified and value meets minimum' {
        Test-IntegerValueInRange -Value 999999 -Minimum 1 | Should -BeTrue
    }
}

# ============================================================
# Test-StartupConfigSchema
# ============================================================
Describe 'Test-StartupConfigSchema' {

    Context 'valid config' {
        It 'returns no errors for a fully valid config' {
            $result = Test-StartupConfigSchema -Config (Get-ValidConfig)
            $result.Count | Should -Be 0
        }
    }

    Context 'required top-level fields' {
        It 'reports error when version is missing' {
            $cfg = Get-ValidConfig
            $cfg.version = $null
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain '必須フィールドが不足しています: version'
        }

        It 'reports error when linuxHost is empty string' {
            $cfg = Get-ValidConfig
            $cfg.linuxHost = ''
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain '必須フィールドが不足しています: linuxHost'
        }

        It 'reports error when projectsDir is whitespace only' {
            $cfg = Get-ValidConfig
            $cfg.projectsDir = '   '
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain '必須フィールドが不足しています: projectsDir'
        }

        It 'reports error when tools is null and returns immediately' {
            $cfg = Get-ValidConfig
            $cfg.tools = $null
            $result = Test-StartupConfigSchema -Config $cfg
            ($result | Where-Object { $_ -like '*tools*' }).Count | Should -BeGreaterThan 0
        }
    }

    Context 'tools.defaultTool validation' {
        It 'reports error when defaultTool is an unsupported value' {
            $cfg = Get-ValidConfig
            $cfg.tools.defaultTool = 'unsupported-tool'
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'tools.defaultTool は claude/codex/copilot のいずれかである必要があります'
        }

        It 'reports error when defaultTool is missing' {
            $cfg = Get-ValidConfig
            $cfg.tools.defaultTool = $null
            $result = Test-StartupConfigSchema -Config $cfg
            ($result | Where-Object { $_ -like '*defaultTool*' }).Count | Should -BeGreaterThan 0
        }

        It 'accepts codex as defaultTool' {
            $cfg = Get-ValidConfig
            $cfg.tools.defaultTool = 'codex'
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Not -Contain 'tools.defaultTool は claude/codex/copilot のいずれかである必要があります'
        }
    }

    Context 'tool-level field validation' {
        It 'reports error when tools.claude is missing' {
            $cfg = Get-ValidConfig
            $cfg.tools.claude = $null
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain '必須フィールドが不足しています: tools.claude'
        }

        It 'reports error when claude.enabled is not boolean' {
            $cfg = Get-ValidConfig
            $cfg.tools.claude.enabled = 'yes'
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'tools.claude.enabled は boolean である必要があります'
        }

        It 'reports error when claude.args is not an array' {
            $cfg = Get-ValidConfig
            $cfg.tools.claude.args = '--dangerously-skip-permissions'
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'tools.claude.args は配列である必要があります'
        }

        It 'reports error when claude.env is null' {
            $cfg = Get-ValidConfig
            $cfg.tools.claude.env = $null
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'tools.claude.env はオブジェクトである必要があります'
        }

        It 'reports error when claude.env is a plain string' {
            $cfg = Get-ValidConfig
            $cfg.tools.claude.env = 'KEY=VALUE'
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'tools.claude.env はオブジェクトである必要があります'
        }

        It 'reports error when claude.apiKeyEnvVar is not a string' {
            $cfg = Get-ValidConfig
            $cfg.tools.claude.apiKeyEnvVar = 123
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'tools.claude.apiKeyEnvVar は文字列である必要があります'
        }

        It 'does not require apiKeyEnvVar for copilot' {
            $cfg = Get-ValidConfig
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Not -Contain 'tools.copilot.apiKeyEnvVar は文字列である必要があります'
        }
    }

    Context 'optional localExcludes field' {
        It 'reports error when localExcludes is not an array' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'localExcludes' -NotePropertyValue 'single-string' -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'localExcludes は配列である必要があります'
        }

        It 'accepts null localExcludes without error' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'localExcludes' -NotePropertyValue $null -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Not -Contain 'localExcludes は配列である必要があります'
        }
    }

    Context 'optional recentProjects validation' {
        It 'reports error when recentProjects.enabled is not boolean' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'recentProjects' -NotePropertyValue ([PSCustomObject]@{
                enabled     = 'true'
                maxHistory  = 10
                historyFile = 'path.json'
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'recentProjects.enabled は boolean である必要があります'
        }

        It 'reports error when recentProjects.maxHistory is zero' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'recentProjects' -NotePropertyValue ([PSCustomObject]@{
                enabled     = $true
                maxHistory  = 0
                historyFile = 'path.json'
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'recentProjects.maxHistory は 1 以上の整数である必要があります'
        }
    }

    Context 'optional logging validation' {
        It 'reports error when logging.successKeepDays is out of range' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'logging' -NotePropertyValue ([PSCustomObject]@{
                enabled         = $true
                successKeepDays = 0
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'logging.successKeepDays は 1 から 3650 の整数である必要があります'
        }

        It 'reports error when logging.enabled is not boolean' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'logging' -NotePropertyValue ([PSCustomObject]@{
                enabled = 1
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'logging.enabled は boolean である必要があります'
        }
    }

    Context 'optional ssh validation' {
        It 'reports error when ssh.autoCleanup is not boolean' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'ssh' -NotePropertyValue ([PSCustomObject]@{
                autoCleanup = 'yes'
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'ssh.autoCleanup は boolean である必要があります'
        }

        It 'reports error when ssh.options is not an array' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'ssh' -NotePropertyValue ([PSCustomObject]@{
                options = '-t'
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'ssh.options は配列である必要があります'
        }
    }

    Context 'optional backupConfig validation' {
        It 'reports error when backupConfig.maxBackups exceeds 1000' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'backupConfig' -NotePropertyValue ([PSCustomObject]@{
                maxBackups = 1001
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'backupConfig.maxBackups は 1 から 1000 の整数である必要があります'
        }

        It 'reports error when backupConfig.sensitiveKeys is not an array' {
            $cfg = Get-ValidConfig
            $cfg | Add-Member -NotePropertyName 'backupConfig' -NotePropertyValue ([PSCustomObject]@{
                sensitiveKeys = 'single-key'
            }) -Force
            $result = Test-StartupConfigSchema -Config $cfg
            $result | Should -Contain 'backupConfig.sensitiveKeys は配列である必要があります'
        }
    }
}

# ============================================================
# Assert-StartupConfigSchema
# ============================================================
Describe 'Assert-StartupConfigSchema' {

    It 'throws when the config file does not exist' {
        { Assert-StartupConfigSchema -ConfigPath 'C:\nonexistent\config.json' } | Should -Throw
    }

    It 'throws when the file contains invalid JSON' {
        $tmpFile = Join-Path $TestDrive 'invalid.json'
        'NOT_JSON' | Set-Content -Path $tmpFile -Encoding UTF8
        { Assert-StartupConfigSchema -ConfigPath $tmpFile } | Should -Throw
    }

    It 'returns true for a valid config file' {
        $tmpFile = Join-Path $TestDrive 'valid-config.json'
        Get-ValidConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $tmpFile -Encoding UTF8
        $result = Assert-StartupConfigSchema -ConfigPath $tmpFile
        $result | Should -BeTrue
    }

    It 'throws with error message when config has schema violations' {
        $tmpFile = Join-Path $TestDrive 'invalid-config.json'
        '{"version":"2.0.0"}' | Set-Content -Path $tmpFile -Encoding UTF8
        { Assert-StartupConfigSchema -ConfigPath $tmpFile } | Should -Throw
    }
}
