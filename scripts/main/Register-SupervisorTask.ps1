#Requires -Version 5.1
<#
.SYNOPSIS
    ClaudeOS Supervisor Daemon をタスクスケジューラーに登録・解除する。
.DESCRIPTION
    -Unregister スイッチで解除。
    登録後はログオン時に自動起動（ウィンドウ非表示）。
    -Status でタスク状態と supervisor が管理するプロセス一覧を表示。
    ClaudeOS v9.0
#>

param(
    [switch]$Unregister,
    [switch]$RunNow,
    [switch]$Status,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName    = 'ClaudeOS Supervisor'
$ScriptRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$WrapperPs1  = Join-Path $ScriptRoot 'scripts\dashboards\start-supervisor-task.ps1'
$StateFile   = Join-Path $env:USERPROFILE '.claudeos\supervisor\state.json'

# pwsh (PowerShell 7) を優先、なければ powershell.exe
$PsExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    (Get-Command pwsh).Source
} else {
    (Get-Command powershell).Source
}

Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host '  ClaudeOS Supervisor - Task Scheduler   ' -ForegroundColor Cyan
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

    # supervisor state.json からプロセス状態を表示
    if (Test-Path $StateFile) {
        try {
            $state = Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Host ''
            Write-Host "  ─── Managed Processes ─── (generated: $($state.generated))" -ForegroundColor DarkGray
            foreach ($kv in $state.processes.PSObject.Properties) {
                $p = $kv.Value
                $statusColor = switch ($p.status) {
                    'running'  { 'Green' }
                    'starting' { 'Cyan' }
                    'cooldown' { 'Yellow' }
                    'stale'    { 'Yellow' }
                    'stopped'  { 'Gray' }
                    'disabled' { 'Red' }
                    default    { 'DarkGray' }
                }
                $pidStr = if ($p.pid) { " (pid=$($p.pid))" } else { '' }
                Write-Host "  [$($p.status.ToUpper().PadRight(9))] $($p.name)$pidStr" -ForegroundColor $statusColor
                if ($p.activeSession) {
                    Write-Host "    session: $($p.activeSession.sessionId) / stale=$($p.activeSession.staleSec)s" -ForegroundColor DarkGray
                }
            }
        } catch {
            Write-Host "  [WARN] state.json 読み取りエラー: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host ''
        Write-Host "  [INFO] state.json 未生成 — supervisor 未起動の可能性があります。" -ForegroundColor DarkGray
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
    Write-Host "  [ERROR] ラッパースクリプトが見つかりません: $WrapperPs1" -ForegroundColor Red
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute $PsExe `
    -Argument "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$WrapperPs1`"" `
    -WorkingDirectory $ScriptRoot

$trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartOnIdle:$false `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -DisallowDemandStart:$false

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action   $action `
        -Trigger  $trigger `
        -Settings $settings `
        -RunLevel Limited `
        -Force | Out-Null

    Write-Host "  [OK] タスクスケジューラーに登録しました" -ForegroundColor Green
    Write-Host "  タスク名 : $TaskName" -ForegroundColor White
    Write-Host "  実行条件 : $($env:USERNAME) ログオン時" -ForegroundColor White
    Write-Host "  表示     : 非表示（バックグラウンド）" -ForegroundColor White
    Write-Host ''
    Write-Host "  ログファイル: $env:USERPROFILE\.claudeos\supervisor\supervisor.log" -ForegroundColor DarkGray
    Write-Host "  State JSON : $StateFile" -ForegroundColor DarkGray
} catch {
    Write-Host "  [ERROR] 登録に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  管理者権限で実行してみてください。" -ForegroundColor Yellow
    if (-not $NonInteractive) { Read-Host '  Enter で戻ります' | Out-Null }
    exit 1
}

# --- 今すぐ起動 ---
if ($RunNow) {
    Write-Host ''
    Write-Host "  [起動中] Supervisor を今すぐ起動します..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2
    Write-Host "  [OK] 起動しました。state.json が生成されます。" -ForegroundColor Green
}

Write-Host ''
Write-Host '  次回 Windows ログイン時から自動起動します。' -ForegroundColor DarkGray
Write-Host '  状態確認: Register-SupervisorTask.ps1 -Status' -ForegroundColor DarkGray
Write-Host '  今すぐ起動: Start-ScheduledTask -TaskName "ClaudeOS Supervisor"' -ForegroundColor DarkGray
Write-Host ''

if (-not $NonInteractive) { Read-Host '  Enter で戻ります' | Out-Null }
