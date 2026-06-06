<#
.SYNOPSIS
    時間制限付きで Claude Code を自律起動する Windows ランチャ。
.DESCRIPTION
    Linux の Claude/templates/linux/cron-launcher.sh に対応する Windows ネイティブ版。
    タスクスケジューラ (Register-AutoRunTask.ps1) から非対話で呼ばれ、
    projectsDir(D:\) 直下の <Project> で claude を -DurationMinutes 分だけ起動する。

    責務 (cron-launcher.sh と同一):
      - session.json を %USERPROFILE%\.claudeos\sessions\ に生成・更新
        (SessionTabManager.psm1。Dashboard / Watch-SessionInfo.ps1 と共通スキーマ)
      - state.json から phase/consecutive/goal_type/phase_mode を復元しプロンプトへ注入
        (Phase 1 では読み取り専用。書き込みは後続フェーズで部分更新方式にて実装)
      - maintenance モードでは session 上限を state.json の値で cap
      - 終了コードで status を確定 (completed / timeout / failed)

    タイムアウト制御: PowerShell に timeout コマンドが無いため
    Start-Process -PassThru + [Process].WaitForExit(ms) + Kill(true) で実装
    (cron-launcher.sh の `timeout --foreground Ns` 相当)。

    ClaudeOS — Phase 1 (Windows ローカル一本化)
.PARAMETER Project
    projectsDir 直下のプロジェクトフォルダ名。
.PARAMETER DurationMinutes
    最大作業時間 (分)。既定 300 (5時間)。
.PARAMETER Trigger
    起動トリガ種別 (manual / cron)。タスクスケジューラからは 'cron'。
.PARAMETER DryRun
    claude を起動せず、session.json 生成と finalize のみ実行 (検証用)。
.EXAMPLE
    .\Start-ClaudeAutoTimeout.ps1 -Project demo -DurationMinutes 2 -DryRun
.EXAMPLE
    .\Start-ClaudeAutoTimeout.ps1 -Project MyApp -DurationMinutes 300 -Trigger cron
#>

