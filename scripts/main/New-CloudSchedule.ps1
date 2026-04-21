<#
.SYNOPSIS
    メニュー 14 本体 / プロジェクト起動後の Cloud Schedule 自動確認。
.DESCRIPTION
    ClaudeOS v8.1 — claude -p を中継して RemoteTrigger ツールを呼び出す。
    プロジェクトごとに Cloud Schedule を管理できる。
    -RepoUrl 未指定時は起動時にプロジェクト選択 UI を表示。
    動作条件:
      - 週6日（月〜土、日曜除く）
      - 1 セッション最大 5 時間（300 分）
      - API 最小間隔: 1 時間
#>

param(
    [switch]$NonInteractive,

    # 空文字 = 起動時にプロジェクト選択 UI を表示
    # 値あり = Start-ClaudeCode.ps1 から直接渡された URL（UI スキップ）
    [string]$RepoUrl = '',

    # プロジェクト起動後の自動確認モード（Start-ClaudeCode.ps1 から呼ばれる）
    [switch]$QuickSetup
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────
# 定数
# ─────────────────────────────────────────────────
$DefaultDurationMinutes = 300
$DefaultDays            = '1-6'          # Mon-Sat (cron DOW)
$DefaultModel           = 'claude-sonnet-4-6'
$AllowedTools           = @('Bash','Read','Write','Edit','Glob','Grep','Agent')

# ─────────────────────────────────────────────────
# claude CLI 検出
# ─────────────────────────────────────────────────
$script:ClaudeCLI = $null
foreach ($c in @('claude', "$env:APPDATA\npm\claude.cmd",
                  "$env:LOCALAPPDATA\Programs\claude\claude.exe",
                  (Join-Path $env:USERPROFILE '.local\bin\claude'))) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $script:ClaudeCLI = $c; break }
    if (Test-Path $c -ErrorAction SilentlyContinue)   { $script:ClaudeCLI = $c; break }
}
if (-not $script:ClaudeCLI) {
    Write-Host "[ERROR] claude CLI が見つかりません。'npm install -g @anthropic-ai/claude-code' でインストールしてください。" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────
# claude -p 中継（Cloudflare 対策: Invoke-RestMethod を使わない）
# ※ Select-Project / Invoke-CronAllSync より前に定義が必要
# ─────────────────────────────────────────────────
function Invoke-CloudCLI {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$ShowOutput
    )
    $output = & $script:ClaudeCLI -p $Prompt 2>&1
    if ($ShowOutput) {
        Write-Host ""
        $output | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" }
    }
    return $output
}

