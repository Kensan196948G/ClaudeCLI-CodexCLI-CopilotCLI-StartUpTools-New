<#
.SYNOPSIS
    Claude Code ログをリアルタイム監視する（SSH + tail -f）。
.DESCRIPTION
    Linux 側の cron-launcher.sh が出力するログファイルを自動検出し
    Windows Terminal の新規タブで tail -f を開始する。
    cron 実行前に起動しておくと、発火を検知して自動でログ表示を開始する。
    v3.2.41 から tail -F をバックグラウンド Job 化し、ライブ表示中にも
    次の cron 発火を検出 → 自動で次セッションへ切り替える (マルチ発火対応)。
    v3.2.42 で spawn タブを強制 pwsh 7 化 + Start-Job 内 UTF-8 化 (文字化け解消)。
    v3.2.46 で wt new-tab に -p "PowerShell" を付与してタブアイコンを PS 化。
    ClaudeOS v3.2.46
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

# spawn タブ用の PowerShell exe 解決: PowerShell 7 (pwsh.exe) を最優先。
# PATH 不通でも既知インストール先を検査し、最終 fallback は親プロセス。
function Get-PwshExe {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    foreach ($p in @(
        'C:\Program Files\PowerShell\7\pwsh.exe',
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:LOCALAPPDATA\Microsoft\PowerShell\7\pwsh.exe"
    )) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return (Get-Process -Id $PID).Path
}
$PwshExe = Get-PwshExe

# wt.exe に渡す profile 名 (タブアイコン・配色を PowerShell 化する)。
# 指定 profile がユーザー WT 設定になければ wt は既定 profile へ fallback するため安全。
# AI_STARTUP_WT_PROFILE で上書き可能。
$WtProfileName = if ($env:AI_STARTUP_WT_PROFILE) { $env:AI_STARTUP_WT_PROFILE } else { 'PowerShell' }

# NewTab モード: 自身を新しい Windows Terminal タブで再起動
if ($NewTab) {
    $psExe  = $PwshExe
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
        $wtArgs = @('-w', '0', 'new-tab', '-p', $WtProfileName, '--title', 'Claude-Live-Log', '--', $psExe) + $psArgs
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
    # attach-session: セッションが存在しなければエラー終了 (new-session -A はゴーストセッションを作るため使わない)
    $sshCmd       = "ssh -t $SshTarget tmux attach-session -t $tmuxSession"
    $psExe        = $script:PwshExe
    $psArgs = @(
        '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command', $sshCmd
    )
    $wtArgs = @('-w', '0', 'new-tab', '-p', $script:WtProfileName, '--title', 'Claude-UI', '--', $psExe) + $psArgs
    Start-Process -FilePath $wtExe.Source -ArgumentList $wtArgs -WindowStyle Hidden
    Write-Host "  Claude UI タブを開きました: tmux attach-session -t $tmuxSession" -ForegroundColor Magenta
}

function Open-SessionInfoTab {
    param([string]$SessionId)
    $wtExe = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wtExe) {
        Write-Host '  [INFO] wt.exe が非検出のため Session Info タブを開けません。' -ForegroundColor Yellow
        return
    }
    $psExe    = $script:PwshExe
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
    $wtArgs = @('-w', '0', 'new-tab', '-p', $script:WtProfileName, '--title', 'Session-Info', '--', $psExe) + $psArgs
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
        # tail -F をバックグラウンド Job で起動し、メインスレッドで次ログ出現を監視する。
        # これにより tail -F が永続ブロックしても次の cron 発火を取りこぼさない (v3.2.41)。
        # stdbuf -oL で tail の line-buffering を強制し、リアルタイム出力を担保する。
        $tailJob = Start-Job -ArgumentList $SshTarget, $latest -ScriptBlock {
            param($target, $path)
            # Job は新規 runspace のため親 console のエンコーディング継承なし。
            # 明示的に UTF-8 化しないと ssh 経由の日本語出力 (例: "UI閲覧用") が文字化ける (v3.2.42)。
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
            $OutputEncoding = [System.Text.Encoding]::UTF8
            ssh $target "stdbuf -oL tail -n 50 -F '$path'"
        }

        try {
            while ($true) {
                # tail の出力を受信してコンソール表示 (非ブロッキング)
                Receive-Job $tailJob -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-Host $_
                }

                # tail Job が落ちた (SSH 切断等) なら抜ける
                if ($tailJob.State -ne 'Running') { break }

                Start-Sleep -Seconds $PollIntervalSeconds

                # より新しいログが出現したら切り替え
                $newer = Get-LatestLog
                if ($newer -and $newer -ne $latest) {
                    # 残出力を flush
                    Receive-Job $tailJob -ErrorAction SilentlyContinue | ForEach-Object {
                        Write-Host $_
                    }
                    Write-Host ''
                    Write-Host "  より新しいセッション検出: $newer" -ForegroundColor Yellow
                    Write-Host '  次のセッションへ切り替えます...' -ForegroundColor Yellow
                    break
                }
            }
        }
        finally {
            Stop-Job $tailJob -ErrorAction SilentlyContinue
            Receive-Job $tailJob -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host $_
            }
            Remove-Job $tailJob -Force -ErrorAction SilentlyContinue
        }

        Write-Host ''
        Write-Host '  現セッションの監視を終了しました。次の cron 発火を待機します...' -ForegroundColor Yellow
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
