<#
.SYNOPSIS
    メニュー 12 本体。Claude Cloud スケジュール (RemoteTrigger) を対話的に登録・編集・削除する。
.DESCRIPTION
    ClaudeOS v8.1 — Linux crontab (New-CronSchedule.ps1) を Cloud Schedule へ移行。
    動作条件:
      - 週6日（月〜土、日曜除く）
      - 1 セッション最大 5 時間（300 分）
    claude CLI の -p フラグで /schedule スキルを呼び出し、
    OAuth 認証と RemoteTrigger API 操作を Claude Code に委譲する。
#>

param(
    [switch]$NonInteractive
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────
# claude CLI 検出
# ─────────────────────────────────────────────────
$script:ClaudeCLI = $null
$candidates = @(
    'claude',
    "$env:APPDATA\npm\claude.cmd",
    "$env:LOCALAPPDATA\Programs\claude\claude.exe",
    (Join-Path $env:USERPROFILE '.local\bin\claude')
)
foreach ($c in $candidates) {
    if (Get-Command $c -ErrorAction SilentlyContinue) {
        $script:ClaudeCLI = $c
        break
    }
    if (Test-Path $c -ErrorAction SilentlyContinue) {
        $script:ClaudeCLI = $c
        break
    }
}
if (-not $script:ClaudeCLI) {
    Write-Host "[ERROR] claude CLI が見つかりません。インストールされているか確認してください。" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────
# 定数
# ─────────────────────────────────────────────────
$DefaultDays            = 'Monday through Saturday'   # 週6日（日曜除く）
$DefaultDurationMinutes = 300                         # 5 時間 = 300 分

# ClaudeOS 標準ループ定義
$LoopPresets = @(
    [pscustomobject]@{ Label = 'ClaudeOS Monitor     (30分ごと)'; Prompt = 'ClaudeOS Monitor';     Interval = '30 minutes' }
    [pscustomobject]@{ Label = 'ClaudeOS Development (2時間ごと)'; Prompt = 'ClaudeOS Development'; Interval = '2 hours' }
    [pscustomobject]@{ Label = 'ClaudeOS Verify      (1時間ごと)'; Prompt = 'ClaudeOS Verify';      Interval = '1 hour' }
    [pscustomobject]@{ Label = 'ClaudeOS Improvement (1時間ごと)'; Prompt = 'ClaudeOS Improvement'; Interval = '1 hour' }
)

# ─────────────────────────────────────────────────
# ヘルパー: claude -p を実行して出力を返す
# ─────────────────────────────────────────────────
function Invoke-ClaudePrint {
    param([Parameter(Mandatory)][string]$Prompt)
    Write-Host "  [Claude] $Prompt" -ForegroundColor DarkGray
    $output = & $script:ClaudeCLI -p $Prompt 2>&1
    return $output
}

# ─────────────────────────────────────────────────
# メニュー表示
# ─────────────────────────────────────────────────
function Show-CloudScheduleMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   Cloud スケジュール 登録・編集・削除" -ForegroundColor Cyan
    Write-Host "   週6日（月〜土） / 最大 $DefaultDurationMinutes 分 / セッション" -ForegroundColor DarkCyan
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [1] 一覧表示" -ForegroundColor Yellow
    Write-Host "    [2] 新規登録（プリセット or カスタム）" -ForegroundColor Yellow
    Write-Host "    [3] 全 4 標準ループを一括登録" -ForegroundColor Green
    Write-Host "    [4] 削除（Trigger ID 指定）" -ForegroundColor Yellow
    Write-Host "    [5] 今すぐ実行（Run, Trigger ID 指定）" -ForegroundColor Green
    Write-Host "    [0] 戻る" -ForegroundColor Gray
    Write-Host ""
}

# ─────────────────────────────────────────────────
# [1] 一覧
# ─────────────────────────────────────────────────
function Invoke-CloudList {
    Write-Host ""
    Write-Host "  Cloud スケジュール一覧を取得中..." -ForegroundColor Cyan
    $result = Invoke-ClaudePrint "/schedule list"
    Write-Host ""
    $result | ForEach-Object { Write-Host "  $_" }
}

# ─────────────────────────────────────────────────
# [2] 新規登録（プリセット or カスタム）
# ─────────────────────────────────────────────────
function Invoke-CloudRegister {
    Write-Host ""
    Write-Host "  -- ClaudeOS 標準ループ --" -ForegroundColor Cyan
    for ($i = 0; $i -lt $LoopPresets.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $LoopPresets[$i].Label) -ForegroundColor White
    }
    Write-Host "    [5] カスタム入力" -ForegroundColor DarkGray
    Write-Host ""

    $sel = Read-Host "  番号を選択"
    $opts = $null

    if ($sel -match '^\d$') {
        $n = [int]$sel - 1
        if ($n -ge 0 -and $n -lt $LoopPresets.Count) {
            $opts = $LoopPresets[$n]
        } elseif ($sel -eq '5') {
            $p = (Read-Host "  プロンプト (例: ClaudeOS Monitor)").Trim()
            $iv = (Read-Host "  間隔 (例: 30 minutes / 1 hour / 2 hours)").Trim()
            if ([string]::IsNullOrWhiteSpace($p) -or [string]::IsNullOrWhiteSpace($iv)) {
                Write-Host "  入力が空です。キャンセルしました。" -ForegroundColor Yellow
                return
            }
            $opts = [pscustomobject]@{ Label = $p; Prompt = $p; Interval = $iv }
        }
    }

    if ($null -eq $opts) {
        Write-Host "  無効な選択です。" -ForegroundColor Red
        return
    }

    $scheduleCmd = "/schedule $($opts.Prompt) every $($opts.Interval) $DefaultDays"

    Write-Host ""
    Write-Host "  == 登録確認 ==" -ForegroundColor Yellow
    Write-Host "    プロンプト : $($opts.Prompt)"
    Write-Host "    間隔       : $($opts.Interval)"
    Write-Host "    曜日       : 月〜土（日曜除く）"
    Write-Host "    最大時間   : $DefaultDurationMinutes 分"
    Write-Host "    コマンド   : $scheduleCmd"
    Write-Host ""
    $confirm = Read-Host "  登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  キャンセルしました。" -ForegroundColor Yellow
        return
    }

    $result = Invoke-ClaudePrint $scheduleCmd
    Write-Host ""
    $result | ForEach-Object { Write-Host "  $_" }
}

