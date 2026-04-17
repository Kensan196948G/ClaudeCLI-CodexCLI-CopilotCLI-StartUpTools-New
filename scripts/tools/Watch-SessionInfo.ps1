<#
.SYNOPSIS
    情報タブ内で実行されるセッション表示ループ。
.DESCRIPTION
    session.json を 1 秒間隔で読み直し、開始時刻 / 終了予定 / 残り時間 / status
    を整形表示する。Ctrl+C で閉じてもセッション本体には影響しない。
    ClaudeOS v3.1.0
#>

param(
    [Parameter(Mandatory)][string]$SessionId,
    [string]$SessionsDir = '',
    [int]$PollIntervalSeconds = 1,
    [int]$AutoCloseAfterExitSeconds = 10
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\SessionTabManager.psm1') -Force -DisableNameChecking

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
        'exited'    { return 'Cyan' }
        'cancelled' { return 'Yellow' }
        'failed'    { return 'Red' }
        default     { return 'Gray' }
    }
}

function Show-SessionFrame {
    param([pscustomobject]$Session)

    Clear-Host
    $start = [datetime]::Parse($Session.start_time)
    $end = [datetime]::Parse($Session.end_time_planned)
    $now = Get-Date

    $elapsed = $now - $start
    $remaining = $end - $now
    $duration = [TimeSpan]::FromMinutes($Session.max_duration_minutes)

    $statusColor = Get-StatusColor -Status $Session.status
    $title = "Claude Session Info — $($Session.project)"

    Write-Host ""
    Write-Host ("  " + "=" * 52) -ForegroundColor Cyan
    Write-Host ("   $title") -ForegroundColor Cyan
    Write-Host ("  " + "=" * 52) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("   Session ID : " + $Session.sessionId) -ForegroundColor DarkGray
    Write-Host ("   Trigger    : " + $Session.trigger) -ForegroundColor Gray
    Write-Host ""
    Write-Host ("   開始時刻   : " + $start.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
    Write-Host ("   終了予定   : " + $end.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
    Write-Host ("   作業時間   : " + ("{0}h {1:00}m ({2} 分)" -f [int]$duration.TotalHours, $duration.Minutes, $Session.max_duration_minutes)) -ForegroundColor White
    Write-Host ""
    Write-Host ("   経過       : " + (Format-Duration -Span $elapsed)) -ForegroundColor Yellow
    Write-Host ("   残り       : " + (Format-Duration -Span $remaining)) -ForegroundColor Yellow
    Write-Host ""
    Write-Host ("   Status     : " + $Session.status) -ForegroundColor $statusColor
    Write-Host ""
    Write-Host ("  " + "-" * 52) -ForegroundColor DarkGray
    Write-Host ("   Last update: " + $now.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ("   Ctrl+C でこのタブを閉じる（セッション本体は継続）") -ForegroundColor DarkGray
    Write-Host ""
}

try {
    while ($true) {
        $session = Get-SessionInfo -SessionId $SessionId -ConfigSessionsDir $SessionsDir
        if ($null -eq $session) {
            Clear-Host
            Write-Host ""
            Write-Host "  セッション情報が見つかりません: $SessionId" -ForegroundColor Red
            Write-Host "  ディレクトリ: $(Get-SessionDir -ConfigSessionsDir $SessionsDir)" -ForegroundColor DarkGray
            Start-Sleep -Seconds 3
            continue
        }

        Show-SessionFrame -Session $session

        if ($session.status -in @('completed', 'exited', 'cancelled', 'failed')) {
            Write-Host ("   -> セッション終了 ({0})。{1} 秒後に閉じます..." -f $session.status, $AutoCloseAfterExitSeconds) -ForegroundColor Magenta
            Start-Sleep -Seconds $AutoCloseAfterExitSeconds
            exit 0
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
catch {
    Write-Host ""
    Write-Host "  Watch-SessionInfo でエラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
