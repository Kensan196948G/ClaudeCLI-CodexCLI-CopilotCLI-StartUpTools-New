<#
.SYNOPSIS
    Claude Code ログをリアルタイム監視する（SSH + tail -f）。
.DESCRIPTION
    Linux 側の cron-launcher.sh が出力するログファイルを自動検出し
    Windows Terminal の新規タブで tail -f を開始する。
    cron 実行前に起動しておくと、発火を検知して自動でログ表示を開始する。
    ClaudeOS v3.2.31
.PARAMETER NewTab
    Windows Terminal の新規タブで開く（既定: 現在のウィンドウで実行）。
.PARAMETER PollIntervalSeconds
    ログファイル検出のポーリング間隔（秒）。既定: 5。
.PARAMETER WithSessionInfoTab
    新しいセッション検出時に Session Info タブを自動で開く。
#>

param(
    [switch]$NewTab,
    [switch]$WithSessionInfoTab,
    [int]$PollIntervalSeconds = 5
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force -DisableNameChecking

$ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot
$Config     = Import-LauncherConfig -ConfigPath $ConfigPath
$LinuxHost  = $Config.linuxHost
$LinuxUser  = if ($Config.PSObject.Properties.Name -contains 'linuxUser' -and -not [string]::IsNullOrWhiteSpace($Config.linuxUser)) { $Config.linuxUser } else { 'kensan' }
$SshTarget  = "${LinuxUser}@${LinuxHost}"

$LogsDir = '/home/kensan/.claudeos/logs'
if ($Config.PSObject.Properties.Name -contains 'cron' -and
    $Config.cron.PSObject.Properties.Name -contains 'logsDir') {
    $LogsDir = $Config.cron.logsDir
}

$SessionsDir = '/home/kensan/.claudeos/sessions'
if ($Config.PSObject.Properties.Name -contains 'cron' -and
    $Config.cron.PSObject.Properties.Name -contains 'sessionsDir') {
    $SessionsDir = $Config.cron.sessionsDir
}

if ([string]::IsNullOrWhiteSpace($LinuxHost) -or $LinuxHost -eq '<your-linux-host>') {
    Write-Host '[ERROR] config.json の linuxHost が未設定です。' -ForegroundColor Red
    exit 1
}

# NewTab モード: 自身を新しい Windows Terminal タブで再起動
if ($NewTab) {
    $psExe  = (Get-Process -Id $PID).Path
    $wtExe  = Get-Command wt.exe -ErrorAction SilentlyContinue
    $myPath = $PSCommandPath

    # $PSCommandPath が空の場合（dot-source 経由など）はガード
    if ([string]::IsNullOrWhiteSpace($myPath)) {
        Write-Host '[ERROR] -NewTab モードは PSCommandPath が空のため使用できません。直接ファイルパスを指定して実行してください。' -ForegroundColor Red
        exit 1
    }

    $psArgs = @(
        '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $myPath,
        '-PollIntervalSeconds', $PollIntervalSeconds
    )
    if ($WithSessionInfoTab) { $psArgs += '-WithSessionInfoTab' }

    if ($wtExe) {
        $wtArgs = @('-w', '0', 'new-tab', '--title', 'Claude-Live-Log', '--', $psExe) + $psArgs
        Start-Process -FilePath $wtExe.Source -ArgumentList $wtArgs -WindowStyle Hidden
        Write-Host '[INFO] Claude-Live-Log タブを開きました。' -ForegroundColor Cyan
    } else {
        Start-Process -FilePath $psExe -ArgumentList $psArgs -WindowStyle Normal
        Write-Host '[INFO] Claude Live Log ウィンドウを開きました（wt.exe 非検出）。' -ForegroundColor Yellow
    }
    exit 0
}

# ─── 内部関数 ────────────────────────────────────────────────────────────

function Write-WaitHeader {
    Write-Host ''
    Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
    Write-Host '   Claude Code ライブログ監視' -ForegroundColor Cyan
    Write-Host "   Host : $LinuxHost" -ForegroundColor DarkCyan
    Write-Host "   Log  : (待機中)" -ForegroundColor DarkCyan
    Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  cron 発火待機中...' -ForegroundColor Yellow
    Write-Host "  ログディレクトリ: $LogsDir" -ForegroundColor DarkGray
    Write-Host ''
}

function Write-LiveHeader {
    param([string]$LogFile)
    Clear-Host
    Write-Host ''
    Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
    Write-Host '   Claude Code ライブログ監視' -ForegroundColor Cyan
    Write-Host "   Host : $LinuxHost" -ForegroundColor DarkCyan
    Write-Host "   Log  : $LogFile" -ForegroundColor DarkCyan
    Write-Host ('  ' + '=' * 54) -ForegroundColor Cyan
    Write-Host '  Ctrl+C でこのタブを閉じる（セッション本体は継続）' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-LatestLog {
    $result = ssh $SshTarget "ls -t $LogsDir/cron-*.log 2>/dev/null | head -1" 2>$null
    if ($null -eq $result) { return '' }
    return $result.Trim()
}

function Get-SessionIdForLog {
    param([string]$LogPath)
    $basename = ($LogPath -split '/')[-1]
    $stamp    = $basename -replace '^cron-', '' -replace '\.log$', ''
    $result   = ssh $SshTarget "ls '$SessionsDir/${stamp}-'*.json 2>/dev/null | head -1" 2>$null
    if ($null -eq $result -or [string]::IsNullOrWhiteSpace($result)) { return '' }
    return ($result.Trim() -split '/')[-1] -replace '\.json$', ''
}

function Open-TmuxAttachTab {
    param([string]$SessionId)
    $wtExe = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wtExe) {
        Write-Host '  [INFO] wt.exe が非検出のため Tmux Attach タブを開けません。' -ForegroundColor Yellow
        return
    }
    # SessionId = "YYYYMMDD-HHMMSS-SAFEPROJECT" → 3番目セグメントが SAFE_PROJECT
    $parts = $SessionId -split '-', 3
    if ($parts.Count -lt 3) {
        Write-Host "  [WARN] SessionId のパースに失敗しました: $SessionId" -ForegroundColor Yellow
        return
    }
    $safeProject = $parts[2]
    $tmuxSession  = "claudeos-$safeProject"
    # tmux new-session -A: attach-or-create（セッション未作成時に自動生成）
    $sshCmd       = "ssh -t $SshTarget tmux new-session -A -s $tmuxSession"
    $psExe        = (Get-Process -Id $PID).Path
    $psArgs = @(
        '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command', $sshCmd
    )
    $wtArgs = @('-w', '0', 'new-tab', '--title', 'Claude-UI', '--', $psExe) + $psArgs
    Start-Process -FilePath $wtExe.Source -ArgumentList $wtArgs -WindowStyle Hidden
    Write-Host "  Claude UI タブを開きました: tmux new-session -A -s $tmuxSession" -ForegroundColor Magenta
}

function Open-SessionInfoTab {
    param([string]$SessionId)
    $wtExe = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wtExe) {
        Write-Host '  [INFO] wt.exe が非検出のため Session Info タブを開けません。' -ForegroundColor Yellow
        return
    }
    $psExe    = (Get-Process -Id $PID).Path
    $siScript = Join-Path $PSScriptRoot 'Watch-SessionInfoSSH.ps1'
    if (-not (Test-Path $siScript)) {
        Write-Host "  [WARN] Watch-SessionInfoSSH.ps1 が見つかりません: $siScript" -ForegroundColor Yellow
        return
    }
    $psArgs = @(
        '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $siScript,
        '-SessionId', $SessionId,
        '-LinuxHost', $LinuxHost,
        '-LinuxUser', $LinuxUser,
        '-SessionsDir', $SessionsDir
    )
    $wtArgs = @('-w', '0', 'new-tab', '--title', 'Session-Info', '--', $psExe) + $psArgs
    Start-Process -FilePath $wtExe.Source -ArgumentList $wtArgs -WindowStyle Hidden
    Write-Host "  Session Info タブを開きました: $SessionId" -ForegroundColor Cyan
}

