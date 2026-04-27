# ============================================================
# Start-Menu.ps1 - AI CLI 統合メニュー
# ClaudeOS Agent Teams 対応: Agent Orchestrator / Scrum Master の操作入口
# docs/common/08_AgentTeams対応表.md を参照
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ProjectRoot "scripts\lib\LauncherCommon.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $ProjectRoot "scripts\lib\Config.psm1") -Force
Import-Module (Join-Path $ProjectRoot "scripts\lib\MenuCommon.psm1") -Force -DisableNameChecking

if ($env:AI_STARTUP_MENU_TEST_EXPORT -ne '1') {
    Set-Location $ProjectRoot

    $ConfigPath = Get-StartupConfigPath -StartupRoot $ProjectRoot
    $Config = Import-LauncherConfig -ConfigPath $ConfigPath
    $LinuxHost = if ($Config.linuxHost) { $Config.linuxHost } else { "未設定" }
    $LinuxBase = if ($Config.linuxBase) { $Config.linuxBase } else { "未設定" }
    $LocalDir  = if ($Config.projectsDir) { $Config.projectsDir } else { "未設定" }
    $ShellExe = Get-LauncherShell
}

function Get-RecentProjectortWeight {
    param([object]$Entry)

    switch ($Entry.result) {
        'success' { return 3 }
        'unknown' { return 2 }
        'cancelled' { return 1 }
        'failure' { return 0 }
        default { return 2 }
    }
}

function Get-RecentProjectuccessRate {
    param([object]$Entry)

    $matchingEntries = @(
        Get-RecentProject -HistoryPath $Config.recentProjects.historyFile |
            Where-Object {
                $_.project -eq $Entry.project -and
                $_.tool -eq $Entry.tool -and
                $_.mode -eq $Entry.mode
            }
    )
    return (Get-LauncherRecentSummary -Entries $matchingEntries).SuccessRate
}

function Get-SortedRecentProject {
    param(
        [object[]]$Entries,
        [ValidateSet('success', 'timestamp', 'elapsed')]
        [string]$SortMode = 'success'
    )

    switch ($SortMode) {
        'timestamp' {
            return @(
                $Entries |
                    Sort-Object @{ Expression = {
                        if ($_.timestamp) { try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue } }
                        else { [datetimeoffset]::MinValue }
                    }; Descending = $true }
            )
        }
        'elapsed' {
            return @(
                $Entries |
                    Sort-Object `
                        @{ Expression = {
                            if ($null -ne $_.elapsedMs) { [int]$_.elapsedMs } else { [int]::MaxValue }
                        }; Descending = $false }, `
                        @{ Expression = { Get-RecentProjectortWeight -Entry $_ }; Descending = $true }, `
                        @{ Expression = {
                            if ($_.timestamp) { try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue } }
                            else { [datetimeoffset]::MinValue }
                        }; Descending = $true }
            )
        }
    }

    return @(
        $Entries |
            Sort-Object `
                @{ Expression = { Get-RecentProjectuccessRate -Entry $_ }; Descending = $true }, `
                @{ Expression = { Get-RecentProjectortWeight -Entry $_ }; Descending = $true }, `
                @{ Expression = {
                    if ($_.timestamp) { try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue } }
                    else { [datetimeoffset]::MinValue }
                }; Descending = $true }
    )
}

function Get-FilteredRecentProject {
    param(
        [object[]]$Entries,
        [string]$ToolFilter = '',
        [string]$SearchQuery = '',
        [ValidateSet('success', 'timestamp', 'elapsed')]
        [string]$SortMode = 'success'
    )

    $filtered = @($Entries)
    if (-not [string]::IsNullOrWhiteSpace($ToolFilter)) {
        $filtered = @($filtered | Where-Object { $_.tool -eq $ToolFilter })
    }
    if (-not [string]::IsNullOrWhiteSpace($SearchQuery)) {
        $filtered = @($filtered | Where-Object { $_.project -like "*$SearchQuery*" })
    }
    return @(@(Get-SortedRecentProject -Entries $filtered -SortMode $SortMode))
}

