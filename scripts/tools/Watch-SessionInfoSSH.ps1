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
    [string]$LinuxUser = 'kensan',
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
    <#
    .SYNOPSIS
        SSH 経由で session.json を取得しパース。JSON 破損時のみ 1 回即時リトライ。
        SSH 接続失敗 / ファイル不存在 / パース失敗をそれぞれ別 Status で区別する。
    .OUTPUTS
        pscustomobject @{
            Session = <parsed or null>;
            Status  = 'ok' | 'empty' | 'parse_error' | 'ssh_error';
            Raw     = <json or null>;
            ExitCode = <int, ssh_error 時のみ>
        }
    #>
    $sessionFile = "$SessionsDir/${SessionId}.json"
    # POSIX shell エスケープ — SessionId / SessionsDir にシングルクォートが混入しても
    # リモートコマンドインジェクションにならないよう必ず quote する
    $quotedSessionFile = "'" + ($sessionFile -replace "'", "'\''") + "'"
    foreach ($attempt in 1..2) {
        # SSH exit code を捕捉するため stderr 握りつぶしを外し、cat の exit を分離
        $json = ssh "${LinuxUser}@$LinuxHost" "cat $quotedSessionFile 2>/dev/null || true" 2>$null
        $sshExit = $LASTEXITCODE
        if ($sshExit -ne 0) {
            return [pscustomobject]@{
                Session = $null; Status = 'ssh_error'; Raw = $null; ExitCode = $sshExit
            }
        }
        if ($null -eq $json -or [string]::IsNullOrWhiteSpace($json)) {
            return [pscustomobject]@{ Session = $null; Status = 'empty'; Raw = $null }
        }
        try {
            return [pscustomobject]@{ Session = ($json | ConvertFrom-Json); Status = 'ok'; Raw = $json }
        } catch {
            if ($attempt -eq 1) {
                # 書き込み途中の可能性 — 短時間待って再取得（破損時のみリトライ）
                Start-Sleep -Milliseconds 200
                continue
            }
            return [pscustomobject]@{ Session = $null; Status = 'parse_error'; Raw = $json }
        }
    }
}

function Show-SessionFrame {
    param(
        [pscustomobject]$Session,
        [datetime]$LastValidReadAt,
        [bool]$IsStale
    )
    Clear-Host
    # DateTimeOffset でタイムゾーン情報を保持（Linux `date -Iseconds` はタイムゾーン付きを返す）
    $start     = [datetimeoffset]::Parse($Session.start_time)
    $end       = [datetimeoffset]::Parse($Session.end_time_planned)
    $now       = [datetimeoffset]::Now
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
    $readTag = $LastValidReadAt.ToString('yyyy-MM-dd HH:mm:ss')
    if ($IsStale) {
        $age = [int]($now - [datetimeoffset]$LastValidReadAt).TotalSeconds
        Write-Host ("   [STALE] 前回値を表示中 (最終有効読取: $readTag / $age 秒前)") -ForegroundColor Red
    } else {
        Write-Host ("   Last valid read: $readTag") -ForegroundColor DarkGray
    }
    Write-Host ("   Now: " + $now.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
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

$lastValidSession   = $null
$lastValidReadAt    = Get-Date

try {
    while ($true) {
        $result = Get-RemoteSession

        if ($result.Status -eq 'ok') {
            $lastValidSession = $result.Session
            $lastValidReadAt  = Get-Date
            Show-SessionFrame -Session $lastValidSession -LastValidReadAt $lastValidReadAt -IsStale:$false

            if ($lastValidSession.status -in @('completed', 'timeout', 'exited', 'cancelled', 'failed')) {
                Write-Host ("   -> セッション終了 ({0})。{1} 秒後に閉じます..." -f $lastValidSession.status, $AutoCloseAfterExitSeconds) -ForegroundColor Magenta
                Start-Sleep -Seconds $AutoCloseAfterExitSeconds
                exit 0
            }
        }
        elseif ($result.Status -eq 'ssh_error' -and $null -ne $lastValidSession) {
            # SSH 接続断 — 前回値を STALE 表示し、exit code も併記
            Show-SessionFrame -Session $lastValidSession -LastValidReadAt $lastValidReadAt -IsStale:$true
            Write-Host ("   ⚠ SSH 接続失敗 (exit $($result.ExitCode)) — キャッシュ値を表示中") -ForegroundColor Red
        }
        elseif ($result.Status -eq 'parse_error' -and $null -ne $lastValidSession) {
            # 破損検出 — 前回値を STALE として表示し続ける
            Show-SessionFrame -Session $lastValidSession -LastValidReadAt $lastValidReadAt -IsStale:$true
            Write-Host '   ⚠ JSON パース失敗 (書き込み中の可能性) — キャッシュ値を表示中' -ForegroundColor Yellow
        }
        elseif ($null -ne $lastValidSession) {
            # empty（ファイル一時消失）だが過去に有効値あり → キャッシュ継続
            Show-SessionFrame -Session $lastValidSession -LastValidReadAt $lastValidReadAt -IsStale:$true
            Write-Host '   ⚠ セッションファイル消失 — キャッシュ値を表示中' -ForegroundColor DarkYellow
        }
        else {
            Clear-Host
            Write-Host ''
            $msg = switch ($result.Status) {
                'empty'       { "セッション情報ファイル未作成: $SessionId" }
                'parse_error' { "JSON パース失敗 (書き込み中 or 破損): $SessionId" }
                'ssh_error'   { "SSH 接続失敗 (exit $($result.ExitCode)): ${LinuxUser}@$LinuxHost" }
                default       { "セッション情報取得失敗 (Status: $($result.Status)): $SessionId" }
            }
            Write-Host "  $msg" -ForegroundColor Red
            Write-Host "  Host: $LinuxHost  Dir: $SessionsDir" -ForegroundColor DarkGray
            Start-Sleep -Seconds 3
            continue
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
catch {
    Write-Host ''
    Write-Host "  Watch-SessionInfoSSH でエラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