# ─────────────────────────────────────────────────
# Cron 全プロジェクトを Cloud Schedule に一括同期
# ※ Select-Project より前に定義が必要（[S] オプションから呼ばれる）
# ─────────────────────────────────────────────────
function Invoke-CronAllSync {
    Write-Host ""
    Write-Host "  Cron 登録済みプロジェクトを Cloud Schedule に一括同期します。" -ForegroundColor Cyan
    Write-Host "  SSH 経由で Cron エントリを取得中..." -ForegroundColor DarkGray

    $cronProjects = @()
    try {
        $ScriptRootCS = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $cronMgr      = Join-Path $ScriptRootCS 'scripts\lib\CronManager.psm1'
        $cfgPath      = Join-Path $ScriptRootCS 'config\config.json'
        if ((Test-Path $cronMgr) -and (Test-Path $cfgPath)) {
            Import-Module $cronMgr -Force -DisableNameChecking -ErrorAction SilentlyContinue
            $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $linuxHost = $cfg.linuxHost
            if ($linuxHost -and $linuxHost -ne '<your-linux-host>') {
                $entries = Get-ClaudeOSCronEntry -LinuxHost $linuxHost -ErrorAction SilentlyContinue
                $cronProjects = @($entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Project) } | Select-Object -ExpandProperty Project -Unique)
            }
        }
    } catch { }

    if ($cronProjects.Count -eq 0) {
        Write-Host "  [INFO] Cron 登録済みプロジェクトが見つかりませんでした。" -ForegroundColor Yellow
        Write-Host "         (SSH 接続エラーまたは Cron エントリなし)" -ForegroundColor DarkGray
        return
    }

    $owner = ''
    try {
        $raw = (& git remote get-url origin 2>$null) -join ''
        if ($raw -match 'github\.com[:/]([^/]+)/') { $owner = $matches[1] }
    } catch { }

    Write-Host ""
    Write-Host "  -- Cron 登録済みプロジェクト ($($cronProjects.Count) 件) --" -ForegroundColor Cyan
    $syncList = @()
    foreach ($proj in $cronProjects) {
        $url = if ($owner) { "https://github.com/$owner/$proj" } else { '' }
        Write-Host ("    {0,-40} {1}" -f $proj, $(if ($url) { $url } else { '(URL 不明)' })) -ForegroundColor White
        $syncList += [pscustomobject]@{ Project = $proj; Url = $url }
    }

    if (-not $owner) {
        Write-Host ""
        Write-Host "  GitHub owner が取得できませんでした。" -ForegroundColor Yellow
        $owner = (Read-Host "  GitHub ユーザー名 / org 名を入力 (例: Kensan196948G)").Trim()
        foreach ($item in $syncList) {
            if ([string]::IsNullOrWhiteSpace($item.Url)) {
                $item.Url = "https://github.com/$owner/$($item.Project)"
            }
        }
    }

    Write-Host ""
    $confirm = Read-Host "  上記 $($syncList.Count) 件を Cloud Schedule に登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    $psExe       = (Get-Process -Id $PID).Path
    $cloudScript = $PSCommandPath
    $ok = 0; $ng = 0

    foreach ($item in $syncList) {
        Write-Host ""
        Write-Host "  >> $($item.Project) ($($item.Url)) を登録中..." -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($item.Url)) {
            Write-Host "  [SKIP] URL が空のためスキップ。" -ForegroundColor Yellow
            $ng++
            continue
        }
        try {
            & $psExe -NoProfile -ExecutionPolicy Bypass -File $cloudScript -RepoUrl $item.Url -QuickSetup
            $ok++
        } catch {
            Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
            $ng++
        }
    }

    Write-Host ""
    Write-Host "  [完了] 登録 $ok 件 / スキップ/エラー $ng 件" -ForegroundColor $(if ($ng -eq 0) { 'Green' } else { 'Yellow' })
}