function Get-RecentProjectLabel {
    param([Parameter(Mandatory)][object]$Entry)

    $tool = if ([string]::IsNullOrWhiteSpace($Entry.tool)) { $Config.tools.defaultTool } else { $Entry.tool }
    $mode = if ($Entry.mode -eq 'local') { 'Local' } else { 'SSH' }
    $timestamp = if ($Entry.timestamp) {
        try { (Get-Date $Entry.timestamp).ToString('yyyy-MM-dd HH:mm') } catch { $Entry.timestamp }
    }
    else {
        '時刻不明'
    }

    $result = switch ($Entry.result) {
        'success' { 'OK' }
        'failure' { 'FAIL' }
        'cancelled' { 'CANCEL' }
        default { 'UNKNOWN' }
    }

    $elapsed = if ($null -ne $Entry.elapsedMs) { "{0}ms" -f [int]$Entry.elapsedMs } else { 'n/a' }
    $matchingEntries = @(
        Get-RecentProject -HistoryPath $Config.recentProjects.historyFile |
            Where-Object {
                $_.project -eq $Entry.project -and
                $_.tool -eq $Entry.tool -and
                $_.mode -eq $Entry.mode
            }
    )
    $summary = Get-LauncherRecentSummary -Entries $matchingEntries
    $successRate = if ($summary.Total -gt 0) { "$($summary.SuccessRate)%" } else { 'n/a' }

    return "{0} [{1}/{2}/{3}] ({4}, {5}, success {6})" -f $Entry.project, $tool, $mode, $result, $timestamp, $elapsed, $successRate
}

function Get-RecentProjectColor {
    param([Parameter(Mandatory)][object]$Entry)

    switch ($Entry.result) {
        'success' { return 'Green' }
        'failure' { return 'Red' }
        'cancelled' { return 'Yellow' }
        default { return 'Cyan' }
    }
}

function Get-RecentProjectLaunchSpec {
    param([Parameter(Mandatory)][object]$Entry)

    $tool = if ([string]::IsNullOrWhiteSpace($Entry.tool)) { $Config.tools.defaultTool } else { $Entry.tool }
    $modeIsLocal = ($Entry.mode -eq 'local')
    $scriptMap = @{
        'claude' = "scripts\main\Start-ClaudeCode.ps1"
        'codex' = "scripts\main\Start-CodexCLI.ps1"
        'copilot' = "scripts\main\Start-CopilotCLI.ps1"
    }

    $scriptArgs = @("-Project", $Entry.project)
    if ($modeIsLocal) {
        $scriptArgs += "-Local"
    }

    return [pscustomobject]@{
        tool = $tool
        file = $scriptMap[$tool]
        scriptArgs = $scriptArgs
    }
}

