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

# Disable conhost QuickEdit: accidental click-select otherwise blocks stdout
# until Enter/Esc, freezing this monitoring tab. Windows Terminal selection is
# independent of this flag so copy/paste still works in WT.
if (-not ('ClaudeConsoleMode' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ClaudeConsoleMode {
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool SetConsoleMode(IntPtr h, uint m);
    public static void DisableQuickEdit() {
        IntPtr h = GetStdHandle(-10);
        uint m;
        if (!GetConsoleMode(h, out m)) { return; }
        // ENABLE_EXTENDED_FLAGS(0x80) must be set for the change to stick.
        m = (m | 0x80u) & ~0x40u;
        SetConsoleMode(h, m);
    }
}
'@ -ErrorAction SilentlyContinue
    } catch { $null = $_ }
}
try { [ClaudeConsoleMode]::DisableQuickEdit() } catch { $null = $_ }

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\SessionTabManager.psm1') -Force -DisableNameChecking

function Format-Duration {
    param([TimeSpan]$Span)
    if ($Span.TotalSeconds -lt 0) { return '00:00:00' }
    # [int] は銀行丸めで繰上げてしまうため Math.Floor で切り捨てる
    return "{0:00}:{1:00}:{2:00}" -f [int][Math]::Floor($Span.TotalHours), $Span.Minutes, $Span.Seconds
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) {
        'running'   { return 'Green' }
        'completed' { return 'Green' }
        'exited'    { return 'Cyan' }
        'cancelled' { return 'Yellow' }
        'failed'    { return 'Red' }
        'timeout'   { return 'Cyan' }
        default     { return 'Gray' }
    }
}

function Get-ProjectPhase {
    param([int]$Week)
    if ($Week -le  8) { return @{ Name='Build';     Range='Week 1-8';   WeekInPhase=$Week;                          PhaseWeeks=8 } }
    if ($Week -le 16) { return @{ Name='Quality';   Range='Week 9-16';  WeekInPhase=$Week-8;                        PhaseWeeks=8 } }
    if ($Week -le 20) { return @{ Name='Stabilize'; Range='Week 17-20'; WeekInPhase=$Week-16;                       PhaseWeeks=4 } }
    return               @{ Name='Release';   Range='Week 21-24'; WeekInPhase=[Math]::Min($Week-20,4); PhaseWeeks=4 }
}

function New-ProgressBar {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function returns in-memory string; no persistent state is modified')]
    param([double]$Pct, [int]$Width = 20)
    $filled = [int][Math]::Round($Pct / 100 * $Width)
    $filled = [Math]::Max(0, [Math]::Min($filled, $Width))
    $bar = ('=' * $Width).ToCharArray()
    if ($filled -lt $Width) {
        for ($i = 0; $i -lt $Width; $i++) { $bar[$i] = if ($i -lt $filled) { '=' } else { ' ' } }
        $bar[$filled] = [char]'o'
    }
    return "[{0}]" -f (-join $bar)
}