# ─────────────────────────────────────────────────
# プロジェクト選択 UI
# [S] Cron全同期 を含む（同期後にリストを再描画）
# ─────────────────────────────────────────────────
function Select-Project {
    while ($true) {
        $projects = [System.Collections.Generic.List[pscustomobject]]::new()

        # ── 1. 登録済み Cloud Schedule から git URL を動的取得 ──
        Write-Host ""
        Write-Host "  登録済みプロジェクトを取得中（Cloud Schedule + Cron）..." -ForegroundColor DarkGray

        $cloudUrls = @{}
        try {
            $out = & $script:ClaudeCLI -p @"
Use RemoteTrigger with action='list'.
For each trigger, extract the git repository URL from job_config.ccr.session_context.sources[0].git_repository.url.
Output each unique URL on its own line prefixed with REPO_URL: (no spaces after colon).
Example: REPO_URL:https://github.com/user/repo
"@ 2>&1
            foreach ($line in $out) {
                if ($line -match '^REPO_URL:(.+)$') {
                    $url = $matches[1].Trim().TrimEnd('/') -replace '\.git$', ''
                    if ($url -match 'github\.com') {
                        $cloudUrls[$url] = $true
                        if (($projects | Where-Object Url -eq $url).Count -eq 0) {
                            $name = $url.Split('/')[-1]
                            $projects.Add([pscustomobject]@{ Label = $name; Url = $url; HasCloud = $true; HasCron = $false })
                        }
                    }
                }
            }
        } catch { }

        # ── 2. Cron 登録済みプロジェクト（CronManager 経由、SSH）を取得してマージ ──
        try {
            $ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
            $cronMgr    = Join-Path $ScriptRoot 'scripts\lib\CronManager.psm1'
            $cfgPath    = Join-Path $ScriptRoot 'config\config.json'
            if (-not (Test-Path $cfgPath)) { $cfgPath = Join-Path $ScriptRoot 'Claude\templates\claude\config.json.template' }
            if ((Test-Path $cronMgr) -and (Test-Path $cfgPath)) {
                Import-Module $cronMgr -Force -DisableNameChecking -ErrorAction SilentlyContinue
                $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
                $linuxHost = $cfg.linuxHost
                if ($linuxHost -and $linuxHost -ne '<your-linux-host>') {
                    $entries = Get-ClaudeOSCronEntry -LinuxHost $linuxHost -ErrorAction SilentlyContinue
                    $cronOwner = ''
                    try {
                        $cronRemote = (& git remote get-url origin 2>$null) -join ''
                        if ($cronRemote -match 'github\.com[:/]([^/]+)/') { $cronOwner = $matches[1] }
                    } catch { }

                    foreach ($e in @($entries)) {
                        if ([string]::IsNullOrWhiteSpace($e.Project)) { continue }
                        $guessUrl = if ($cronOwner) { "https://github.com/$cronOwner/$($e.Project)" } else { '' }

                        $existing = $projects | Where-Object { $_.Label -eq $e.Project -or ($guessUrl -and $_.Url -eq $guessUrl) } | Select-Object -First 1
                        if ($existing) {
                            $existing.HasCron = $true
                        } else {
                            $url = if ($guessUrl) { $guessUrl } else { '' }
                            $projects.Add([pscustomobject]@{ Label = $e.Project; Url = $url; HasCloud = $false; HasCron = $true })
                        }
                    }
                }
            }
        } catch { }

        # ── 3. 現在のディレクトリの git remote（未登録なら追加） ──
        try {
            $rawUrl = (& git remote get-url origin 2>$null) -join ''
            if ($rawUrl -match 'github\.com') {
                $rawUrl = $rawUrl.Trim() -replace '\.git$', '' -replace '^git@github\.com:', 'https://github.com/'
                if (($projects | Where-Object Url -eq $rawUrl).Count -eq 0) {
                    $name = $rawUrl.Split('/')[-1] + ' (現在のディレクトリ)'
                    $projects.Insert(0, [pscustomobject]@{ Label = $name; Url = $rawUrl; HasCloud = $false; HasCron = $false })
                }
            }
        } catch { }

        # ── 4. フォールバック ──
        if ($projects.Count -eq 0) {
            $projects.Add([pscustomobject]@{ Label = 'ClaudeCode-StartUpTools-New';   Url = 'https://github.com/Kensan196948G/ClaudeCode-StartUpTools-New'; HasCloud = $false; HasCron = $false })
            $projects.Add([pscustomobject]@{ Label = 'Enterprise-AI-HelpDesk-System'; Url = 'https://github.com/Kensan196948G/Enterprise-AI-HelpDesk-System'; HasCloud = $false; HasCron = $false })
        }

        # ── 表示 ──
        Clear-Host
        Write-Host ""
        Write-Host "  =============================================" -ForegroundColor Cyan
        Write-Host "   Cloud Schedule — プロジェクト選択" -ForegroundColor Cyan
        Write-Host "   S1 (SSH/Linux) プロジェクト専用" -ForegroundColor DarkCyan
        Write-Host "   ※ L1 (Local/Windows) は登録不要（手動起動のみ）" -ForegroundColor DarkGray
        Write-Host "   ※ 5時間強制終了が必要な場合はメニュー 15 の Cron も併用" -ForegroundColor DarkGray
        Write-Host "  =============================================" -ForegroundColor Cyan
        Write-Host "   凡例: ☁=Cloud Schedule登録済  ⏱=Cron(5h)登録済" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $projects.Count; $i++) {
            $badge = ''
            if ($projects[$i].HasCloud) { $badge += ' ☁' }
            if ($projects[$i].HasCron)  { $badge += ' ⏱' }
            $color = if ($projects[$i].HasCloud -or $projects[$i].HasCron) { 'White' } else { 'DarkGray' }
            Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $projects[$i].Label, $badge) -ForegroundColor $color
            if ($projects[$i].Url) {
                Write-Host ("        {0}" -f $projects[$i].Url) -ForegroundColor DarkGray
            }
        }
        Write-Host "    [M] 手動入力（GitHub URL）" -ForegroundColor DarkGray
        Write-Host "    [S] Cron 全プロジェクトを Cloud Schedule に同期" -ForegroundColor Cyan
        Write-Host "    [0] 戻る" -ForegroundColor Gray
        Write-Host ""

        $sel = (Read-Host "  番号を選択").Trim()

        if ($sel -eq '0') { return '' }

        if ($sel -match '^[Ss]$') {
            Invoke-CronAllSync
            Read-Host "  Enter でプロジェクト選択に戻ります" | Out-Null
            continue   # リストを再描画（☁ バッジ更新）
        }

        if ($sel -match '^\d+$') {
            $n = [int]$sel - 1
            if ($n -ge 0 -and $n -lt $projects.Count -and $projects[$n].Url) {
                return $projects[$n].Url
            }
        } elseif ($sel -match '^[Mm]$') {
            $url = (Read-Host "  GitHub URL を入力 (例: https://github.com/user/repo)").Trim()
            $url = $url.TrimEnd('/') -replace '\.git$', ''
            if (-not [string]::IsNullOrWhiteSpace($url)) { return $url }
        }

        Write-Host "  無効な選択です。デフォルトを使用します。" -ForegroundColor Yellow
        return $projects[0].Url
    }
}

