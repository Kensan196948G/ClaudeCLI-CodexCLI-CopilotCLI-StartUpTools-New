<#
.SYNOPSIS
    Watch-ClaudeLog.ps1 をWindowsログオン時に自動起動するタスクスケジューラタスクを登録する。
.DESCRIPTION
    ClaudeOS v3.2.103
    Linux cron が発火した際に自動でWindowsターミナルの既存ウィンドウにタブを追加する。
    タスクスケジューラから直接 wt.exe を起動することで、
    中間 pwsh プロセス経由の「新規ウィンドウ」問題を解消する。
.PARAMETER Unregister
    登録済みのタスクを削除する。
#>

param(
    [switch]$Unregister
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName    = 'ClaudeOS-WatchAutoStart'
$ScriptRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$WatchScript = Join-Path $ScriptRoot 'scripts\tools\Watch-ClaudeLog.ps1'

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[OK] タスク '$TaskName' を削除しました。" -ForegroundColor Green
    } else {
        Write-Host "[INFO] タスク '$TaskName' は登録されていません。" -ForegroundColor Yellow
    }
    exit 0
}

# 既存タスクの確認
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "[INFO] タスク '$TaskName' は既に登録されています。再登録するには -Unregister で削除後に再実行してください。" -ForegroundColor Yellow
    exit 0
}

# wt.exe の解決（WindowsApps が PATH に入らないケースも考慮）
$wtCandidates = @(
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe",
    "$env:ProgramFiles\WindowsApps\Microsoft.WindowsTerminal*\wt.exe"
)
$wtExe = $null
foreach ($c in $wtCandidates) {
    $found = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $wtExe = $found.FullName; break }
}
if (-not $wtExe) { $wtExe = 'wt.exe' }  # PATH fallback

# pwsh.exe の解決
$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwshExe) {
    foreach ($p in @('C:\Program Files\PowerShell\7\pwsh.exe', "$env:ProgramFiles\PowerShell\7\pwsh.exe")) {
        if (Test-Path $p) { $pwshExe = $p; break }
    }
}
if (-not $pwshExe) {
    Write-Host '[ERROR] pwsh.exe が見つかりません。PowerShell 7 をインストールしてください。' -ForegroundColor Red
    exit 1
}

# wt.exe --commandline の引数は PowerShell→wt→CreateProcess と3段階解析されるため
# スペース入り文字列を渡すたびに引用符が崩れる。
# 唯一確実な回避策: スペースなしパスの .cmd ファイルを --commandline に渡す。
$LauncherCmd = Join-Path (Split-Path $WatchScript) 'Watch-ClaudeLog-Launcher.cmd'
if (-not (Test-Path $LauncherCmd)) {
    Write-Host "[ERROR] Watch-ClaudeLog-Launcher.cmd が見つかりません: $LauncherCmd" -ForegroundColor Red
    exit 1
}

# wt.exe に渡す引数:
#   -w last : 最後に使用した WindowsTerminal ウィンドウに追加（なければ新規作成）
#   new-tab : 新しいタブを追加
#   --commandline : .cmd ファイルのパス（スペースなし）
$wtArgStr = "-w last new-tab --title `"Claude-Live-Log`" --commandline `"$LauncherCmd`""

$action = New-ScheduledTaskAction -Execute $wtExe -Argument $wtArgStr

# ログオン時トリガー（対話型セッション確保）
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal `
    -Description 'ClaudeOS: Linux cron 発火時に既存 WindowsTerminal へタブを追加してログ監視を起動' | Out-Null

Write-Host ''
Write-Host "  [OK] タスク '$TaskName' を登録しました。" -ForegroundColor Green
Write-Host ''
Write-Host "  wt.exe    : $wtExe" -ForegroundColor DarkGray
Write-Host "  pwsh.exe  : $pwshExe" -ForegroundColor DarkGray
Write-Host "  スクリプト: $WatchScript" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  動作: Windowsログオン時に既存 WindowsTerminal ウィンドウへ' -ForegroundColor DarkCyan
Write-Host '        Claude-Live-Log タブが追加され、Linux cron を監視します。' -ForegroundColor DarkCyan
Write-Host ''
Write-Host "  登録状態: $((Get-ScheduledTask -TaskName $TaskName).State)" -ForegroundColor Green