function Show-ProjectTimeline {
    param([pscustomobject]$Session)

    $regDateStr  = if ($Session.PSObject.Properties.Name -contains 'project_registration_date') { "$($Session.project_registration_date)" } else { '' }
    $deadlineStr = if ($Session.PSObject.Properties.Name -contains 'project_release_deadline')  { "$($Session.project_release_deadline)"  } else { '' }
    $durMonths   = if ($Session.PSObject.Properties.Name -contains 'project_duration_months' -and $Session.project_duration_months) { [int]$Session.project_duration_months } else { 6 }

    if ([string]::IsNullOrWhiteSpace($regDateStr)) { return }

    try { $regDate = [datetime]::Parse($regDateStr) } catch { return }

    $today     = [datetime]::Today
    $totalDays = if (-not [string]::IsNullOrWhiteSpace($deadlineStr)) {
        try { ([datetime]::Parse($deadlineStr) - $regDate).TotalDays } catch { $durMonths * 30.44 }
    } else { $durMonths * 30.44 }

    $elapsed    = [Math]::Max(0, ($today - $regDate).TotalDays)
    $remaining  = $totalDays - $elapsed
    $pct        = [Math]::Min(100, [Math]::Max(0, $elapsed / $totalDays * 100))
    $week       = [int][Math]::Max(1, [Math]::Ceiling($elapsed / 7))
    $totalWeeks = [int][Math]::Ceiling($totalDays / 7)
    $phase      = Get-ProjectPhase -Week $week

    $deadlineDisplay = if (-not [string]::IsNullOrWhiteSpace($deadlineStr)) { $deadlineStr } else { "+${durMonths}M" }
    $remainColor     = if ($remaining -lt 30) { 'Red' } elseif ($remaining -lt 60) { 'Yellow' } else { 'Green' }

    Write-Host ("  " + ([char]9552).ToString() * 52) -ForegroundColor DarkCyan
    Write-Host ("   [Timeline] Project Timeline") -ForegroundColor Cyan
    Write-Host ("  " + ([char]9472).ToString() * 52) -ForegroundColor DarkCyan
    Write-Host ("   登録開始: $regDateStr   期限: $deadlineDisplay") -ForegroundColor White
    Write-Host ("   Week $week / $totalWeeks  >  $($phase.Name) Phase  ($($phase.Range))") -ForegroundColor Yellow
    Write-Host ""
    $bar = New-ProgressBar -Pct $pct
    Write-Host ("   全体  $bar  {0:0}%  ({1:0}日 / {2:0}日)" -f $pct, $elapsed, $totalDays) -ForegroundColor Green
    Write-Host ("   残り  {0:0} 日  ($deadlineDisplay まで)" -f $remaining) -ForegroundColor $remainColor
    Write-Host ("  " + ([char]9552).ToString() * 52) -ForegroundColor DarkCyan
    Write-Host ""
}

function Show-SessionFrame {
    param([pscustomobject]$Session)

    Clear-Host
    # Use DateTimeOffset to preserve TZ info from Linux `date -Iseconds` output.
    # Compute end from start + max_duration_minutes to avoid end_time_planned TZ drift.
    $start    = [datetimeoffset]::Parse($Session.start_time)
    $duration = [TimeSpan]::FromMinutes($Session.max_duration_minutes)
    $now      = [datetimeoffset]::Now

    $elapsed       = $now - $start
    $endComputed   = $start + $duration
    $remaining     = $endComputed - $now

    $statusColor = Get-StatusColor -Status $Session.status
    $title = "Claude Session Info — $($Session.project)"

    Write-Host ""
    Write-Host ("  " + "=" * 52) -ForegroundColor Cyan
    Write-Host ("   $title") -ForegroundColor Cyan
    Write-Host ("  " + "=" * 52) -ForegroundColor Cyan
    Write-Host ""
    Show-ProjectTimeline -Session $Session
    Write-Host ("   Session ID : " + $Session.sessionId) -ForegroundColor DarkGray
    Write-Host ("   Trigger    : " + $Session.trigger) -ForegroundColor Gray
    Write-Host ""
    Write-Host ("   開始時刻   : " + $start.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
    Write-Host ("   終了予定   : " + $endComputed.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
    Write-Host ("   作業時間   : " + ("{0}h {1:00}m ({2} 分)" -f [int][Math]::Floor($duration.TotalHours), $duration.Minutes, $Session.max_duration_minutes)) -ForegroundColor White
    Write-Host ""
    Write-Host ("   経過       : " + (Format-Duration -Span $elapsed)) -ForegroundColor Yellow
    Write-Host ("   残り       : " + (Format-Duration -Span $remaining)) -ForegroundColor Yellow
    Write-Host ""
    Write-Host ("   Status     : " + $Session.status) -ForegroundColor $statusColor
    Write-Host ""
    Write-Host ("  " + "-" * 52) -ForegroundColor DarkGray
    Write-Host ("   Last update: " + $now.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ("   Ctrl+C でこのタブを閉じる（セッション本体は継続）") -ForegroundColor DarkGray
    Write-Host ("   Enterキーで更新可能") -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("   再起動コマンド（コピペ可）:") -ForegroundColor DarkGray
    $restartCmd = '& "{0}" -SessionId "{1}"' -f $PSCommandPath, $SessionId
    Write-Host ("   " + $restartCmd) -ForegroundColor Gray
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

        if ($session.status -in @('completed', 'exited', 'cancelled', 'failed', 'timeout')) {
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