# ─────────────────────────────────────────────────
# プリセット生成（プロジェクト URL に依存するため関数化）
# ─────────────────────────────────────────────────
function New-LoopPresets {
    param([Parameter(Mandatory)][string]$Url)
    return @(
        [pscustomobject]@{
            Label = 'Monitor     (1時間ごと ※API最小間隔)'
            Name  = 'ClaudeOS Monitor'
            Cron  = "0 * * * $DefaultDays"
            Content = @"
ClaudeOS v8 Monitor Phase — Autonomous Execution

Repository: $Url
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Monitor phase:
1. Git & CI State: git log --oneline -10, check GitHub Actions CI on recent commits/PRs
2. GitHub Issues: list by priority (P1>P2>P3), flag P1 issues
3. Open PRs: CI status, review state, blocked PRs
4. Goal & KPI: read state.json and CLAUDE.md, assess current KPI
5. STABLE judgment: test+build+CI+lint+security → STABLE or UNSTABLE
6. Recommendations: status table, recommend next phase (Development/Verify/Repair)
   Create a P1 GitHub Issue if CI is failing and one does not already exist.

Constraints: Do NOT implement code. Do NOT push to main. Observation only.
"@
        }
        [pscustomobject]@{
            Label = 'Development (2時間ごと)'
            Name  = 'ClaudeOS Development'
            Cron  = "0 */2 * * $DefaultDays"
            Content = @"
ClaudeOS v8 Development Phase — Autonomous Build Loop

Repository: $Url
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Development phase:
1. Check open GitHub Issues (P1>P2>P3) and CI status; read state.json for goal/KPI
2. Select highest-priority actionable Issue (security > CI failure > test failure)
3. Implement fix or feature on new branch (feat/vX.Y.Z-<topic>)
4. Run tests/lint locally
5. Commit with conventional commit referencing the Issue
6. Push and create PR: changes, test results, impact scope, remaining issues
7. Update GitHub Projects board

Agent chain: [Architect] → [Developer] → [Reviewer]
Constraints: Never push to main. Never merge without CI. One Issue per session.
"@
        }
        [pscustomobject]@{
            Label = 'Verify      (1時間ごと)'
            Name  = 'ClaudeOS Verify'
            Cron  = "0 * * * $DefaultDays"
            Content = @"
ClaudeOS v8 Verify Phase — Autonomous Execution

Repository: $Url
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Verify phase:
1. Run tests (npm test / pytest / equivalent), lint, build
2. Check GitHub Actions CI on recent PRs and main branch
3. STABLE/UNSTABLE: requires test+build+CI+lint success + zero security blockers
4. Auto-repair simple failures (max 3 attempts per root cause)
5. Create GitHub Issues for each blocker found
6. Report: STABLE/UNSTABLE verdict, each check result, next action

Constraints: Never merge without CI passing. Never push to main directly.
"@
        }
        [pscustomobject]@{
            Label = 'Improvement (1時間ごと)'
            Name  = 'ClaudeOS Improvement'
            Cron  = "0 * * * $DefaultDays"
            Content = @"
ClaudeOS v8 Improvement Phase — Autonomous Execution

Repository: $Url
Max session: 5 hours (300 minutes). Weekdays: Monday-Saturday.

Execute the Improvement phase (only after STABLE is confirmed):
1. Naming improvements, refactoring, technical debt reduction
2. Update README.md if architecture/features/setup changed
3. Update state.json with learning patterns
4. Create P3 GitHub Issues for improvement candidates
5. Commit on feature branch, push, create PR

Constraints: Never break tests. Never push to main directly.
"@
        }
    )
}

