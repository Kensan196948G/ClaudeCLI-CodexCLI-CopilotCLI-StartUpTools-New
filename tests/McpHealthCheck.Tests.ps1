# ============================================================
# McpHealthCheck.Tests.ps1 - McpHealthCheck.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\McpHealthCheck.psm1') -Force

    $script:OriginalMcpConfigPath = $env:AI_STARTUP_MCP_CONFIG_PATH
    $script:OriginalRuntimeProbe = $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE
    $script:OriginalHealthTimeout = $env:AI_STARTUP_MCP_HEALTH_TIMEOUT_SEC
    $script:OriginalStartupTimeout = $env:AI_STARTUP_MCP_STARTUP_TIMEOUT_SEC
    $script:OriginalShutdownTimeout = $env:AI_STARTUP_MCP_SHUTDOWN_TIMEOUT_SEC
}

AfterAll {
    $env:AI_STARTUP_MCP_CONFIG_PATH = $script:OriginalMcpConfigPath
    $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE = $script:OriginalRuntimeProbe
    $env:AI_STARTUP_MCP_HEALTH_TIMEOUT_SEC = $script:OriginalHealthTimeout
    $env:AI_STARTUP_MCP_STARTUP_TIMEOUT_SEC = $script:OriginalStartupTimeout
    $env:AI_STARTUP_MCP_SHUTDOWN_TIMEOUT_SEC = $script:OriginalShutdownTimeout
}

Describe 'Test-McpCommandExists' {

    Context 'コマンドが存在する場合' {
        It '$true を返すこと' {
            $result = Test-McpCommandExists -Command 'cmd'
            $result | Should -Be $true
        }
    }

    Context 'コマンドが存在しない場合' {
        It '$false を返すこと' {
            $result = Test-McpCommandExists -Command 'nonexistent-command-xyz-12345'
            $result | Should -Be $false
        }
    }
}

Describe 'Get-McpServerHealth' {

    Context '基本的なサーバー定義の場合' {
        It 'コマンドが見つかるサーバーは available を返すこと' {
            $definition = [pscustomobject]@{
                command = 'cmd'
                args    = @('/c', 'echo', 'test')
            }

            $result = Get-McpServerHealth -Name 'test-server' -Definition $definition
            $result.name | Should -Be 'test-server'
            $result.command | Should -Be 'cmd'
            $result.commandExists | Should -Be $true
            $result.configured | Should -Be $true
            $result.status | Should -Be 'available'
        }

        It 'コマンドが見つからないサーバーは unavailable を返すこと' {
            $definition = [pscustomobject]@{
                command = 'nonexistent-mcp-server-xyz'
                args    = @()
            }

            $result = Get-McpServerHealth -Name 'missing-server' -Definition $definition
            $result.name | Should -Be 'missing-server'
            $result.commandExists | Should -Be $false
            $result.status | Should -Be 'unavailable'
            $result.note | Should -Match 'not found'
        }
    }

    Context 'command プロパティが空の場合' {
        It 'unavailable を返すこと' {
            $definition = [pscustomobject]@{
                command = ''
                args    = @()
            }

            $result = Get-McpServerHealth -Name 'empty-cmd' -Definition $definition
            $result.commandExists | Should -Be $false
            $result.status | Should -Be 'unavailable'
        }
    }

    Context 'healthCommand が定義されていない場合' {
        It 'healthStatus が not_configured であること' {
            $definition = [pscustomobject]@{
                command = 'cmd'
                args    = @()
            }

            $result = Get-McpServerHealth -Name 'no-health' -Definition $definition
            $result.healthStatus | Should -Be 'not_configured'
            $result.healthCommand.Count | Should -Be 0
        }
    }

    Context 'memory サーバーの場合' {
        It 'kind が memory であること' {
            $definition = [pscustomobject]@{
                command = 'cmd'
                args    = @()
            }

            $result = Get-McpServerHealth -Name 'memory' -Definition $definition
            $result.kind | Should -Be 'memory'
        }
    }

    Context '外部サーバーの場合' {
        It 'kind が external であること' {
            $definition = [pscustomobject]@{
                command = 'cmd'
                args    = @()
            }

            $result = Get-McpServerHealth -Name 'github' -Definition $definition
            $result.kind | Should -Be 'external'
        }
    }

    Context 'タイムアウト設定のオーバーライド' {

        BeforeEach {
            $env:AI_STARTUP_MCP_HEALTH_TIMEOUT_SEC = $null
            $env:AI_STARTUP_MCP_STARTUP_TIMEOUT_SEC = $null
            $env:AI_STARTUP_MCP_SHUTDOWN_TIMEOUT_SEC = $null
        }

        It 'デフォルトタイムアウトが適用されること' {
            $definition = [pscustomobject]@{
                command = 'cmd'
                args    = @()
            }

            $result = Get-McpServerHealth -Name 'timeout-test' -Definition $definition
            $result.healthCommandTimeoutSec | Should -Be 5
            $result.startupCommandTimeoutSec | Should -Be 10
            $result.shutdownCommandTimeoutSec | Should -Be 10
        }

        It '環境変数でタイムアウトを上書きできること' {
            $env:AI_STARTUP_MCP_HEALTH_TIMEOUT_SEC = '15'

            $definition = [pscustomobject]@{
                command = 'cmd'
                args    = @()
            }

            $result = Get-McpServerHealth -Name 'env-timeout' -Definition $definition
            $result.healthCommandTimeoutSec | Should -Be 15
        }

        It 'Definition 内のタイムアウトが環境変数より優先されること' {
            $env:AI_STARTUP_MCP_HEALTH_TIMEOUT_SEC = '15'

            $definition = [pscustomobject]@{
                command                = 'cmd'
                args                   = @()
                healthCommandTimeoutSec = 3
            }

            $result = Get-McpServerHealth -Name 'def-timeout' -Definition $definition
            $result.healthCommandTimeoutSec | Should -Be 3
        }
    }

    Context 'operatingProcedure の構造' {
        It 'startup/health/shutdown フィールドを持つこと' {
            $definition = [pscustomobject]@{
                command        = 'cmd'
                args           = @()
                startupCommand = @('cmd', '/c', 'echo', 'start')
                healthCommand  = @('cmd', '/c', 'echo', 'health')
                shutdownCommand = @('cmd', '/c', 'echo', 'stop')
            }

            $result = Get-McpServerHealth -Name 'op-test' -Definition $definition
            $result.operatingProcedure.startup | Should -Not -BeNullOrEmpty
            $result.operatingProcedure.health | Should -Not -BeNullOrEmpty
            $result.operatingProcedure.shutdown | Should -Not -BeNullOrEmpty
        }
    }

    Context 'runtime probe が無効の場合' {

        BeforeEach {
            $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE = '0'
        }

        It 'startupStatus が not_requested であること' {
            $definition = [pscustomobject]@{
                command        = 'cmd'
                args           = @()
                startupCommand = @('cmd', '/c', 'echo', 'start')
            }

            $result = Get-McpServerHealth -Name 'probe-off' -Definition $definition
            $result.startupStatus | Should -Be 'not_requested'
            $result.shutdownStatus | Should -Be 'not_requested'
        }
    }
}