param(
    [Parameter(Mandatory)][string]$Project,
    [int]$DurationMinutes = 300,
    [ValidateSet('manual', 'cron')][string]$Trigger = 'cron',
    [switch]$DryRun,

    # --- 上書き用 (テスト/特殊環境。通常は未指定で既定解決) ---
    # cron-launcher.sh の PROJECTS_BASE / CLAUDEOS_HOME 上書きと同じ思想。
    [string]$ProjectsDir = '',
    [string]$SessionsDir = '',
    [string]$ConfigPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\SessionTabManager.psm1') -Force -DisableNameChecking

function Write-Info { param($Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Ok   { param($Message) Write-Host "[ OK ]  $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Err  { param($Message) Write-Host "[ERR ]  $Message" -ForegroundColor Red }

# state.json の入れ子プロパティを StrictMode 安全に取得する。
# $Path はドット区切り (例: 'execution.phase')。未存在/未定義なら $Default。
function Get-StateValue {
    param($Root, [Parameter(Mandatory)][string]$Path, $Default = $null)
    $cur = $Root
    foreach ($seg in ($Path -split '\.')) {
        if ($null -eq $cur) { return $Default }
        $prop = $cur.PSObject.Properties[$seg]
        if ($null -eq $prop) { return $Default }
        $cur = $prop.Value
    }
    if ($null -eq $cur) { return $Default }
    return $cur
}

# ============================================================
# 1) config / プロジェクト解決
# ============================================================
# -ProjectsDir 上書きが無ければ config.json から解決する (本番経路)。
if ([string]::IsNullOrWhiteSpace($ProjectsDir)) {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ScriptRoot = Get-StartupRoot -PSScriptRootPath $PSScriptRoot
        $ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot
    }
    $config = Import-StartupConfig -ConfigPath $ConfigPath
    $ProjectsDir = $config.projectsDir
}
if ([string]::IsNullOrWhiteSpace($ProjectsDir)) {
    Write-Err 'projectsDir が解決できません (config.projectsDir 未設定)'
    exit 2
}
$projectDir = Join-Path $ProjectsDir $Project
if (-not (Test-Path $projectDir)) {
    Write-Err "プロジェクトディレクトリが存在しません: $projectDir"
    exit 3
}

# ============================================================
# 2) ~/.claudeos パス (cron-launcher.sh と同じ構成)
# ============================================================
# -SessionsDir 上書きが無ければ %USERPROFILE%\.claudeos\sessions を使う (本番経路)。
# logs は sessions の兄弟ディレクトリ (.claudeos\logs) に揃える。
if ([string]::IsNullOrWhiteSpace($SessionsDir)) {
    $claudeosHome = Join-Path $env:USERPROFILE '.claudeos'
    $SessionsDir  = Join-Path $claudeosHome 'sessions'
    $logsDir      = Join-Path $claudeosHome 'logs'
}
else {
    $logsDir = Join-Path (Split-Path -Parent $SessionsDir) 'logs'
}
foreach ($d in @($SessionsDir, $logsDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logsDir "cron-$stamp.log"

# ログ行をセッションログへ追記 (best-effort)。
function Write-RunLog {
    param($Message)
    try { Add-Content -Path $logFile -Value $Message -Encoding UTF8 } catch { $null = $_ }
}

# ============================================================
# 3) state.json から復元 (cron-launcher.sh L170-266 相当・読み取り専用)
# ============================================================
$stateFile = Join-Path $projectDir 'state.json'
$resumePhase = 'Monitor'; $resumeConsecutive = 0; $resumeSummary = '(none)'
$resumeGoalType = 'mvp-release'; $phaseMode = 'development'
$state = $null
if (Test-Path $stateFile) {
    try { $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Write-Warn "state.json のパースに失敗 (既定値を使用): $($_.Exception.Message)"; $state = $null }
}
if ($null -ne $state) {
    $resumePhase       = [string](Get-StateValue $state 'execution.phase' 'Monitor')
    $resumeConsecutive = [int](Get-StateValue $state 'stable.consecutive_success' 0)
    $summaryRaw        = [string](Get-StateValue $state 'execution.last_session_summary' '')
    $resumeSummary     = if ($summaryRaw) { $summaryRaw.Substring(0, [Math]::Min(300, $summaryRaw.Length)) } else { '(none)' }
    $resumeGoalType    = [string](Get-StateValue $state 'goal_type' 'mvp-release')

    # phase_mode: project.phase_mode を優先、なければ maintenance.phase_mode
    $phaseMode = [string](Get-StateValue $state 'project.phase_mode' '')
    if ([string]::IsNullOrWhiteSpace($phaseMode)) {
        $phaseMode = [string](Get-StateValue $state 'maintenance.phase_mode' 'development')
    }

    # maintenance モード: session 上限を cap (引数が上限超過時のみ短縮)
    if ($phaseMode -eq 'maintenance') {
        $maintMax = [int](Get-StateValue $state 'maintenance.session_max_minutes' 120)
        if ($DurationMinutes -gt $maintMax) {
            Write-RunLog "[auto-timeout] maintenance mode: DurationMinutes capped $DurationMinutes -> $maintMax"
            $DurationMinutes = $maintMax
        }
        if ($resumePhase -eq 'Monitor') { $resumePhase = 'Maintenance' }
    }
}
$env:CLAUDEOS_GOAL_TYPE = $resumeGoalType
Write-Info "state restored: phase=$resumePhase phase_mode=$phaseMode consecutive=$resumeConsecutive"

# ============================================================
# 4) session.json 生成 (SessionTabManager — Dashboard 共通スキーマ)
# ============================================================
$regDate  = [string](Get-StateValue $state 'project.start_date' '')
$deadline = [string](Get-StateValue $state 'project.release_deadline' '')
$session = New-SessionInfo -Project $Project -DurationMinutes $DurationMinutes -Trigger $Trigger `
    -ProcessId $PID -ConfigSessionsDir $sessionsDir `
    -ProjectRegistrationDate $regDate -ProjectReleaseDeadline $deadline
$sessionId = $session.sessionId
Write-RunLog "[auto-timeout] $((Get-Date).ToString('o')) project=$Project duration=${DurationMinutes}m session=$sessionId"

# ============================================================
# 5) START_PROMPT.md + Resume header
# ============================================================
$promptPath = Join-Path $projectDir '.claude\START_PROMPT.md'
$promptArg = ''
if (Test-Path $promptPath) {
    $promptArg = Get-Content $promptPath -Raw -Encoding UTF8
}
$maintNote = if ($phaseMode -eq 'maintenance') {
    " [maintenance mode: max ${DurationMinutes}min, loop=maintenance-loop.md, KPI=SLA/MTTR]"
} else { '' }
$resumeHeader = "[Cron Session Resume] phase=$resumePhase phase_mode=$phaseMode$maintNote goal_type=$resumeGoalType consecutive_success=$resumeConsecutive last_summary=$resumeSummary`n`n"
$promptArg = $resumeHeader + $promptArg

# ============================================================
# 6) DryRun: claude を起動せず finalize のみ (検証用)
# ============================================================
if ($DryRun) {
    Write-Info "[DryRun] session=$sessionId project=$projectDir duration=${DurationMinutes}m"
    Write-Info "[DryRun] prompt length=$($promptArg.Length) chars"
    Set-SessionStatus -SessionId $sessionId -Status 'completed' -ConfigSessionsDir $sessionsDir | Out-Null
    Write-RunLog '[auto-timeout] DryRun finished (no claude launch)'
    Write-Ok "[DryRun] session.json 生成と finalize を確認しました: $sessionId"
    exit 0
}

# ============================================================
# 7) claude を時間制限起動
# ============================================================
Set-Location $projectDir
$env:LANG = 'C.UTF-8'; $env:LC_ALL = 'C.UTF-8'
$env:CLAUDE_SESSION_ID = $sessionId
$env:CLAUDE_PROJECT = $Project
$env:CLAUDE_RESUME_PHASE = $resumePhase
$env:CLAUDE_RESUME_CONSECUTIVE = "$resumeConsecutive"
# Hook が settings.json から参照する絶対パス (サブディレクトリ起動でも解決させる)
$env:CLAUDEOS_HOOKS_DIR = Join-Path $projectDir '.claude\claudeos\scripts\hooks'

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Err 'claude コマンドが見つかりません (npm install -g @anthropic-ai/claude-code)'
    Set-SessionStatus -SessionId $sessionId -Status 'failed' -ConfigSessionsDir $sessionsDir | Out-Null
    exit 4
}
$claudeExe = $claudeCmd.Source

$claudeArgs = @('--dangerously-skip-permissions', $promptArg)
$finalStatus = 'failed'; $exitCode = 1
try {
    # NOTE: 長大プロンプトを引数渡しするため、claude が .cmd shim の場合の
    #       コマンドライン長/クオート挙動は Windows 実機での検証対象 (Phase 1 検証)。
    $proc = Start-Process -FilePath $claudeExe -ArgumentList $claudeArgs `
        -WorkingDirectory $projectDir -PassThru -NoNewWindow
    $timeoutMs = $DurationMinutes * 60 * 1000
    if ($proc.WaitForExit($timeoutMs)) {
        $exitCode = $proc.ExitCode
        $finalStatus = if ($exitCode -eq 0) { 'completed' } else { 'failed' }
    }
    else {
        # タイムアウト = 計画時間到達 (cron-launcher.sh の exit 124 相当)。失敗ではない。
        try { $proc.Kill($true) } catch { Write-Warn "プロセス終了に失敗: $($_.Exception.Message)" }
        $finalStatus = 'timeout'; $exitCode = 124
    }
}
catch {
    Write-Err "claude 起動に失敗: $($_.Exception.Message)"
    $finalStatus = 'failed'
}

# ============================================================
# 8) finalize
# ============================================================
Set-SessionStatus -SessionId $sessionId -Status $finalStatus -ConfigSessionsDir $sessionsDir | Out-Null
Write-RunLog "[auto-timeout] session finished status=$finalStatus exit=$exitCode at $((Get-Date).ToString('o'))"
Write-Info "session finished: status=$finalStatus exit=$exitCode"
exit $exitCode