# ─────────────────────────────────────────────────
# RepoUrl 確定（QuickSetup / NonInteractive 時はデフォルト）
# ─────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    if ($NonInteractive -or $QuickSetup) {
        $RepoUrl = 'https://github.com/Kensan196948G/ClaudeCode-StartUpTools-New'
    } else {
        $RepoUrl = Select-Project
        if ([string]::IsNullOrWhiteSpace($RepoUrl)) { exit 0 }   # [0] 戻る
    }
}

# プリセットをプロジェクト URL で生成
$script:LoopPresets = New-LoopPresets -Url $RepoUrl
$script:RepoShortName = $RepoUrl.Split('/')[-1]

# ─────────────────────────────────────────────────
# Build-CreatePrompt
# ─────────────────────────────────────────────────
function Build-CreatePrompt {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Cron,
        [Parameter(Mandatory)][string]$PromptContent
    )
    $uuid = [guid]::NewGuid().ToString()
    return @"
Use the RemoteTrigger tool to create a new cloud schedule trigger with these exact parameters:
- name: "$Name"
- cron_expression: "$Cron"
- enabled: true
- job_config.ccr.events[0].data.message.content: "$($PromptContent.Replace('"','\"').Replace("`n",'\n'))"
- job_config.ccr.events[0].data.message.role: "user"
- job_config.ccr.events[0].data.uuid: "$uuid"
- job_config.ccr.session_context.model: "$DefaultModel"
- job_config.ccr.session_context.sources: [{"git_repository": {"url": "$RepoUrl"}}]
- job_config.ccr.session_context.allowed_tools: $($AllowedTools | ConvertTo-Json -Compress)
Use your current environment_id automatically.
After creation output ONE line: CREATED_ID=<trigger_id>
"@
}

# ─────────────────────────────────────────────────
# [1] 一覧表示
# ─────────────────────────────────────────────────
function Invoke-CloudList {
    Write-Host ""
    Write-Host "  Cloud スケジュール一覧を取得中..." -ForegroundColor Cyan
    Write-Host "  (claude API 経由 / 数秒かかる場合があります)" -ForegroundColor DarkGray

    $prompt = @"
Use RemoteTrigger with action='list' to get all cloud schedule triggers.
Display results as a table with columns:
  ID | Name | Cron | 有効 | 次回実行(JST)
Be concise. Show ALL triggers in the list, grouped by project if possible.
"@
    Invoke-CloudCLI $prompt -ShowOutput
}

# ─────────────────────────────────────────────────
# [2] 新規登録（プリセット or カスタム）
# ─────────────────────────────────────────────────
function Invoke-CloudRegister {
    Write-Host ""
    Write-Host "  プロジェクト: $script:RepoShortName" -ForegroundColor DarkCyan
    Write-Host "  -- ClaudeOS 標準ループ (Mon-Sat / 最小間隔 1h) --" -ForegroundColor Cyan
    for ($i = 0; $i -lt $script:LoopPresets.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $script:LoopPresets[$i].Label) -ForegroundColor White
    }
    Write-Host "    [5] カスタム入力 (Cron 直接指定)" -ForegroundColor DarkGray
    Write-Host ""

    $sel = (Read-Host "  番号を選択").Trim()
    $preset = $null

    if ($sel -match '^\d$') {
        $n = [int]$sel - 1
        if ($n -ge 0 -and $n -lt $script:LoopPresets.Count) {
            $preset = $script:LoopPresets[$n]
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
    Write-Host "    名前     : $($preset.Name)"
    Write-Host "    Cron     : $($preset.Cron)"
    Write-Host "    プロジェクト: $script:RepoShortName"
    Write-Host ""
    $confirm = Read-Host "  登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    Write-Host ""
    Write-Host "  登録中（claude API 経由）..." -ForegroundColor Cyan
    $createPrompt = Build-CreatePrompt -Name $preset.Name -Cron $preset.Cron -PromptContent $preset.Content
    $output = Invoke-CloudCLI $createPrompt

    $idLine = $output | Where-Object { $_ -match '^CREATED_ID=' } | Select-Object -First 1
    if ($idLine) {
        Write-Host "  [OK] 登録完了: $(($idLine -replace '^CREATED_ID=','').Trim())" -ForegroundColor Green
    } else {
        $output | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" }
    }
}

# ─────────────────────────────────────────────────
# [3] 全 4 標準ループを一括登録
# ─────────────────────────────────────────────────
function Invoke-CloudRegisterAll {
    Write-Host ""
    Write-Host "  プロジェクト: $script:RepoShortName" -ForegroundColor DarkCyan
    Write-Host "  以下の 4 スケジュールを一括登録します（Mon-Sat / 最大 $DefaultDurationMinutes 分）:" -ForegroundColor Cyan
    foreach ($p in $script:LoopPresets) {
        Write-Host ("    - {0,-30} Cron: {1}" -f $p.Name, $p.Cron) -ForegroundColor White
    }
    Write-Host ""
    $confirm = Read-Host "  登録しますか? [y/N]"
    if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    $ok = 0; $ng = 0
    foreach ($p in $script:LoopPresets) {
        Write-Host ""
        Write-Host "  >> $($p.Name) を登録中..." -ForegroundColor Cyan
        try {
            $createPrompt = Build-CreatePrompt -Name $p.Name -Cron $p.Cron -PromptContent $p.Content
            $output = Invoke-CloudCLI $createPrompt

            $idLine = $output | Where-Object { $_ -match '^CREATED_ID=' } | Select-Object -First 1
            if ($idLine) {
                Write-Host "  [OK] ID=$(($idLine -replace '^CREATED_ID=','').Trim())" -ForegroundColor Green
            } else {
                $output | Where-Object { $_.Trim() } | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            }
            $ok++
        } catch {
            Write-Host "  [ERROR] $($p.Name): $($_.Exception.Message)" -ForegroundColor Red
            $ng++
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host ""
    Write-Host "  [完了] 登録 $ok 件 / エラー $ng 件" -ForegroundColor $(if ($ng -eq 0) { 'Green' } else { 'Yellow' })
}

# ─────────────────────────────────────────────────
# [4] 管理（無効化 / 有効化 / 完全削除）
# ─────────────────────────────────────────────────
function Invoke-CloudManage {
    Invoke-CloudList
    Write-Host ""
    Write-Host "  -- 操作を選択 --" -ForegroundColor Cyan
    Write-Host "    [OFF]  無効化       (ID 指定 → enabled=false)" -ForegroundColor Yellow
    Write-Host "    [ON]   有効化       (ID 指定 → enabled=true)" -ForegroundColor Green
    Write-Host "    [DEL]  完全削除     (ID 指定 → API delete)" -ForegroundColor Red
    Write-Host "    [OFFA] 全無効化     (全トリガー → enabled=false)" -ForegroundColor Yellow
    Write-Host "    [ONA]  全有効化     (全トリガー → enabled=true)" -ForegroundColor Green
    Write-Host "    [DELA] 全完全削除   (全トリガー → API delete)" -ForegroundColor Red
    Write-Host "    [Enter] キャンセル" -ForegroundColor Gray
    Write-Host ""
    $op = (Read-Host "  操作を入力").Trim().ToUpper()

    if ([string]::IsNullOrWhiteSpace($op)) { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    switch ($op) {
        'OFFA' {
            $confirm = Read-Host "  全トリガーを無効化します。よろしいですか? [y/N]"
            if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }
            Write-Host "  全無効化中..." -ForegroundColor Yellow
            $out = Invoke-CloudCLI @"
Use RemoteTrigger action='list', then for each trigger call action='update' with body={"enabled":false}.
Output ONE line: DONE_ALL=<count>
"@
            $line = $out | Where-Object { $_ -match '^DONE_ALL=' } | Select-Object -First 1
            if ($line) { Write-Host "  [OK] $(($line -replace '^DONE_ALL=','').Trim()) 件を無効化しました。" -ForegroundColor Green }
            else { $out | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" } }
            return
        }
        'ONA' {
            $confirm = Read-Host "  全トリガーを有効化します。よろしいですか? [y/N]"
            if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }
            Write-Host "  全有効化中..." -ForegroundColor Green
            $out = Invoke-CloudCLI @"
Use RemoteTrigger action='list', then for each trigger call action='update' with body={"enabled":true}.
Output ONE line: DONE_ALL=<count>
"@
            $line = $out | Where-Object { $_ -match '^DONE_ALL=' } | Select-Object -First 1
            if ($line) { Write-Host "  [OK] $(($line -replace '^DONE_ALL=','').Trim()) 件を有効化しました。" -ForegroundColor Green }
            else { $out | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" } }
            return
        }
        'DELA' {
            $confirm = Read-Host "  全トリガーを完全削除します。元に戻せません。よろしいですか? [y/N]"
            if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }
            Write-Host "  全完全削除中..." -ForegroundColor Red
            $out = Invoke-CloudCLI @"
Use RemoteTrigger action='list' to get all trigger IDs.
For each trigger ID, attempt to permanently delete it using RemoteTrigger.
If permanent deletion is not supported by the API, disable it with action='update' body={"enabled":false} instead.
Output ONE line: DONE_ALL=<count>
"@
            $line = $out | Where-Object { $_ -match '^DONE_ALL=' } | Select-Object -First 1
            if ($line) { Write-Host "  [OK] $(($line -replace '^DONE_ALL=','').Trim()) 件を処理しました。" -ForegroundColor Green }
            else { $out | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" } }
            return
        }
    }

    if ($op -notin @('OFF','ON','DEL')) {
        Write-Host "  無効な操作です。" -ForegroundColor Red; return
    }

    $id = (Read-Host "  Trigger ID を入力 (空 Enter でキャンセル)").Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    switch ($op) {
        'OFF' {
            $confirm = Read-Host "  '$id' を無効化しますか? [y/N]"
            if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }
            Write-Host "  無効化中..." -ForegroundColor Yellow
            $out = Invoke-CloudCLI "Use RemoteTrigger action='update', trigger_id='$id', body={'enabled':false}. Output ONE line: DONE"
            if ($out -match 'DONE') { Write-Host "  [OK] 無効化しました: $id" -ForegroundColor Green }
            else { $out | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" } }
        }
        'ON' {
            $confirm = Read-Host "  '$id' を有効化しますか? [y/N]"
            if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }
            Write-Host "  有効化中..." -ForegroundColor Green
            $out = Invoke-CloudCLI "Use RemoteTrigger action='update', trigger_id='$id', body={'enabled':true}. Output ONE line: DONE"
            if ($out -match 'DONE') { Write-Host "  [OK] 有効化しました: $id" -ForegroundColor Green }
            else { $out | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" } }
        }
        'DEL' {
            $confirm = Read-Host "  '$id' を完全削除しますか? 元に戻せません。 [y/N]"
            if ($confirm -notmatch '^[yY]') { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }
            Write-Host "  完全削除中..." -ForegroundColor Red
            $out = Invoke-CloudCLI @"
Permanently delete the RemoteTrigger with trigger_id='$id'.
If the API supports permanent deletion use it; otherwise disable with action='update' body={'enabled':false}.
Output ONE line: DONE
"@
            if ($out -match 'DONE') { Write-Host "  [OK] 処理しました: $id" -ForegroundColor Green }
            else { $out | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" } }
        }
    }
}

# ─────────────────────────────────────────────────
# [5] 今すぐ実行（Trigger ID 指定）
# ─────────────────────────────────────────────────
function Invoke-CloudRun {
    Invoke-CloudList
    Write-Host ""
    $id = (Read-Host "  実行する Trigger ID を入力 (空 Enter でキャンセル)").Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { Write-Host "  キャンセルしました。" -ForegroundColor Yellow; return }

    Write-Host ""
    Write-Host "  [起動中] $id ..." -ForegroundColor Cyan
    $output = Invoke-CloudCLI @"
Use RemoteTrigger with action='run', trigger_id='$id'.
After the call output ONE line: DONE or ERROR
"@

    if ($output -match 'DONE') {
        Write-Host "  [OK] 実行キューに追加しました。" -ForegroundColor Green
    } else {
        $output | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" }
    }
}

# ─────────────────────────────────────────────────
# メニュー（プロジェクト名をヘッダーに表示）
# ─────────────────────────────────────────────────
function Show-CloudScheduleMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   Cloud スケジュール 登録・削除・実行" -ForegroundColor Cyan
    Write-Host "   S1 (SSH) 専用 / 週6日（月〜土） / 最小間隔 1h" -ForegroundColor DarkCyan
    Write-Host "   ※ 5時間強制終了 → メニュー 15 の Cron を併用" -ForegroundColor DarkGray
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   プロジェクト: $script:RepoShortName" -ForegroundColor White
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [1] 一覧表示" -ForegroundColor Yellow
    Write-Host "    [2] 新規登録（プリセット or カスタム）" -ForegroundColor Yellow
    Write-Host "    [3] 全 4 標準ループを一括登録" -ForegroundColor Green
    Write-Host "    [4] 管理（無効化 / 有効化 / 完全削除）" -ForegroundColor Yellow
    Write-Host "    [5] 今すぐ実行（Trigger ID 指定）" -ForegroundColor Green
    Write-Host "    [P] プロジェクトを切り替え（Cron全同期はここから）" -ForegroundColor Magenta
    Write-Host "    [0] 戻る" -ForegroundColor Gray
    Write-Host ""
}

if ($NonInteractive) { exit 0 }

# ─────────────────────────────────────────────────
# QuickSetup モード（プロジェクト起動直後の自動確認）
# ─────────────────────────────────────────────────
if ($QuickSetup) {
    Write-Host "  プロジェクト : $RepoUrl" -ForegroundColor DarkGray
    Write-Host ""

    $loopSummary = ($script:LoopPresets | ForEach-Object { "  - $($_.Name) (cron: $($_.Cron))" }) -join "`n"
    $checkPrompt = @"
