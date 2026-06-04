<#
.SYNOPSIS
    Claude Code の時間制限付き自律実行を Windows タスクスケジューラに週次登録する。
.DESCRIPTION
    Linux の crontab + cron-launcher.sh に対応する Windows ネイティブ版。
    Start-ClaudeAutoTimeout.ps1 を指定の曜日・時刻に起動するタスクを
    プロジェクトごとに登録する。Register-DashboardTask.ps1 のパターンを踏襲
    (pwsh 優先 / RunLevel Limited / 多重起動防止)。
    ClaudeOS — Phase 1 (Windows ローカル一本化)
.PARAMETER Project
    projectsDir 直下のプロジェクト名 (タスク名に使用)。
.PARAMETER DaysOfWeek
    起動曜日 (Monday..Sunday)。既定は月〜土 (CLAUDE.md「日曜は休む」に準拠)。
.PARAMETER At
    起動時刻 (HH:mm)。既定 09:00。
.PARAMETER DurationMinutes
    1 セッションの最大作業時間 (分)。既定 300 (5時間)。
.PARAMETER Unregister
    指定プロジェクトの登録を解除。
.PARAMETER Status
    指定プロジェクトの登録状態を表示。
.EXAMPLE
    .\Register-AutoRunTask.ps1 -Project MyApp -DaysOfWeek Monday,Wednesday,Friday -At 09:00
.EXAMPLE
    .\Register-AutoRunTask.ps1 -Project MyApp -Status
.EXAMPLE
    .\Register-AutoRunTask.ps1 -Project MyApp -Unregister
#>

param(
    [string]$Project = '',
    [string[]]$DaysOfWeek = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'),
    [string]$At = '09:00',
    [int]$DurationMinutes = 300,
    [switch]$Unregister,
    [switch]$Status,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Project)) {
    Write-Host '  [ERROR] -Project を指定してください。' -ForegroundColor Red
    exit 1
}

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$WrapperPs1 = Join-Path $ScriptRoot 'scripts\main\Start-ClaudeAutoTimeout.ps1'
$TaskName   = "ClaudeOS AutoRun - $Project"

# pwsh (PowerShell 7) を優先、なければ powershell.exe
$PsExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    (Get-Command pwsh).Source
} else {
    (Get-Command powershell).Source
}

Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host '  ClaudeOS AutoRun - Task Scheduler' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ''

# --- Status ---
if ($Status) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        Write-Host "  タスク名  : $TaskName" -ForegroundColor White
        Write-Host "  状態      : $($task.State)" -ForegroundColor $(if ($task.State -eq 'Running') { 'Green' } else { 'Yellow' })
        if ($info) {
            Write-Host "  最終実行  : $($info.LastRunTime)" -ForegroundColor Gray
            Write-Host "  次回実行  : $($info.NextRunTime)" -ForegroundColor Gray
            Write-Host "  最終結果  : 0x$($info.LastTaskResult.ToString('X'))" -ForegroundColor Gray
        }
    } else {
        Write-Host "  [未登録] タスク '$TaskName' は登録されていません。" -ForegroundColor Yellow
    }
    Write-Host ''
    if (-not $NonInteractive) { Read-Host '  Enter で戻ります' | Out-Null }
    return
}

# --- Unregister ---
if ($Unregister) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "  [INFO] タスク '$TaskName' は登録されていません。" -ForegroundColor Yellow
    } else {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  [OK] タスクを削除しました: $TaskName" -ForegroundColor Green
    }
    Write-Host ''
    if (-not $NonInteractive) { Read-Host '  Enter で戻ります' | Out-Null }
    return
}

# --- Register ---
if (-not (Test-Path $WrapperPs1)) {
    Write-Host "  [ERROR] ランチャが見つかりません: $WrapperPs1" -ForegroundColor Red
    exit 1
}

# 曜日文字列を [System.DayOfWeek] へ変換 (不正値は停止)
$days = @()
foreach ($d in $DaysOfWeek) {
    try { $days += [System.DayOfWeek]$d }
    catch {
        Write-Host "  [ERROR] 不正な曜日: '$d' (Monday..Sunday で指定してください)" -ForegroundColor Red
        exit 1
    }
}

$argument = "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass " +
            "-File `"$WrapperPs1`" -Project `"$Project`" -DurationMinutes $DurationMinutes -Trigger cron"

$action  = New-ScheduledTaskAction -Execute $PsExe -Argument $argument -WorkingDirectory $ScriptRoot
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $At

# スクリプト側が自前で時間制限するが、二重防護として DurationMinutes+30 分で打ち切る。
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::FromMinutes($DurationMinutes + 30)) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action   $action `
        -Trigger  $trigger `
        -Settings $settings `
        -RunLevel Limited `
        -Force | Out-Null

    Write-Host '  [OK] タスクスケジューラーに登録しました' -ForegroundColor Green
    Write-Host "  タスク名     : $TaskName" -ForegroundColor White
    Write-Host "  プロジェクト : $Project" -ForegroundColor White
    Write-Host "  曜日         : $($DaysOfWeek -join ', ')" -ForegroundColor White
    Write-Host "  時刻         : $At" -ForegroundColor White
    Write-Host "  作業時間     : $DurationMinutes 分" -ForegroundColor White
    Write-Host "  ランチャ     : Start-ClaudeAutoTimeout.ps1" -ForegroundColor DarkGray
} catch {
    Write-Host "  [ERROR] 登録に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  管理者権限で実行してみてください。' -ForegroundColor Yellow
    if (-not $NonInteractive) { Read-Host '  Enter で戻ります' | Out-Null }
    exit 1
}

Write-Host ''
Write-Host "  次回 $At から週次で自律開発セッションを起動します。" -ForegroundColor DarkGray
Write-Host "  状態確認: .\Register-AutoRunTask.ps1 -Project `"$Project`" -Status" -ForegroundColor DarkGray
Write-Host ''

if (-not $NonInteractive) { Read-Host '  Enter で戻ります' | Out-Null }