# ─────────────────────────────────────────────────
# [3] 4 標準ループを一括登録
# ─────────────────────────────────────────────────
function Invoke-CloudRegisterAll {
    Write-Host ""
    Write-Host "  以下の 4 スケジュールを一括登録します（$DefaultDays）:" -ForegroundColor Cyan
    foreach ($p in $LoopPresets) {
        Write-Host "    - $($p.Prompt) : $($p.Interval)" -ForegroundColor White
    }
    Write-Host ""
    $confirm = Read-Host "  登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  キャンセルしました。" -ForegroundColor Yellow
        return
    }

    foreach ($p in $LoopPresets) {
        $cmd = "/schedule $($p.Prompt) every $($p.Interval) $DefaultDays"
        Write-Host ""
        Write-Host "  >> $($p.Prompt) を登録中..." -ForegroundColor Cyan
        $result = Invoke-ClaudePrint $cmd
        $result | ForEach-Object { Write-Host "  $_" }
        Start-Sleep -Milliseconds 500
    }

    Write-Host ""
    Write-Host "  [OK] 4 スケジュールの一括登録が完了しました。" -ForegroundColor Green
}

# ─────────────────────────────────────────────────
# [4] 削除
# ─────────────────────────────────────────────────
function Invoke-CloudDelete {
    Invoke-CloudList

    Write-Host ""
    $id = (Read-Host "  削除する Trigger ID を入力 (空 Enter でキャンセル)").Trim()
    if ([string]::IsNullOrWhiteSpace($id)) {
        Write-Host "  キャンセルしました。" -ForegroundColor Yellow
        return
    }

    $confirm = Read-Host "  Trigger '$id' を削除しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  キャンセルしました。" -ForegroundColor Yellow
        return
    }

    $result = Invoke-ClaudePrint "/schedule delete $id"
    Write-Host ""
    $result | ForEach-Object { Write-Host "  $_" }
}

# ─────────────────────────────────────────────────
# [5] 今すぐ実行 (Run)
# ─────────────────────────────────────────────────
function Invoke-CloudRun {
    Invoke-CloudList

    Write-Host ""
    $id = (Read-Host "  実行する Trigger ID を入力 (空 Enter でキャンセル)").Trim()
    if ([string]::IsNullOrWhiteSpace($id)) {
        Write-Host "  キャンセルしました。" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  [起動中] Trigger $id ..." -ForegroundColor Cyan
    $result = Invoke-ClaudePrint "/schedule run $id"
    Write-Host ""
    $result | ForEach-Object { Write-Host "  $_" }
}

# ─────────────────────────────────────────────────
# メインループ
# ─────────────────────────────────────────────────
if ($NonInteractive) { exit 0 }

while ($true) {
    Show-CloudScheduleMenu
    $choice = Read-Host "  番号を入力"
    switch ($choice) {
        '1' { Invoke-CloudList;          Read-Host "  Enter で戻ります" | Out-Null }
        '2' { Invoke-CloudRegister;      Read-Host "  Enter で戻ります" | Out-Null }
        '3' { Invoke-CloudRegisterAll;   Read-Host "  Enter で戻ります" | Out-Null }
        '4' { Invoke-CloudDelete;        Read-Host "  Enter で戻ります" | Out-Null }
        '5' { Invoke-CloudRun;           Read-Host "  Enter で戻ります" | Out-Null }
        '0' { exit 0 }
        default {
            Write-Host "  無効な入力です。" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
