<#
.SYNOPSIS
    メニュー 12 本体。Linux crontab の CLAUDEOS エントリを対話的に登録・編集・削除する。
.DESCRIPTION
    ClaudeOS v3.1.0
#>

param(
    [switch]$NonInteractive
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\CronManager.psm1') -Force -DisableNameChecking

$ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot
$Config = Import-LauncherConfig -ConfigPath $ConfigPath
$LinuxHost = $Config.linuxHost

$LinuxUser = 'kensan'
if ($Config.PSObject.Properties.Name -contains 'linuxUser') { $LinuxUser = $Config.linuxUser }

if ([string]::IsNullOrWhiteSpace($LinuxHost) -or $LinuxHost -eq '<your-linux-host>') {
    Write-Host "[ERROR] config.json の linuxHost が未設定です。" -ForegroundColor Red
    exit 1
}

# CronManager 設定を config から反映
$launcherPath = '/home/kensan/.claudeos/cron-launcher.sh'
$logsDir      = '/home/kensan/.claudeos/logs'
if ($Config.PSObject.Properties.Name -contains 'cron') {
    $cronConfig = $Config.cron
    $prefix = if ($cronConfig.PSObject.Properties.Name -contains 'entryPrefix') { $cronConfig.entryPrefix } else { 'CLAUDEOS' }
    $launcher = if ($cronConfig.PSObject.Properties.Name -contains 'launcherPath') { $cronConfig.launcherPath } else { $launcherPath }
    $logs = if ($cronConfig.PSObject.Properties.Name -contains 'logsDir') { $cronConfig.logsDir } else { $logsDir }
    $launcherPath = $launcher
    $logsDir      = $logs
    Set-CronManagerConfig -EntryPrefix $prefix -LauncherPath $launcher -LogsDir $logs
}

$defaultDuration = if ($Config.PSObject.Properties.Name -contains 'cron' -and $Config.cron.PSObject.Properties.Name -contains 'defaultDurationMinutes') {
    [int]$Config.cron.defaultDurationMinutes
} else { 300 }

function Show-CronMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   Cron 登録・編集・削除・テスト (Linux: $LinuxHost)" -ForegroundColor Cyan
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [1] 新規登録" -ForegroundColor Yellow
    Write-Host "    [2] 一覧" -ForegroundColor Yellow
    Write-Host "    [3] 編集" -ForegroundColor Yellow
    Write-Host "    [4] 削除 (ID 指定)" -ForegroundColor Yellow
    Write-Host "    [5] 全解除" -ForegroundColor Yellow
    Write-Host "    [6] 今すぐ実行" -ForegroundColor Green
    Write-Host "    [0] 戻る" -ForegroundColor Gray
    Write-Host ""
}

