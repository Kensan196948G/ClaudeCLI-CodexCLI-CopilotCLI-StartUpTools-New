<#
.SYNOPSIS
    メニュー13: Claude セッション起動・監視タブ。
.DESCRIPTION
    ClaudeOS v3.2.104
    起動時に以下を順に試みる:
      1. 既存の claudeos-* tmux セッションがあれば即 attach
      2. 今日のCronスケジュール時刻が過ぎていてセッションが未起動なら即実行
      3. 上記に該当しなければ次の Cron 発火を待機

    セッション接続後、Session-Info タブ (Watch-SessionInfoSSH.ps1) を
    既存 WindowsTerminal ウィンドウに自動で追加する。

    -NewTab: 既存 WindowsTerminal の最後のウィンドウに新タブとして追加する。

    v3.2.104: 起動時即実行ロジック + Session-Info タブ自動オープン追加。
    v3.2.103: tail-F + 別タブ方式を廃止し tmux 直接 attach 方式に変更。
    ClaudeOS v3.2.104
.PARAMETER NewTab
    既存 WindowsTerminal ウィンドウに新タブを追加して起動する。
.PARAMETER PollIntervalSeconds
    tmux セッション検出のポーリング間隔（秒）。既定: 5。
#>

param(
    [switch]$NewTab,
    [switch]$WithSessionInfoTab,   # 後方互換
    [switch]$TmuxAttach,           # 後方互換
    [int]$PollIntervalSeconds = 5
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force -DisableNameChecking

$ConfigPath  = Get-StartupConfigPath -StartupRoot $ScriptRoot
$Config      = Import-LauncherConfig -ConfigPath $ConfigPath
$LinuxHost   = $Config.linuxHost
$LinuxUser   = if ($Config.PSObject.Properties.Name -contains 'linuxUser' -and
                    -not [string]::IsNullOrWhiteSpace($Config.linuxUser)) { $Config.linuxUser } else { 'kensan' }
$SshTarget   = "${LinuxUser}@${LinuxHost}"
$SessionsDir = '/home/kensan/.claudeos/sessions'
$LauncherPath = '/home/kensan/.claudeos/cron-launcher.sh'
$LogsDir      = '/home/kensan/.claudeos/logs'

if ($Config.PSObject.Properties.Name -contains 'cron') {
    $c = $Config.cron
    if ($c.PSObject.Properties.Name -contains 'sessionsDir') { $SessionsDir  = $c.sessionsDir }
    if ($c.PSObject.Properties.Name -contains 'launcherPath'){ $LauncherPath = $c.launcherPath }
    if ($c.PSObject.Properties.Name -contains 'logsDir')     { $LogsDir      = $c.logsDir }
}

if ([string]::IsNullOrWhiteSpace($LinuxHost) -or $LinuxHost -eq '<your-linux-host>') {
    Write-Host '[ERROR] config.json の linuxHost が未設定です。' -ForegroundColor Red
    exit 1
}

# ─── pwsh / wt 解決（-NewTab 用）──────────────────────────────────────────────

function Get-PwshExe {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    foreach ($p in @('C:\Program Files\PowerShell\7\pwsh.exe', "$env:ProgramFiles\PowerShell\7\pwsh.exe")) {
        if (Test-Path $p) { return $p }
    }
    return (Get-Process -Id $PID).Path
}
$PwshExe = Get-PwshExe

function Get-WtPwshProfile {
    foreach ($p in @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    )) {
        if (-not (Test-Path $p)) { continue }
        try {
            $profiles = @((Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json).profiles.list) |
                Where-Object { $_.commandline -match 'pwsh\.exe' -and -not $_.hidden }
            if ($profiles.Count -gt 0) {
                if ($profiles[0].guid) { return $profiles[0].guid }
                if ($profiles[0].name) { return $profiles[0].name }
            }
        } catch { $null = $_ }
    }
    return '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
}
$WtProfileName = if ($env:AI_STARTUP_WT_PROFILE) { $env:AI_STARTUP_WT_PROFILE } else { Get-WtPwshProfile }

# ─── -NewTab モード ──────────────────────────────────────────────────────────
# .cmd ランチャー経由でスペース入りパス問題を回避。& 演算子で WT コンテキストを継承。