function Show-Menu {
    Clear-Host
    $hr = "  " + ("─" * 60)

    # ── ヘッダー ──────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   🤖 Claude Code ユニバーサルスタートアップツール v3.2  ║" -ForegroundColor Cyan
    Write-Host "  ║      ClaudeOS v8.2  │  Linux Cron 自律実行  │  AI Dev   ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # ── 接続情報 ─────────────────────────────────────────────────────────────
    Write-Host "  🔗 " -NoNewline -ForegroundColor Yellow
    Write-Host "SSH   " -NoNewline -ForegroundColor DarkGray
    Write-Host "$LinuxHost" -NoNewline -ForegroundColor White
    Write-Host " ➜ " -NoNewline -ForegroundColor DarkGray
    Write-Host "$LinuxBase" -ForegroundColor Yellow
    Write-Host "  📂 " -NoNewline -ForegroundColor Green
    Write-Host "Local " -NoNewline -ForegroundColor DarkGray
    Write-Host "$LocalDir" -ForegroundColor Green
    Write-Host ""

    # ── 起動 ─────────────────────────────────────────────────────────────────
    Write-Host $hr -ForegroundColor DarkCyan
    Write-Host "  🚀 Claude Code 起動" -ForegroundColor Cyan
    Write-Host $hr -ForegroundColor DarkCyan
    Write-Host "   " -NoNewline
    Write-Host " S1 " -NoNewline -ForegroundColor Black -BackgroundColor Yellow
    Write-Host "  ☁️  Claude Code (SSH)    " -NoNewline -ForegroundColor Yellow
    Write-Host "Linux cron 自律実行 / 5h セッション" -ForegroundColor DarkYellow
    Write-Host "   " -NoNewline
    Write-Host " L1 " -NoNewline -ForegroundColor Black -BackgroundColor Green
    Write-Host "  🖥️  Claude Code (ローカル)" -NoNewline -ForegroundColor Green
    Write-Host "  手動セッション / スケジューラ不要" -ForegroundColor DarkGreen
    Write-Host ""

    # ── 診断・ツール ─────────────────────────────────────────────────────────
    Write-Host $hr -ForegroundColor DarkMagenta
    Write-Host "  🔧 診断・セットアップ・ツール" -ForegroundColor Magenta
    Write-Host $hr -ForegroundColor DarkMagenta

    $diagItems = @(
        [pscustomobject]@{ Key = " 5"; Icon = "🩺"; Label = "ツール確認・診断";             Color = "Magenta"   }
        [pscustomobject]@{ Key = " 6"; Icon = "💾"; Label = "ドライブマッピング診断";        Color = "Magenta"   }
        [pscustomobject]@{ Key = " 7"; Icon = "⚙️"; Label = "Windows Terminal セットアップ"; Color = "DarkYellow"}
        [pscustomobject]@{ Key = " 8"; Icon = "🩹"; Label = "MCP ヘルスチェック";            Color = "Magenta"   }
        [pscustomobject]@{ Key = " 9"; Icon = "🤝"; Label = "Agent Teams ランタイム";        Color = "Cyan"      }
        [pscustomobject]@{ Key = "10"; Icon = "🌿"; Label = "Worktree Manager";              Color = "Cyan"      }
        [pscustomobject]@{ Key = "11"; Icon = "🏛️"; Label = "Architecture Check";            Color = "Magenta"   }
        [pscustomobject]@{ Key = "12"; Icon = "📊"; Label = "Statusline 設定";               Color = "DarkCyan"  }
        [pscustomobject]@{ Key = "13"; Icon = "📡"; Label = "Claude ログ監視タブを開く";     Color = "Cyan"      }
    )
    foreach ($it in $diagItems) {
        Write-Host "   " -NoNewline
        Write-Host " $($it.Key) " -NoNewline -ForegroundColor Black -BackgroundColor DarkGray
        Write-Host "  $($it.Icon)  " -NoNewline -ForegroundColor White
        Write-Host $it.Label -ForegroundColor $it.Color
    }
    Write-Host ""

    # ── Cron 管理 ────────────────────────────────────────────────────────────
    Write-Host $hr -ForegroundColor DarkYellow
    Write-Host "  ⏰ Linux Cron 自律実行管理  " -NoNewline -ForegroundColor Yellow
    Write-Host "[SSH 専用]" -ForegroundColor DarkYellow
    Write-Host $hr -ForegroundColor DarkYellow

    Write-Host "   " -NoNewline
    Write-Host " 14 " -NoNewline -ForegroundColor Black -BackgroundColor DarkBlue
    Write-Host "  📅  " -NoNewline -ForegroundColor White
    Write-Host "Cron スケジュール 登録・編集・削除  " -NoNewline -ForegroundColor Cyan
    Write-Host "[SSH / 5h 強制終了]" -ForegroundColor DarkCyan

    Write-Host "   " -NoNewline
    Write-Host " 15 " -NoNewline -ForegroundColor Black -BackgroundColor DarkBlue
    Write-Host "  📺  " -NoNewline -ForegroundColor White
    Write-Host "Linux セッション状態監視  " -NoNewline -ForegroundColor Cyan
    Write-Host "[SSH / リアルタイム cron 実行状況]" -ForegroundColor DarkCyan
    Write-Host ""

    # ── フッター ──────────────────────────────────────────────────────────────
    Write-Host $hr -ForegroundColor DarkGray
    Write-Host "   " -NoNewline
    Write-Host "  0 " -NoNewline -ForegroundColor Black -BackgroundColor DarkGray
    Write-Host "  ❌  終了" -ForegroundColor Gray
    Write-Host $hr -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  💡 " -NoNewline -ForegroundColor Yellow
    Write-Host "自律実行: Linux cron (月〜土 / プロジェクト別 / 300分)　" -NoNewline -ForegroundColor DarkGray
    Write-Host "推奨: Windows Terminal" -ForegroundColor DarkCyan
    Write-Host ""
}