function Get-ProjectList {
    # Linux 側の /home/kensan/Projects を ssh ls で取得
    $sshExe = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { 'ssh' }
    $base = $Config.linuxBase
    $output = & $sshExe -T -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o ControlMaster=no `
        $LinuxHost "ls -1 '$base' 2>/dev/null | grep -v '^\.'"
    if ($null -eq $output) { return @() }
    return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Select-Project {
    $projects = Get-ProjectList
    if ($projects.Count -eq 0) {
        Write-Host "  プロジェクト一覧が取得できません。手動入力してください。" -ForegroundColor Yellow
        $name = Read-Host "  プロジェクト名"
        return $name.Trim()
    }
    Write-Host ""
    Write-Host "  -- プロジェクト一覧 --" -ForegroundColor Cyan
    for ($i = 0; $i -lt $projects.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $projects[$i]) -ForegroundColor White
    }
    Write-Host ""
    $idx = Read-Host "  番号を入力"
    if ($idx -match '^\d+$') {
        $n = [int]$idx - 1
        if ($n -ge 0 -and $n -lt $projects.Count) { return $projects[$n] }
    }
    Write-Host "  無効な番号です" -ForegroundColor Red
    return $null
}

function Select-DayOfWeek {
    Write-Host ""
    Write-Host "  -- 曜日選択 (複数可、カンマ区切り) --" -ForegroundColor Cyan
    Write-Host "    0=日 1=月 2=火 3=水 4=木 5=金 6=土" -ForegroundColor DarkGray
    $rawInput = Read-Host "  曜日 (例: 0 または 1,3,5)"
    $list = @()
    foreach ($token in ($rawInput -split ',')) {
        $t = $token.Trim()
        if ($t -match '^\d$') { $list += [int]$t }
    }
    if ($list.Count -eq 0) {
        Write-Host "  曜日を 1 つ以上指定してください" -ForegroundColor Red
        return $null
    }
    return $list
}

function Invoke-Register {
    $project = Select-Project
    if ([string]::IsNullOrWhiteSpace($project)) { return }

    $dow = Select-DayOfWeek
    if ($null -eq $dow) { return }

    $time = Read-Host "  時刻 (HH:MM, 例: 21:00)"
    $durationInput = Read-Host "  作業時間 (分、Enter で $defaultDuration)"
    $duration = if ([string]::IsNullOrWhiteSpace($durationInput)) { $defaultDuration } else { [int]$durationInput }

    Write-Host ""
    Write-Host "  == 確認 ==" -ForegroundColor Yellow
    Write-Host "    プロジェクト : $project"
    Write-Host "    曜日         : $(($dow | ForEach-Object { Get-DayOfWeekLabel -Dow $_ }) -join '/')"
    Write-Host "    時刻         : $time"
    Write-Host "    作業時間     : $duration 分"
    Write-Host ""
    $confirm = Read-Host "  登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  キャンセルしました" -ForegroundColor Yellow
        return
    }

    try {
        $entry = Add-ClaudeOSCronEntry -LinuxHost $LinuxHost -Project $project -DayOfWeek $dow -Time $time -DurationMinutes $duration
        Write-Host ""
        Write-Host "  [OK] Cron エントリを登録しました: ID=$($entry.Id)" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-List {
    $entries = Get-ClaudeOSCronEntry -LinuxHost $LinuxHost
    Write-Host ""
    if ($entries.Count -eq 0) {
        Write-Host "  登録済みの CLAUDEOS Cron エントリはありません。" -ForegroundColor Yellow
        return
    }
    Write-Host "  -- 登録済み Cron エントリ ($($entries.Count) 件) --" -ForegroundColor Cyan
    foreach ($e in $entries) {
        Write-Host ("    " + (Format-CronEntryForDisplay -Entry $e)) -ForegroundColor White
    }
}

function Invoke-Edit {
    Invoke-List
    $entries = Get-ClaudeOSCronEntry -LinuxHost $LinuxHost
    if ($entries.Count -eq 0) { return }
    $id = Read-Host "  編集対象の ID"
    $target = $entries | Where-Object { $_.Id -eq $id }
    if ($null -eq $target) {
        Write-Host "  ID が見つかりません: $id" -ForegroundColor Red
        return
    }
    Write-Host "  一度削除して新規登録します。項目を再入力してください。" -ForegroundColor Cyan
    Remove-ClaudeOSCronEntry -LinuxHost $LinuxHost -Id $id | Out-Null
    Invoke-Register
}

function Invoke-Remove {
    Invoke-List
    $entries = Get-ClaudeOSCronEntry -LinuxHost $LinuxHost
    if ($entries.Count -eq 0) { return }
    $id = Read-Host "  削除対象の ID"
    try {
        $removed = Remove-ClaudeOSCronEntry -LinuxHost $LinuxHost -Id $id
        if ($removed -gt 0) {
            Write-Host "  [OK] 削除しました: ID=$id" -ForegroundColor Green
        }
        else {
            Write-Host "  [INFO] 該当する ID がありません" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-RemoveAll {
    $confirm = Read-Host "  全 CLAUDEOS エントリを削除します。本当によろしいですか? [y/N]"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  キャンセルしました" -ForegroundColor Yellow
        return
    }
    try {
        $removed = Remove-AllClaudeOSCronEntry -LinuxHost $LinuxHost
        Write-Host "  [OK] $removed 件削除しました" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-CronTest {
    $entries = Get-ClaudeOSCronEntry -LinuxHost $LinuxHost
    Write-Host ""

    $project  = $null
    $entryDuration = $null

    if ($entries.Count -gt 0) {
        Write-Host "  -- 実行対象プロジェクト --" -ForegroundColor Cyan
        Write-Host "    [0] プロジェクト一覧から選択" -ForegroundColor DarkGray
        for ($i = 0; $i -lt $entries.Count; $i++) {
            Write-Host ("    [{0}] {1}" -f ($i + 1), (Format-CronEntryForDisplay -Entry $entries[$i])) -ForegroundColor White
        }
        Write-Host ""
        $sel = Read-Host "  番号を入力 (0=プロジェクト一覧から選択)"
        if ($sel -eq '0') {
            $project = Select-Project
        } elseif ($sel -match '^\d+$') {
            $n = [int]$sel - 1
            if ($n -ge 0 -and $n -lt $entries.Count) {
                $project = $entries[$n].Project
                if ($entries[$n].PSObject.Properties.Name -contains 'DurationMinutes') {
                    $entryDuration = [int]$entries[$n].DurationMinutes
                }
            } else {
                Write-Host "  無効な番号です" -ForegroundColor Red
                return
            }
        } else {
            Write-Host "  無効な入力です" -ForegroundColor Red
            return
        }
    } else {
        Write-Host "  登録済みの Cron エントリがありません。プロジェクト一覧から選択します。" -ForegroundColor Yellow
        $project = Select-Project
    }

    if ([string]::IsNullOrWhiteSpace($project)) { return }

    $suggestedDuration = if ($null -ne $entryDuration) { $entryDuration } else { $defaultDuration }
    $durationInput = Read-Host "  実行時間 (分、Enter で $suggestedDuration)"
    $duration = if ([string]::IsNullOrWhiteSpace($durationInput)) { $suggestedDuration } else { [int]$durationInput }

    Write-Host ""
    Write-Host "  == 実行確認 ==" -ForegroundColor Yellow
    Write-Host "    プロジェクト  : $project"
    Write-Host "    実行時間      : $duration 分"
    Write-Host "    START_PROMPT  : プロジェクト .claude/START_PROMPT.md を参照"
    Write-Host "    ランチャー    : $launcherPath"
    Write-Host ""
    $confirm = Read-Host "  今すぐ実行しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  キャンセルしました" -ForegroundColor Yellow
        return
    }

    # SSH でバックグラウンド起動 (nohup で SSH 切断後も継続)
    $sshExe    = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { 'ssh' }
    $sshTarget = "${LinuxUser}@${LinuxHost}"
    # `$(date ...) は PowerShell 側で展開させず bash に渡す (`$ でエスケープ)
    $logPattern = "$logsDir/cron-`$(date +%Y%m%d-%H%M%S).log"
    $sshCmd    = "nohup bash $launcherPath '$project' $duration >> $logPattern 2>&1 &"

    Write-Host ""
    Write-Host "  [起動中] $project ($duration 分) ..." -ForegroundColor Cyan
    & $sshExe -T -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o ControlMaster=no `
        $sshTarget $sshCmd 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] SSH 実行に失敗しました (exit=$LASTEXITCODE)" -ForegroundColor Red
        return
    }
    Write-Host "  [OK] バックグラウンド起動完了" -ForegroundColor Green

    # ライブログ監視タブを開く (Watch-ClaudeLog.ps1 がログ検出後にセッション情報タブも自動展開)
    $watchScript = Join-Path $ScriptRoot 'scripts\tools\Watch-ClaudeLog.ps1'
    $psExe = (Get-Process -Id $PID).Path
    $wtExe = Get-Command wt.exe -ErrorAction SilentlyContinue

    if ($wtExe -and (Test-Path $watchScript)) {
        $psArgs = @(
            '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $watchScript,
            '-WithSessionInfoTab'
        )
        $wtArgs = @('-w', '0', 'new-tab', '--title', 'Claude-Live-Log', '--', $psExe) + $psArgs
        Start-Process -FilePath $wtExe.Source -ArgumentList $wtArgs -WindowStyle Hidden
        Write-Host "  [OK] ライブログ監視タブを開きました" -ForegroundColor Cyan
        Write-Host "       ログ検出後にセッション情報タブが自動で開きます" -ForegroundColor DarkGray
    } else {
        if (-not $wtExe) {
            Write-Host "  [INFO] wt.exe 非検出: タブを自動で開けません" -ForegroundColor Yellow
        } elseif (-not (Test-Path $watchScript)) {
            Write-Host "  [WARN] Watch-ClaudeLog.ps1 が見つかりません: $watchScript" -ForegroundColor Yellow
        }
        Write-Host "  ログ確認: ssh $sshTarget 'ls -t $logsDir/cron-*.log | head -1'" -ForegroundColor DarkGray
    }
}

if ($NonInteractive) { exit 0 }

while ($true) {
    Show-CronMenu
    $choice = Read-Host "  番号を入力"
    switch ($choice) {
        '1' { Invoke-Register; Read-Host "  Enter で戻ります" | Out-Null }
        '2' { Invoke-List; Read-Host "  Enter で戻ります" | Out-Null }
        '3' { Invoke-Edit; Read-Host "  Enter で戻ります" | Out-Null }
        '4' { Invoke-Remove; Read-Host "  Enter で戻ります" | Out-Null }
        '5' { Invoke-RemoveAll; Read-Host "  Enter で戻ります" | Out-Null }
        '6' { Invoke-CronTest; Read-Host "  Enter で戻ります" | Out-Null }
        '0' { exit 0 }
        default {
            Write-Host "  無効な入力" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