Describe 'Get-McpHealthReport' {

    Context '.mcp.json が存在しない場合' {
        It 'configured が $false であること' {
            $env:AI_STARTUP_MCP_CONFIG_PATH = Join-Path $TestDrive 'nonexistent.json'

            $result = Get-McpHealthReport -ProjectRoot $TestDrive
            $result.configured | Should -Be $false
            $result.summary | Should -Be 'MCP 設定なし'
            $result.servers.Count | Should -Be 0
        }
    }

    Context '有効な .mcp.json が存在する場合' {

        BeforeAll {
            $script:McpConfigDir = $TestDrive
            $script:McpConfigPath = Join-Path $script:McpConfigDir '.mcp.json'

            $mcpConfig = @{
                mcpServers = @{
                    github = @{
                        command = 'cmd'
                        args    = @('/c', 'echo', 'github')
                    }
                    memory = @{
                        command = 'cmd'
                        args    = @('/c', 'echo', 'memory')
                    }
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $script:McpConfigPath -Value $mcpConfig -Encoding UTF8
        }

        BeforeEach {
            $env:AI_STARTUP_MCP_CONFIG_PATH = $null
        }

        It 'configured が $true であること' {
            $result = Get-McpHealthReport -ProjectRoot $script:McpConfigDir
            $result.configured | Should -Be $true
        }

        It 'サーバー数が正しいこと' {
            $result = Get-McpHealthReport -ProjectRoot $script:McpConfigDir
            @($result.servers).Count | Should -Be 2
        }

        It 'connections 配列がサーバー数と一致すること' {
            $result = Get-McpHealthReport -ProjectRoot $script:McpConfigDir
            @($result.connections).Count | Should -Be 2
        }

        It 'summary にサーバー数が含まれること' {
            $result = Get-McpHealthReport -ProjectRoot $script:McpConfigDir
            $result.summary | Should -Match '2 server'
        }

        It 'github サーバーの kind が external であること' {
            $result = Get-McpHealthReport -ProjectRoot $script:McpConfigDir
            $githubServer = @($result.servers) | Where-Object { $_.name -eq 'github' }
            $githubServer.kind | Should -Be 'external'
        }

        It 'memory サーバーの kind が memory であること' {
            $result = Get-McpHealthReport -ProjectRoot $script:McpConfigDir
            $memoryServer = @($result.servers) | Where-Object { $_.name -eq 'memory' }
            $memoryServer.kind | Should -Be 'memory'
        }
    }

    Context 'mcpServers が空の場合' {

        BeforeAll {
            $script:EmptyConfigPath = Join-Path $TestDrive 'empty-mcp.json'
            $emptyConfig = @{ mcpServers = @{} } | ConvertTo-Json
            Set-Content -Path $script:EmptyConfigPath -Value $emptyConfig -Encoding UTF8
        }

        It 'server 定義なし と表示されること' {
            $env:AI_STARTUP_MCP_CONFIG_PATH = $script:EmptyConfigPath
            $result = Get-McpHealthReport -ProjectRoot $TestDrive
            $result.configured | Should -Be $true
            $result.summary | Should -Match 'server 定義なし'
        }
    }

    Context '不正な JSON の場合' {

        BeforeAll {
            $script:BadConfigPath = Join-Path $TestDrive 'bad-mcp.json'
            Set-Content -Path $script:BadConfigPath -Value '{ invalid json }}}' -Encoding UTF8
        }

        It '解析失敗の summary を返すこと' {
            $env:AI_STARTUP_MCP_CONFIG_PATH = $script:BadConfigPath
            $result = Get-McpHealthReport -ProjectRoot $TestDrive
            $result.summary | Should -Match '解析に失敗'
        }
    }

    Context '環境変数で MCP config パスを上書きした場合' {
        It '環境変数のパスが使われること' {
            $customPath = Join-Path $TestDrive 'custom-mcp.json'
            $customConfig = @{
                mcpServers = @{
                    custom = @{
                        command = 'cmd'
                        args    = @('/c', 'echo', 'custom')
                    }
                }
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $customPath -Value $customConfig -Encoding UTF8

            $env:AI_STARTUP_MCP_CONFIG_PATH = $customPath
            $result = Get-McpHealthReport -ProjectRoot $TestDrive
            $result.configPath | Should -Be $customPath
            @($result.servers).Count | Should -Be 1
            $result.servers[0].name | Should -Be 'custom'
        }
    }
}

Describe 'Show-McpHealthReport' {

    Context '正常なレポートの場合' {
        It 'エラーなしで実行できること' {
            $report = [pscustomobject]@{
                configured  = $true
                configPath  = 'test/.mcp.json'
                servers     = @(
                    [pscustomobject]@{
                        name                     = 'github'
                        command                  = 'cmd'
                        status                   = 'available'
                        healthStatus             = 'not_configured'
                        startupCommand           = @()
                        shutdownCommand          = @()
                        startupCommandTimeoutSec = 10
                        shutdownCommandTimeoutSec = 10
                        operatingProcedure       = [pscustomobject]@{
                            startup  = $null
                            health   = $null
                            shutdown = $null
                        }
                    }
                )
                connections = @()
                summary     = 'MCP 設定あり: 1 server(s)'
            }

            { Show-McpHealthReport -Report $report } | Should -Not -Throw
        }
    }

    Context '未設定のレポートの場合' {
        It 'エラーなしで実行できること' {
            $report = [pscustomobject]@{
                configured  = $false
                configPath  = ''
                servers     = @()
                connections = @()
                summary     = 'MCP 設定なし'
            }

            { Show-McpHealthReport -Report $report } | Should -Not -Throw
        }
    }
}

Describe 'Test-AllTools.ps1 との互換性' {

    BeforeAll {
        . (Join-Path $script:RepoRoot 'scripts\test\Test-AllTools.ps1')
    }

    Context 'Get-McpServerDiagnostics が委譲されている場合' {
        It 'Get-McpServerHealth と同じ結果を返すこと' {
            $definition = [pscustomobject]@{
                command = 'cmd'
                args    = @('/c', 'echo', 'test')
            }

            $diagnosticsResult = Get-McpServerDiagnostics -Name 'compat-test' -Definition $definition
            $healthResult = Get-McpServerHealth -Name 'compat-test' -Definition $definition

            $diagnosticsResult.name | Should -Be $healthResult.name
            $diagnosticsResult.status | Should -Be $healthResult.status
            $diagnosticsResult.commandExists | Should -Be $healthResult.commandExists
        }
    }

    Context 'Get-McpDiagnostics が委譲されている場合' {
        It 'configured フィールドが一致すること' {
            $env:AI_STARTUP_MCP_CONFIG_PATH = Join-Path $TestDrive 'nonexistent.json'

            $diagnosticsResult = Get-McpDiagnostics -ProjectRoot $TestDrive
            $healthResult = Get-McpHealthReport -ProjectRoot $TestDrive

            $diagnosticsResult.configured | Should -Be $healthResult.configured
        }
    }
}
