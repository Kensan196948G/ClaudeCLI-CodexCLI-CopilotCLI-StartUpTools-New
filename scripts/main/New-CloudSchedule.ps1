<#
.SYNOPSIS
    メニュー 12 本体。Claude Cloud スケジュール (RemoteTrigger) を対話的に登録・削除・実行する。
.DESCRIPTION
    ClaudeOS v8.1 — claude -p (AskUserQuestion ブロック問題) を排除し、
    Invoke-RestMethod で https://claude.ai/api/v1/code/triggers を直接操作する。
    動作条件:
      - 週6日（月〜土、日曜除く）
      - 1 セッション最大 5 時間（300 分）
      - API 最小間隔: 1 時間
#>

param(
    [switch]$NonInteractive
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────
# 定数
# ─────────────────────────────────────────────────
$ApiBase                = 'https://claude.ai/api'
$CredPath               = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$DefaultDurationMinutes = 300
$DefaultDays            = '1-6'        # Mon-Sat (cron DOW)
$DefaultModel           = 'claude-sonnet-4-6'
$RepoUrl                = 'https://github.com/Kensan196948G/ClaudeCode-StartUpTools-New'
$AllowedTools           = @('Bash','Read','Write','Edit','Glob','Grep','Agent')

$script:EnvironmentId   = $null   # 既存 trigger から動的取得してキャッシュ

# ─────────────────────────────────────────────────
# プリセット定義 (4 標準ループ)
# 注意: API 最小間隔 = 1h のため Monitor も 1h
# ─────────────────────────────────────────────────
$LoopPresets = @(
    [pscustomobject]@{
        Label = 'Monitor     (1時間ごと ※API最小間隔)'
        Name  = 'ClaudeOS Monitor'
        Cron  = "0 * * * $DefaultDays"
        Content = @"
ClaudeOS v8 Monitor Phase — Autonomous Execution

Repository: $RepoUrl
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Monitor phase:
1. Git & CI State: git log --oneline -10, check GitHub Actions CI status on recent commits/PRs
2. GitHub Issues: list by priority (P1>P2>P3), flag P1 issues needing immediate attention
3. Open PRs: CI status, review state, blocked PRs
4. Goal & KPI: read state.json and CLAUDE.md, assess current KPI achievement
5. STABLE judgment: test+build+CI+lint+security → STABLE or UNSTABLE
6. Recommendations: concise status table, recommend next phase (Development/Verify/Repair)
   Create a P1 GitHub Issue if CI is failing and one does not already exist.

Constraints: Do NOT implement code. Do NOT push to main. Observation and reporting only.
"@
    }
    [pscustomobject]@{
        Label = 'Development (2時間ごと)'
        Name  = 'ClaudeOS Development'
        Cron  = "0 */2 * * $DefaultDays"
        Content = @"
ClaudeOS v8 Development Phase — Autonomous Build Loop

Repository: $RepoUrl
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Development (Build) phase:
1. Check open GitHub Issues (P1>P2>P3) and CI status; read state.json for goal/KPI
2. Select highest-priority actionable Issue (security blocker > CI failure > test failure)
3. Implement fix or feature on new branch (feat/vX.Y.Z-<topic> or fix/vX.Y.Z-<topic>)
4. Run tests/lint locally (npm test, npm run lint if available)
5. Commit with conventional commit message referencing the Issue number
6. Push and create PR: changes summary, test results, impact scope, remaining issues
7. Update GitHub Projects board status

Agent chain: [Architect] design → [Developer] implement → [Reviewer] self-review diff

Constraints: Never push to main directly. Never merge without CI passing.
One Issue per session. Stop if approaching 4.5 hours or token budget high.
"@
    }
    [pscustomobject]@{
        Label = 'Verify      (1時間ごと)'
        Name  = 'ClaudeOS Verify'
        Cron  = "0 * * * $DefaultDays"
        Content = @"
ClaudeOS v8 Verify Phase — Autonomous Execution

Repository: $RepoUrl
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Verify phase:
1. Run tests (npm test / pytest / equivalent), lint, build
2. Check GitHub Actions CI status on recent PRs and main branch
3. STABLE/UNSTABLE judgment: requires test+build+CI+lint success + zero security blockers
4. Auto-repair simple failures (max 3 attempts per root cause category)
5. Create GitHub Issues for each blocker found
6. Report: STABLE/UNSTABLE verdict, each check result, Issues created, next recommended action

Constraints: Never merge without CI passing. Never push to main directly.
"@
    }
    [pscustomobject]@{
        Label = 'Improvement (1時間ごと)'
        Name  = 'ClaudeOS Improvement'
        Cron  = "0 * * * $DefaultDays"
        Content = @"
ClaudeOS v8 Improvement Phase — Autonomous Execution

Repository: $RepoUrl
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Improvement phase (only after STABLE is confirmed):
1. Naming improvements, refactoring, technical debt reduction
2. Update README.md if architecture/features/setup changed (use tables, icons, Mermaid diagrams)
3. Update state.json with learning patterns and current session summary
4. Create P3 GitHub Issues for improvement candidates found
5. Commit improvements on feature branch, push, create PR

Constraints: Never break existing tests. Never push to main directly.
Report: improvements made, docs updated, Issues created.
"@
    }
)

# ─────────────────────────────────────────────────
# 認証・HTTP ヘルパー
# ─────────────────────────────────────────────────
function Get-ClaudeAuthToken {
    if (-not (Test-Path $CredPath)) {
        throw "認証ファイルが見つかりません: $CredPath`n'claude auth login' で再認証してください。"
    }
    $creds = Get-Content $CredPath -Raw | ConvertFrom-Json
    $token = $creds.claudeAiOauth.accessToken
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "アクセストークンが空です。'claude auth login' で再認証してください。"
    }
    return $token
}