if ($NewTab) {
    $wtExe       = Get-Command wt.exe -ErrorAction SilentlyContinue
    $launcherCmd = Join-Path $PSScriptRoot 'Watch-ClaudeLog-Launcher.cmd'

    if ($wtExe -and (Test-Path $launcherCmd)) {
        $wtArgs = @('-w', 'last', 'new-tab', '-p', $WtProfileName,
                    '--title', 'Claude-Live-Log', '--commandline', $launcherCmd)
        & $wtExe.Source @wtArgs
        Write-Host '[INFO] Claude-Live-Log タブを既存 WindowsTerminal に追加しました。' -ForegroundColor Cyan
    } else {
        Start-Process -FilePath $PwshExe -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) -WindowStyle Normal
        Write-Host '[INFO] Claude Live Log ウィンドウを開きました。' -ForegroundColor Yellow
    }
    exit 0
}

# ─── ヘッダー表示 ────────────────────────────────────────────────────────────

function Write-WaitHeader {
    Clear-Host
    Write-Host ''
    Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
    Write-Host '   Claude Code セッション監視' -ForegroundColor Cyan
    Write-Host "   Host : $LinuxHost" -ForegroundColor DarkCyan
    Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  次の Cron 発火を待機中...' -ForegroundColor Yellow
    Write-Host '  Ctrl+C でこのタブを終了します。' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-AttachHeader {
    param([string]$Session)
    Clear-Host
    Write-Host ''
    Write-Host ('  ' + '=' * 54) -ForegroundColor Green
    Write-Host "   接続: $Session" -ForegroundColor Green
    Write-Host "   Ctrl+B → D : デタッチ（Claude セッションは継続）" -ForegroundColor DarkGray
    Write-Host ('  ' + '=' * 54) -ForegroundColor Green
    Write-Host ''
}

# ─── SSH ヘルパ ──────────────────────────────────────────────────────────────

function Invoke-Ssh {
    param([string]$Cmd)
    $result = & ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new `
        -o ControlMaster=no $SshTarget $Cmd 2>$null
    return $result
}

# 現在動いている claudeos-* tmux セッション名を返す（なければ空文字）
function Get-RunningTmuxSession {
    $raw = Invoke-Ssh "tmux ls 2>/dev/null | grep '^claudeos-'"
    if (-not $raw) { return '' }
    $line = ($raw -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    return $(if ($line) { ($line -split ':')[0].Trim() } else { '' })
}

# 今日の曜日 (0=日..6=土) でスケジュール時刻が現在より過去のプロジェクトを返す
function Get-OverdueCronProject {
    $script = @'
DOW=$(date +%w)
NOW_MIN=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
crontab -l 2>/dev/null | grep 'cron-launcher.sh' | grep -v '^#' | while IFS= read -r line; do
  MIN=$(echo "$line"  | awk '{print $1}')
  HOUR=$(echo "$line" | awk '{print $2}')
  DOW_FIELD=$(echo "$line" | awk '{print $5}')
  PROJECT=$(echo "$line" | grep -oP 'cron-launcher\.sh \K\S+')
  [ -z "$PROJECT" ] && continue
  SCHED=$(( 10#$HOUR * 60 + 10#$MIN ))
  if echo ",$DOW_FIELD," | grep -qE ",$DOW," || [ "$DOW_FIELD" = "*" ]; then
    if [ "$SCHED" -le "$NOW_MIN" ]; then
      echo "$PROJECT|$SCHED"
    fi
  fi
done | sort -t'|' -k2 -rn | head -1 | cut -d'|' -f1
'@
    $result = Invoke-Ssh $script
    return $(if ($result) { $result.Trim() } else { '' })
}

# cron-launcher.sh をバックグラウンドで即実行し、起動したセッション名を返す
function Start-CronSession {
    param([string]$Project, [int]$DurationMin = 300)
    $safeName  = $Project -replace '[^A-Za-z0-9_-]', '_'
    $logFile   = "$LogsDir/cron-`$(date +%Y%m%d-%H%M%S).log"
    $launchCmd = "nohup bash $LauncherPath '$Project' $DurationMin >> $logFile 2>&1 &"
    Invoke-Ssh "mkdir -p $LogsDir && $launchCmd" | Out-Null

    Write-Host "  [起動中] $Project (${DurationMin}min) ..." -ForegroundColor Cyan
    # tmux セッションが現れるまで最大 30 秒待機
    $targetName = "claudeos-$safeName"
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 2
        $sess = Get-RunningTmuxSession
        if ($sess -eq $targetName) {
            Write-Host "  [OK] tmux セッション起動確認: $sess" -ForegroundColor Green
            return $sess
        }
    }
    Write-Host "  [WARN] tmux セッションの起動を確認できませんでした。" -ForegroundColor Yellow
    return ''
}

