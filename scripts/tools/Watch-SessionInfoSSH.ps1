<#
.SYNOPSIS
    Linux側の session.json を SSH 経由でリアルタイム監視して表示する。
.DESCRIPTION
    cron-launcher.sh が生成する session.json を SSH 経由で 1 秒ごとに読み取り、
    開始時刻・終了予定・残り時間・status を整形表示する。
    セッション終了を検知すると自動的に閉じる。
    ClaudeOS v3.2.15
.PARAMETER SessionId
    監視するセッション ID (例: 20260417-120000-myproject)。
.PARAMETER LinuxHost
    SSH接続先ホスト名。
.PARAMETER SessionsDir
    Linux 側の sessions ディレクトリパス。既定: /home/kensan/.claudeos/sessions
.PARAMETER PollIntervalSeconds
    ポーリング間隔（秒）。既定: 1。
.PARAMETER AutoCloseAfterExitSeconds
    セッション終了後に自動クローズするまでの秒数。既定: 10。
#>

param(
    [Parameter(Mandatory)][string]$SessionId,
    [Parameter(Mandatory)][string]$LinuxHost,
    [string]$SessionsDir = '/home/kensan/.claudeos/sessions',
    [int]$PollIntervalSeconds = 1,
    [int]$AutoCloseAfterExitSeconds = 10
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-Duration {
    param([TimeSpan]$Span)
    if ($Span.TotalSeconds -lt 0) { return '00:00:00' }
    return "{0:00}:{1:00}:{2:00}" -f [int]$Span.TotalHours, $Span.Minutes, $Span.Seconds
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) {
        'running'   { return 'Green' }
        'completed' { return 'Green' }
        'timeout'   { return 'Cyan' }
        'exited'    { return 'Cyan' }
        'cancelled' { return 'Yellow' }
        'failed'    { return 'Red' }
        default     { return 'Gray' }
    }
}

function Get-RemoteSession {
    $sessionFile = "$SessionsDir/${SessionId}.json"
    $json = ssh "kensan@$LinuxHost" "cat '$sessionFile' 2>/dev/null" 2>$null
    if ($null -eq $json -or [string]::IsNullOrWhiteSpace($json)) { return $null }
    try { return ($json | ConvertFrom-Json) }
    catch { return $null }
}

function Show-SessionFrame {
    param([pscustomobject]$Session)
    Clear-Host
    $start     = [datetime]::Parse($Session.start_time)
    $end       = [datetime]::Parse($Session.end_time_planned)
    $now       = Get-Date
    $elapsed   = $now - $start
    $remaining = $end - $now
    $duration  = [TimeSpan]::FromMinutes($Session.max_duration_minutes)
    $statusColor = Get-StatusColor -Status $Session.status

    Write-Host ''
    Write-Host ('  ' + '=' * 52) -ForegroundColor Cyan
    Write-Host ("   Claude Session Info — $($Session.project)") -ForegroundColor Cyan
    Write-Host ('  ' + '=' * 52) -ForegroundColor Cyan
    Write-Host ''
    Write-Host ("   Session ID : " + $Session.sessionId) -ForegroundColor DarkGray
    Write-Host ("   Host       : " + $LinuxHost) -ForegroundColor DarkGray
    Write-Host ("   Trigger    : " + $Session.trigger) -ForegroundColor Gray
    Write-Host ''
    Write-Host ("   開始時刻   : " + $start.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
    Write-Host ("   終了予定   : " + $end.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
    Write-Host ("   作業時間   : " + ("{0}h {1:00}m" -f [int]$duration.TotalHours, $duration.Minutes)) -ForegroundColor White
    Write-Host ''
    Write-Host ("   経過       : " + (Format-Duration -Span $elapsed)) -ForegroundColor Yellow
    Write-Host ("   残り       : " + (Format-Duration -Span $remaining)) -ForegroundColor Yellow
    Write-Host ''
    Write-Host ("   Status     : " + $Session.status) -ForegroundColor $statusColor
    Write-Host ''
    Write-Host ('  ' + '-' * 52) -ForegroundColor DarkGray
    Write-Host ("   Last update: " + $now.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host '   Ctrl+C でこのタブを閉じる（セッション本体は継続）' -ForegroundColor DarkGray
    Write-Host ''
}

# 初期ヘッダー
Clear-Host
Write-Host ''
Write-Host ('  ' + '=' * 52) -ForegroundColor Cyan
Write-Host '   Claude Session Info (SSH)' -ForegroundColor Cyan
Write-Host "   Host : $LinuxHost" -ForegroundColor DarkCyan
Write-Host "   ID   : $SessionId" -ForegroundColor DarkCyan
Write-Host ('  ' + '=' * 52) -ForegroundColor Cyan
Write-Host ''
Write-Host '  セッション情報を取得中...' -ForegroundColor Yellow

try {
    while ($true) {
        $session = Get-RemoteSession
        if ($null -eq $session) {
            Clear-Host
            Write-Host ''
            Write-Host "  セッション情報が見つかりません: $SessionId" -ForegroundColor Red
            Write-Host "  Host: $LinuxHost  Dir: $SessionsDir" -ForegroundColor DarkGray
            Start-Sleep -Seconds 3
            continue
        }

        Show-SessionFrame -Session $session

        if ($session.status -in @('completed', 'timeout', 'exited', 'cancelled', 'failed')) {
            Write-Host ("   -> セッション終了 ({0})。{1} 秒後に閉じます..." -f $session.status, $AutoCloseAfterExitSeconds) -ForegroundColor Magenta
            Start-Sleep -Seconds $AutoCloseAfterExitSeconds
            exit 0
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
catch {
    Write-Host ''
    Write-Host "  Watch-SessionInfoSSH でエラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