function Invoke-MenuScript {
    param(
        [Parameter(Mandatory)]
        [string]$File,
        [string[]]$ScriptArgs = @()
    )

    & $ShellExe -NoProfile -ExecutionPolicy Bypass -File $File @ScriptArgs
    $scriptExitCode = $LASTEXITCODE

    Write-Host ""
    if ($scriptExitCode -ne 0) {
        $logDir = Join-Path $ProjectRoot "logs"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }
        $timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
        $logFile = Join-Path $logDir "menu-error-$timestamp.log"

        $logContent = @(
            "Timestamp : $timestamp"
            "Script    : $File"
            "Args      : $($ScriptArgs -join ' ')"
            "ExitCode  : $scriptExitCode"
            "Host      : $env:COMPUTERNAME"
        ) -join "`n"
        Set-Content -Path $logFile -Value $logContent -Encoding UTF8

        Write-Host "  ========================================" -ForegroundColor Red
        Write-Host "  エラーが発生しました (終了コード: $scriptExitCode)" -ForegroundColor Red
        Write-Host "  ログ: $logFile" -ForegroundColor Yellow
        Write-Host "  ========================================" -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "  Enterキーでメニューに戻ります（Ctrl+Cでコピー可）"
}

function Invoke-ToolFromMenu {
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [switch]$Local
    )

    $scriptArgs = @("-Tool", $Tool)
    if ($Local) {
        $scriptArgs += "-Local"
    }

    Invoke-MenuScript -File "scripts\main\Start-All.ps1" -ScriptArgs $scriptArgs
}

if ($env:AI_STARTUP_MENU_TEST_EXPORT -eq '1') {
    return
}

while ($true) {
    Show-Menu
    $choice = Read-Host "  番号を入力してください"

    switch ($choice.ToUpper()) {
        "S1" { Invoke-ToolFromMenu -Tool "claude" }
        "L1" { Invoke-ToolFromMenu -Tool "claude" -Local }
        "5"  { Invoke-MenuScript -File "scripts\test\Test-AllTools.ps1" }
        "6"  { Invoke-MenuScript -File "scripts\test\test-drive-mapping.ps1" }
        "7"  { Invoke-MenuScript -File "scripts\setup\setup-windows-terminal.ps1" }
        "8"  { Invoke-MenuScript -File "scripts\test\Test-McpHealth.ps1" }
        "9"  { Invoke-MenuScript -File "scripts\test\Test-AgentTeams.ps1" }
        "10" { Invoke-MenuScript -File "scripts\test\Test-WorktreeManager.ps1" }
        "11" { Invoke-MenuScript -File "scripts\test\Test-ArchitectureCheck.ps1" }
        "12" { Invoke-MenuScript -File "scripts\main\Set-Statusline.ps1" }
        "13" {
            $watchScript = Join-Path $ProjectRoot "scripts\tools\Watch-ClaudeLog.ps1"
            & $ShellExe -NoProfile -ExecutionPolicy Bypass -File $watchScript -NewTab -WithSessionInfoTab
            Write-Host ""
            Read-Host "  Enterキーでメニューに戻ります"
        }
        "14" { Invoke-MenuScript -File "scripts\main\New-CronSchedule.ps1" }
        "15" {
            $watchScript = Join-Path $ProjectRoot "scripts\tools\Watch-SessionInfoSSH.ps1"
            & $ShellExe -NoProfile -ExecutionPolicy Bypass -File $watchScript
            Write-Host ""
            Read-Host "  Enterキーでメニューに戻ります"
        }
        "0"  { exit 0 }
        default {
            Write-Host ""
            Write-Host "  無効な入力です。もう一度選択してください。" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