# 最新 session.json から SessionId を取得
function Get-LatestSessionId {
    param([string]$TmuxSession)
    # セッション名から SAFE_PROJECT を逆引き: "claudeos-SAFE" → SAFE
    $safe = $TmuxSession -replace '^claudeos-', ''
    $result = Invoke-Ssh "ls -t '$SessionsDir/'*-${safe}.json 2>/dev/null | head -1"
    if (-not $result) { return '' }
    return ([System.IO.Path]::GetFileNameWithoutExtension($result.Trim()))
}

# Session-Info タブを既存 WT ウィンドウに追加する
function Open-SessionInfoTab {
    param([string]$SessionId)
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return }

    $wtExe    = Get-Command wt.exe -ErrorAction SilentlyContinue
    $siScript = Join-Path $PSScriptRoot 'Watch-SessionInfoSSH.ps1'
    if (-not $wtExe -or -not (Test-Path $siScript)) { return }

    # Session-Info 用の .cmd ランチャーを一時生成（スペース入りパス回避）
    $tmpCmd = Join-Path $env:TEMP 'ClaudeOS-SessionInfo-Launcher.cmd'
    @"
@echo off
pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -File "$siScript" -SessionId "$SessionId" -LinuxHost "$LinuxHost" -LinuxUser "$LinuxUser" -SessionsDir "$SessionsDir"
"@ | Set-Content $tmpCmd -Encoding ASCII

    $wtArgs = @('-w', 'last', 'new-tab', '-p', $WtProfileName,
                '--title', 'Session-Info', '--commandline', $tmpCmd)
    & $wtExe.Source @wtArgs
    Write-Host "  [+] Session-Info タブを開きました: $SessionId" -ForegroundColor DarkCyan
}

# tmux attach（フォアグラウンド）を実行し、Session-Info タブも開く
function Connect-TmuxSession {
    param([string]$TmuxSession)

    Write-AttachHeader -Session $TmuxSession

    # Session-Info タブを開く（attach と並行）
    $sessionId = Get-LatestSessionId -TmuxSession $TmuxSession
    if ($sessionId) { Open-SessionInfoTab -SessionId $sessionId }

    # フォアグラウンドで attach（-tt で強制 TTY 割り当て）
    & ssh -tt $SshTarget "tmux attach-session -t '$TmuxSession'" 2>$null

    Write-Host ''
    Write-Host '  セッション終了またはデタッチしました。' -ForegroundColor Yellow
    Write-Host '  次の Cron 発火を待機中...' -ForegroundColor DarkGray
    Write-Host ''
    Start-Sleep -Seconds 2
}

# ─── 起動時即実行ロジック ─────────────────────────────────────────────────────

Write-Host ''
Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
Write-Host '   Claude Code セッション監視 — 起動チェック中...' -ForegroundColor Cyan
Write-Host "   Host : $LinuxHost" -ForegroundColor DarkCyan
Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
Write-Host ''

# ① 既存 tmux セッションがあれば即 attach
$existing = Get-RunningTmuxSession
if ($existing) {
    Write-Host "  [検出] 実行中セッション: $existing" -ForegroundColor Green
    Connect-TmuxSession -TmuxSession $existing
    $lastSession = $existing
} else {
    # ② 今日のCron時刻が過ぎていれば即起動
    Write-Host '  実行中セッションなし。今日のCronスケジュールを確認中...' -ForegroundColor DarkGray
    $overdueProject = Get-OverdueCronProject
    if ($overdueProject) {
        Write-Host "  [即実行] スケジュール時刻超過: $overdueProject" -ForegroundColor Yellow
        $newSession = Start-CronSession -Project $overdueProject
        if ($newSession) {
            Connect-TmuxSession -TmuxSession $newSession
            $lastSession = $newSession
        } else {
            $lastSession = ''
        }
    } else {
        Write-Host '  本日の実行時刻はまだ先です。発火を待機します。' -ForegroundColor DarkGray
        $lastSession = ''
    }
}

# ─── 監視ループ（セッション終了後・次回発火待機）────────────────────────────

Write-WaitHeader
$dotCount = 0

while ($true) {
    $current = Get-RunningTmuxSession

    if ($current -and ($current -ne $lastSession)) {
        Write-Host ''
        Write-Host "  [新規発火] $current" -ForegroundColor Green
        Connect-TmuxSession -TmuxSession $current
        $lastSession = $current
        $dotCount    = 0
        Write-WaitHeader
    } else {
        Write-Host '.' -NoNewline -ForegroundColor DarkGray
        $dotCount++
        if ($dotCount -ge 60) { Write-Host ''; $dotCount = 0 }
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}