# ─── 本体: ログ監視ループ ────────────────────────────────────────────────

Write-WaitHeader

$knownLog = Get-LatestLog
# 起動時に15分以内のログがある場合は実行中と見なして即監視
if ($knownLog -match 'cron-(\d{8}-\d{6})\.log$') {
    $logTime = [datetime]::MinValue
    $parsed  = [datetime]::TryParseExact($Matches[1], 'yyyyMMdd-HHmmss', $null,
        [System.Globalization.DateTimeStyles]::None, [ref]$logTime)
    if ($parsed -and ((Get-Date) - $logTime -lt [timespan]::FromMinutes(15))) {
        $knownLog = ''  # 新規扱いにして直後のループで検出させる
    }
}
$dotCount = 0

while ($true) {
    $latest = Get-LatestLog

    # 新しいログが現れたら監視開始
    if ($latest -and ($latest -ne $knownLog)) {
        Write-LiveHeader -LogFile $latest
        Write-Host "  新しいセッション検出: $latest" -ForegroundColor Green

        if ($WithSessionInfoTab) {
            Write-Host '  Session ID を取得中...' -ForegroundColor DarkGray
            $sessionId = Get-SessionIdForLog -LogPath $latest
            if ($sessionId) {
                Open-TmuxAttachTab -SessionId $sessionId   # Tab ②: Claude UI (tmux attach)
                Start-Sleep -Seconds 1
                Open-SessionInfoTab -SessionId $sessionId  # Tab ③: Session Info
            } else {
                Write-Host '  [WARN] Session ID が見つかりませんでした。' -ForegroundColor Yellow
            }
        }

        Write-Host ''
        # tail -F でリアルタイム表示 — -F はログローテーション (inode 変化) に追従
        ssh $SshTarget "tail -n 50 -F '$latest'"
        $sshExitCode = $LASTEXITCODE
        Write-Host ''
        if ($sshExitCode -ne 0) {
            Write-Host "  [WARN] SSH が終了コード $sshExitCode で切断されました。次のポーリングへ戻ります..." -ForegroundColor Yellow
        } else {
            Write-Host '  セッション終了を検知しました。次の cron 発火を待機します...' -ForegroundColor Yellow
        }
        Write-Host ''
        $knownLog = $latest
        $dotCount = 0
        Write-WaitHeader
        continue
    }

    # 待機中ドット表示
    Write-Host '.' -NoNewline -ForegroundColor DarkGray
    $dotCount++
    if ($dotCount -ge 60) {
        Write-Host ''
        $dotCount = 0
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}
