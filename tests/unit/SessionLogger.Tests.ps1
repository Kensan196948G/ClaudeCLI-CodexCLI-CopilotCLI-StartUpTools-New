# ============================================================
# SessionLogger.Tests.ps1 - SessionLogger.ps1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibPath  = Join-Path $script:RepoRoot 'scripts\lib'
    . (Join-Path $script:LibPath 'SessionLogger.ps1')
}

Describe 'Get-LauncherMetadataLogPath' {

    Context 'Config.logging.logDir が設定されている場合' {

        It 'logDir を使ったパスを返すこと' {
            $config = [pscustomobject]@{
                logging        = [pscustomobject]@{ logDir = 'C:\logs' }
                recentProjects = $null
            }
            $result = Get-LauncherMetadataLogPath -Config $config
            $result | Should -Match 'launch-metadata-\d{8}\.jsonl$'
            $result | Should -Match '^C:\\logs\\'
        }
    }

    Context 'logging が null で recentProjects が設定されている場合' {

        It 'recentProjects.historyFile の親ディレクトリを使うこと' {
            $config = [pscustomobject]@{
                logging        = $null
                recentProjects = [pscustomobject]@{ historyFile = 'C:\data\history.json' }
            }
            $result = Get-LauncherMetadataLogPath -Config $config
            $result | Should -Match '^C:\\data\\'
            $result | Should -Match 'launch-metadata-\d{8}\.jsonl$'
        }
    }

    Context 'どちらも null の場合' {

        It 'null を返すこと' {
            $config = [pscustomobject]@{
                logging        = $null
                recentProjects = $null
            }
            $result = Get-LauncherMetadataLogPath -Config $config
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-LauncherMetadataEntry' {

    Context 'ログパスが null の場合' {

        It '空配列を返すこと' {
            $config = [pscustomobject]@{ logging = $null; recentProjects = $null }
            $result = Get-LauncherMetadataEntry -Config $config
            @($result).Count | Should -Be 0
        }
    }

    Context 'ログディレクトリが存在しない場合' {

        It '空配列を返すこと' {
            $config = [pscustomobject]@{
                logging        = [pscustomobject]@{ logDir = 'C:\nonexistent\path\xyz_9999' }
                recentProjects = $null
            }
            $result = Get-LauncherMetadataEntry -Config $config
            @($result).Count | Should -Be 0
        }
    }

    Context '有効な JSONL ファイルが存在する場合' {

        BeforeAll {
            $script:LogDir = Join-Path $TestDrive 'logs'
            New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
            $today = Get-Date -Format 'yyyyMMdd'
            $jsonlPath = Join-Path $script:LogDir "launch-metadata-$today.jsonl"
            @(
                '{"timestamp":"2026-04-18T10:00:00+09:00","project":"proj-a","tool":"claude","mode":"local","result":"success","elapsedMs":1200}',
                '{"timestamp":"2026-04-18T11:00:00+09:00","project":"proj-b","tool":"codex","mode":"ssh","result":"failure","elapsedMs":800}'
            ) | Set-Content -Path $jsonlPath -Encoding UTF8
            $script:LogConfig = [pscustomobject]@{
                logging        = [pscustomobject]@{ logDir = $script:LogDir }
                recentProjects = $null
            }
        }

        It 'エントリを読み込んで返すこと' {
            $result = Get-LauncherMetadataEntry -Config $script:LogConfig
            @($result).Count | Should -Be 2
        }

        It 'MaxCount でエントリ数を制限できること' {
            $result = Get-LauncherMetadataEntry -Config $script:LogConfig -MaxCount 1
            @($result).Count | Should -Be 1
        }
    }
}

Describe 'Get-LauncherBacklogSummary' {

    Context 'TASKS.md が存在しない場合' {

        It 'Count=0 を返すこと' {
            $result = Get-LauncherBacklogSummary -TasksPath (Join-Path $TestDrive 'NOSUCHFILE.md')
            $result.Count | Should -Be 0
        }
    }

    Context '有効な TASKS.md が存在する場合' {

        BeforeAll {
            $script:TasksFile = Join-Path $TestDrive 'TASKS.md'
            @(
                '1. [DONE] [Priority:P1] 完了タスク',
                '2. [Priority:P1] 未完了タスクA',
                '3. [Priority:P2] 未完了タスクB'
            ) | Set-Content -Path $script:TasksFile -Encoding UTF8
        }

        It 'DONE でないタスク件数を返すこと' {
            $result = Get-LauncherBacklogSummary -TasksPath $script:TasksFile
            $result.Count | Should -Be 2
        }

        It 'Priorities に優先度分布を返すこと' {
            $result = Get-LauncherBacklogSummary -TasksPath $script:TasksFile
            $result.Priorities | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'New-LauncherExecutionContext' {

    It 'StartTime プロパティを持つオブジェクトを返すこと' {
        $ctx = New-LauncherExecutionContext
        $ctx.StartTime | Should -Not -BeNullOrEmpty
    }

    It 'Result が unknown で初期化されること' {
        $ctx = New-LauncherExecutionContext
        $ctx.Result | Should -Be 'unknown'
    }

    It 'Project / Mode / Tool が null で初期化されること' {
        $ctx = New-LauncherExecutionContext
        $ctx.Project | Should -BeNullOrEmpty
        $ctx.Mode    | Should -BeNullOrEmpty
        $ctx.Tool    | Should -BeNullOrEmpty
    }
}

Describe 'Get-LauncherRecentSummary' {

    It 'エントリが空の場合は Total=0 を返すこと' {
        $result = Get-LauncherRecentSummary -Entries @()
        $result.Total           | Should -Be 0
        $result.SuccessRate     | Should -Be 0
        $result.AverageElapsedMs | Should -Be 0
    }

    It 'success 件数から SuccessRate を計算すること (2/3 = 67%)' {
        $entries = @(
            [pscustomobject]@{ result = 'success'; elapsedMs = 1000 },
            [pscustomobject]@{ result = 'success'; elapsedMs = 2000 },
            [pscustomobject]@{ result = 'failure'; elapsedMs = 500  }
        )
        $result = Get-LauncherRecentSummary -Entries $entries
        $result.Total       | Should -Be 3
        $result.SuccessRate | Should -Be 67
    }

    It 'AverageElapsedMs を正しく計算すること' {
        $entries = @(
            [pscustomobject]@{ result = 'success'; elapsedMs = 1000 },
            [pscustomobject]@{ result = 'failure'; elapsedMs = 2000 }
        )
        $result = Get-LauncherRecentSummary -Entries $entries
        $result.AverageElapsedMs | Should -Be 1500
    }
}