Check my cloud schedules using RemoteTrigger(action='list').
For the repository '$RepoUrl', identify which of these 4 schedules are already registered (match by name):
$loopSummary

Output a table: Name | Status (登録済み/未登録)
Then output: MISSING_COUNT=<number>
"@

    Write-Host "  Cloud Schedule 登録状況を確認中..." -ForegroundColor Cyan
    $checkOutput = Invoke-CloudCLI $checkPrompt -ShowOutput

    $missingLine = $checkOutput | Where-Object { $_ -match '^MISSING_COUNT=' } | Select-Object -First 1
    $missingCount = if ($missingLine -match '=(\d+)$') { [int]$matches[1] } else { -1 }

    Write-Host ""
    if ($missingCount -eq 0) {
        Write-Host "  [OK] 全 4 スケジュールが登録済みです。" -ForegroundColor Green
    } else {
        $label = if ($missingCount -gt 0) { "$missingCount 件" } else { '不明件数の' }
        Write-Host "  未登録スケジュールが $label あります。" -ForegroundColor Yellow
        $confirm = Read-Host "  今すぐ一括登録しますか? [y/N]"
        if ($confirm -match '^[yY]') {
            Invoke-CloudRegisterAll
        } else {
            Write-Host "  スキップ。メニュー 14 でいつでも登録できます。" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    exit 0
}

# ─────────────────────────────────────────────────
# 通常メニューモード
# ─────────────────────────────────────────────────
while ($true) {
    Show-CloudScheduleMenu
    $choice = Read-Host "  番号を入力"
    switch ($choice.ToUpper()) {
        '1' { Invoke-CloudList;        Read-Host "  Enter で戻ります" | Out-Null }
        '2' { Invoke-CloudRegister;    Read-Host "  Enter で戻ります" | Out-Null }
        '3' { Invoke-CloudRegisterAll; Read-Host "  Enter で戻ります" | Out-Null }
        '4' { Invoke-CloudManage;      Read-Host "  Enter で戻ります" | Out-Null }
        '5' { Invoke-CloudRun;         Read-Host "  Enter で戻ります" | Out-Null }
        'P' {
            $newUrl = Select-Project
            if (-not [string]::IsNullOrWhiteSpace($newUrl) -and $newUrl -ne $RepoUrl) {
                $RepoUrl = $newUrl
                $script:LoopPresets = New-LoopPresets -Url $RepoUrl
                $script:RepoShortName = $RepoUrl.Split('/')[-1]
                Write-Host "  プロジェクトを切り替えました: $script:RepoShortName" -ForegroundColor Green
            }
        }
        '0' { exit 0 }
        default {
            Write-Host "  無効な入力です。" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