function Invoke-TriggersAPI {
    param(
        [ValidateSet('GET','POST','DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        [object]$Body = $null
    )
    $token = Get-ClaudeAuthToken
    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }
    $params = @{ Uri = "$ApiBase$Path"; Method = $Method; Headers = $headers }
    if ($null -ne $Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $detail = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw "[HTTP $status] $detail"
    }
}

function Get-EnvironmentId {
    if ($script:EnvironmentId) { return $script:EnvironmentId }
    try {
        $list = Invoke-TriggersAPI -Method 'GET' -Path '/v1/code/triggers'
        foreach ($t in $list.data) {
            $eid = $t.job_config?.ccr?.environment_id
            if (-not [string]::IsNullOrWhiteSpace($eid)) {
                $script:EnvironmentId = $eid
                return $eid
            }
        }
    } catch { }
    return $null
}

# ─────────────────────────────────────────────────
# [1] 一覧表示
# ─────────────────────────────────────────────────
function Invoke-CloudList {
    Write-Host ""
    Write-Host "  Cloud スケジュール一覧を取得中..." -ForegroundColor Cyan
    try {
        $result = Invoke-TriggersAPI -Method 'GET' -Path '/v1/code/triggers'
        if ($result.data.Count -eq 0) {
            Write-Host "  登録済みの Cloud スケジュールはありません。" -ForegroundColor Yellow
            return
        }
        Write-Host ""
        Write-Host ("  {0,-36} {1,-28} {2,-18} {3,-6} {4}" -f 'ID','名前','Cron','有効','次回実行(JST)') -ForegroundColor Cyan
        Write-Host ("  " + ("-" * 100)) -ForegroundColor DarkGray
        foreach ($t in $result.data) {
            $enabled = if ($t.enabled) { '✓' } else { '✗' }
            $next = if ($t.next_run_at) {
                try { (Get-Date $t.next_run_at).ToLocalTime().ToString('MM-dd HH:mm') } catch { '-' }
            } else { '-' }
            $color = if ($t.enabled) { 'White' } else { 'DarkGray' }
            Write-Host ("  {0,-36} {1,-28} {2,-18} {3,-6} {4}" -f $t.id, $t.name, $t.cron_expression, $enabled, $next) -ForegroundColor $color
        }
        # environment_id をキャッシュ
        foreach ($t in $result.data) {
            $eid = $t.job_config?.ccr?.environment_id
            if (-not [string]::IsNullOrWhiteSpace($eid)) { $script:EnvironmentId = $eid; break }
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────
# trigger 作成ボディ生成
# ─────────────────────────────────────────────────
function New-TriggerBody {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$CronExpression,
        [Parameter(Mandatory)][string]$PromptContent
    )
    $envId = Get-EnvironmentId
    $uuid  = [guid]::NewGuid().ToString()

    $ccr = [ordered]@{
        events = @(
            @{
                data = @{
                    message            = @{ content = $PromptContent; role = 'user' }
                    parent_tool_use_id = $null
                    session_id         = ''
                    type               = 'user'
                    uuid               = $uuid
                }
            }
        )
        session_context = @{
            allowed_tools = $AllowedTools
            model         = $DefaultModel
            sources       = @( @{ git_repository = @{ url = $RepoUrl } } )
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($envId)) {
        $ccr['environment_id'] = $envId
    }

    return [ordered]@{
        name            = $Name
        cron_expression = $CronExpression
        enabled         = $true
        job_config      = @{ ccr = $ccr }
    }
}

# ─────────────────────────────────────────────────
# [2] 新規登録（プリセット or カスタム）
# ─────────────────────────────────────────────────
function Invoke-CloudRegister {
    Write-Host ""
    Write-Host "  -- ClaudeOS 標準ループ (Mon-Sat / 最小間隔 1h) --" -ForegroundColor Cyan
    for ($i = 0; $i -lt $LoopPresets.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $LoopPresets[$i].Label) -ForegroundColor White
    }
    Write-Host "    [5] カスタム入力 (Cron 直接指定)" -ForegroundColor DarkGray
    Write-Host ""

    $sel = (Read-Host "  番号を選択").Trim()
    $preset = $null

    if ($sel -match '^\d$') {
        $n = [int]$sel - 1
        if ($n -ge 0 -and $n -lt $LoopPresets.Count) {
            $preset = $LoopPresets[$n]
        } elseif ($sel -eq '5') {
            $pName    = (Read-Host "  名前 (例: ClaudeOS Monitor)").Trim()
            $pCron    = (Read-Host "  Cron 式 (例: 0 * * * 1-6)").Trim()
            $pContent = (Read-Host "  プロンプト内容").Trim()
            if ([string]::IsNullOrWhiteSpace($pName) -or [string]::IsNullOrWhiteSpace($pCron)) {
                Write-Host "  入力が空です。キャンセルしました。" -ForegroundColor Yellow; return
            }
            $preset = [pscustomobject]@{ Name = $pName; Cron = $pCron; Content = $pContent }
        }
    }

    if ($null -eq $preset) { Write-Host "  無効な選択です。" -ForegroundColor Red; return }

    Write-Host ""
    Write-Host "  == 登録確認 ==" -ForegroundColor Yellow
    Write-Host "    名前 : $($preset.Name)"
    Write-Host "    Cron : $($preset.Cron)"
    Write-Host "    曜日 : 月〜土（日曜除く）"
    Write-Host ""
    $confirm = Read-Host "  登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    try {
        $body   = New-TriggerBody -Name $preset.Name -CronExpression $preset.Cron -PromptContent $preset.Content
        $result = Invoke-TriggersAPI -Method 'POST' -Path '/v1/code/triggers' -Body $body
        Write-Host "  [OK] 登録完了: ID=$($result.id)  Cron=$($result.cron_expression)" -ForegroundColor Green
        if ($result.next_run_at) {
            $next = try { (Get-Date $result.next_run_at).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } catch { $result.next_run_at }
            Write-Host "       次回実行(JST): $next" -ForegroundColor DarkGreen
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────
# [3] 全 4 標準ループを一括登録
# ─────────────────────────────────────────────────
function Invoke-CloudRegisterAll {
    Write-Host ""
    Write-Host "  以下の 4 スケジュールを一括登録します（Mon-Sat / 最大 $DefaultDurationMinutes 分）:" -ForegroundColor Cyan
    foreach ($p in $LoopPresets) {
        Write-Host ("    - {0,-30} Cron: {1}" -f $p.Name, $p.Cron) -ForegroundColor White
    }
    Write-Host ""
    $confirm = Read-Host "  登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    $ok = 0; $ng = 0
    foreach ($p in $LoopPresets) {
        Write-Host ""
        Write-Host "  >> $($p.Name) を登録中 ($($p.Cron))..." -ForegroundColor Cyan
        try {
            $body   = New-TriggerBody -Name $p.Name -CronExpression $p.Cron -PromptContent $p.Content
            $result = Invoke-TriggersAPI -Method 'POST' -Path '/v1/code/triggers' -Body $body
            Write-Host "  [OK] ID=$($result.id)  Cron=$($result.cron_expression)" -ForegroundColor Green
            $ok++
        } catch {
            Write-Host "  [ERROR] $($p.Name): $($_.Exception.Message)" -ForegroundColor Red
            $ng++
        }
        Start-Sleep -Milliseconds 300
    }
    Write-Host ""
    Write-Host "  [完了] 登録 $ok 件 / エラー $ng 件" -ForegroundColor $(if ($ng -eq 0) { 'Green' } else { 'Yellow' })
}

# ─────────────────────────────────────────────────
# [4] 削除（DELETE → 失敗時は enabled=false）
# ─────────────────────────────────────────────────
function Invoke-CloudDelete {
    Invoke-CloudList
    Write-Host ""
    $id = (Read-Host "  削除する Trigger ID を入力 (空 Enter でキャンセル)").Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    $confirm = Read-Host "  '$id' を削除しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    # DELETE を試みる
    try {
        Invoke-TriggersAPI -Method 'DELETE' -Path "/v1/code/triggers/$id" | Out-Null
        Write-Host "  [OK] 削除しました: $id" -ForegroundColor Green
        return
    } catch { }

    # DELETE 非対応の場合は無効化
    try {
        Invoke-TriggersAPI -Method 'POST' -Path "/v1/code/triggers/$id" -Body @{ enabled = $false } | Out-Null
        Write-Host "  [OK] 無効化しました: $id  (enabled=false)" -ForegroundColor Yellow
        Write-Host "       ※ API が DELETE を未サポートのため無効化で代替しました。" -ForegroundColor DarkGray
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────
# [5] 今すぐ実行
# ─────────────────────────────────────────────────
function Invoke-CloudRun {
    Invoke-CloudList
    Write-Host ""
    $id = (Read-Host "  実行する Trigger ID を入力 (空 Enter でキャンセル)").Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    Write-Host "  [起動中] $id ..." -ForegroundColor Cyan
    try {
        $result = Invoke-TriggersAPI -Method 'POST' -Path "/v1/code/triggers/$id/run"
        Write-Host "  [OK] 実行キューに追加しました。" -ForegroundColor Green
        if ($result) { Write-Host "       $($result | ConvertTo-Json -Depth 2 -Compress)" -ForegroundColor DarkGray }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────
# メニュー
# ─────────────────────────────────────────────────
function Show-CloudScheduleMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   Cloud スケジュール 登録・削除・実行" -ForegroundColor Cyan
    Write-Host "   週6日（月〜土） / 最大 $DefaultDurationMinutes 分 / 最小間隔 1h" -ForegroundColor DarkCyan
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [1] 一覧表示" -ForegroundColor Yellow
    Write-Host "    [2] 新規登録（プリセット or カスタム）" -ForegroundColor Yellow
    Write-Host "    [3] 全 4 標準ループを一括登録" -ForegroundColor Green
    Write-Host "    [4] 削除 / 無効化（Trigger ID 指定）" -ForegroundColor Yellow
    Write-Host "    [5] 今すぐ実行（Trigger ID 指定）" -ForegroundColor Green
    Write-Host "    [0] 戻る" -ForegroundColor Gray
    Write-Host ""
}

if ($NonInteractive) { exit 0 }

while ($true) {
    Show-CloudScheduleMenu
    $choice = Read-Host "  番号を入力"
    switch ($choice) {
        '1' { Invoke-CloudList;        Read-Host "  Enter で戻ります" | Out-Null }
        '2' { Invoke-CloudRegister;    Read-Host "  Enter で戻ります" | Out-Null }
        '3' { Invoke-CloudRegisterAll; Read-Host "  Enter で戻ります" | Out-Null }
        '4' { Invoke-CloudDelete;      Read-Host "  Enter で戻ります" | Out-Null }
        '5' { Invoke-CloudRun;         Read-Host "  Enter で戻ります" | Out-Null }
        '0' { exit 0 }
        default {
            Write-Host "  無効な入力です。" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
