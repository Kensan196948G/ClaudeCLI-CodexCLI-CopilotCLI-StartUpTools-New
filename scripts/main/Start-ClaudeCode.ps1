<#
.SYNOPSIS
    Claude Code startup script
.DESCRIPTION
    ClaudeOS Agent Teams lane: Architect / DevAPI / QA.
#>

param(
    [string]$Project = '',
    [switch]$Local,
    [switch]$NonInteractive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\McpHealthCheck.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\AgentTeams.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\SessionTabManager.psm1') -Force -DisableNameChecking

$ScriptRoot = Get-StartupRoot -PSScriptRootPath $PSScriptRoot
$ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot

function Write-Info { param($Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Ok { param($Message) Write-Host "[ OK ]  $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Error2 { param($Message) Write-Host "[ERR]   $Message" -ForegroundColor Red }

function ConvertTo-BashSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)

    $quote = [string][char]39
    $replacement = $quote + '"' + $quote + '"' + $quote
    return $quote + $Value.Replace($quote, $replacement) + $quote
}

function New-RemoteTemplateDeployScript {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function returns in-memory object; no persistent system state is modified')]
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Label,
        [switch]$EnsureParentDirectory,
        # InitializeOnly: ファイルが存在しない場合のみ配置（既存ファイルを上書きしない）。
        # ローカルモードの Initialize-ProjectTemplate と同等の動作。
        # settings.json など Claude が実行中に変更するファイルに使用する。
        [switch]$InitializeOnly
    )

    if (-not (Test-Path $TemplatePath)) {
        return ""
    }

    $content = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
    # bash double-quote does not expand ~ — replace with $HOME for correct expansion
    $normalizedTargetPath = $TargetPath.Replace('\', '/')
    if ($normalizedTargetPath -match '^~/') {
        $normalizedTargetPath = '$HOME/' + $normalizedTargetPath.Substring(2)
    }
    $mkdir = ""
    if ($EnsureParentDirectory) {
        $mkdir = "mkdir -p `"`$(dirname `"$normalizedTargetPath`")`"`n"
    }

    if ($InitializeOnly) {
        return @"
$mkdir
TMP_FILE=`$(mktemp)
printf '%s' '$base64' | base64 -d > "`$TMP_FILE"
if [ ! -f "$normalizedTargetPath" ]; then
  mv "`$TMP_FILE" "$normalizedTargetPath"
  echo "[OK] $Label を配置しました: $normalizedTargetPath"
else
  rm -f "`$TMP_FILE"
  echo "[INFO] $Label は最新です: $normalizedTargetPath"
fi
"@
    }

    return @"
$mkdir
TMP_FILE=`$(mktemp)
printf '%s' '$base64' | base64 -d > "`$TMP_FILE"
if [ ! -f "$normalizedTargetPath" ] || ! cmp -s "`$TMP_FILE" "$normalizedTargetPath"; then
  mv "`$TMP_FILE" "$normalizedTargetPath"
  echo "[OK] $Label を配置/更新しました: $normalizedTargetPath"
else
  rm -f "`$TMP_FILE"
  echo "[INFO] $Label は最新です: $normalizedTargetPath"
fi
"@
}

function Get-StartPromptSection {
    param([Parameter(Mandatory)][string]$PromptPath)

    $content = Get-Content -Path $PromptPath -Raw -Encoding UTF8
    $content = $content.TrimStart([char]0xFEFF)

    $loopMatch = [regex]::Match($content, '(?ms)^##\s*LOOP_COMMANDS[^\r\n]*\r?\n(.*?)(?=^##\s*PROMPT_BODY\b)')
    $bodyMatch = [regex]::Match($content, '(?ms)^##\s*PROMPT_BODY[^\r\n]*\r?\n(.*)$')

    # LOOP_COMMANDS は任意（Linux cron 運用では不要）。
    # PROMPT_BODY が見つからない場合はファイル全体を PromptBody として扱う。
    $loopCommands = if ($loopMatch.Success) { $loopMatch.Groups[1].Value.Trim() } else { '' }
    $promptBody   = if ($bodyMatch.Success) { $bodyMatch.Groups[1].Value.Trim() } else { $content.Trim() }

    # LoopCommands がある場合のみ末尾に追加（スラッシュコマンド解析の誤発火防止）。
    $fullText = if ($loopCommands) {
        ("$promptBody`r`n`r`n$loopCommands").Trim()
    } else {
        $promptBody
    }

    return [pscustomobject]@{
        LoopCommands = $loopCommands
        PromptBody   = $promptBody
        FullText     = $fullText
    }
}

function Invoke-ClaudeSshViaStdin {
    param(
        [Parameter(Mandatory)][string]$LinuxHost,
        [Parameter(Mandatory)][string]$ScriptText
    )

    if ($env:AI_STARTUP_SSH_CAPTURE_DIR) {
        $captureDir = $env:AI_STARTUP_SSH_CAPTURE_DIR
        if (-not (Test-Path $captureDir)) {
            New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
        }
        Set-Content -Path (Join-Path $captureDir "deploy-script.sh") -Value $ScriptText -Encoding UTF8
        Write-Host "[INFO] SSH_CAPTURE deploy $LinuxHost" -ForegroundColor DarkGray
        return 0
    }

    # Bash on the remote side must receive LF-only content.
    $normalizedScript = (($ScriptText -replace "`r`n", "`n") -replace "`r", "`n")

    $sshCommand = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { 'ssh' }
    $connectTimeout = if ($env:AI_STARTUP_SSH_CONNECT_TIMEOUT) { $env:AI_STARTUP_SSH_CONNECT_TIMEOUT } else { '10' }

    # Windows OpenSSH は ControlMaster のUnixソケットをサポートしないため無効化する。
    # Linuxでのみ ControlMaster=auto を使用して多重接続時の TCP 競合を回避する。
    $sshControlArgs = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        "-o ControlMaster=no"
    } else {
        $controlPath = "/tmp/ssh_cm_%r@%h_%p"
        "-o ControlMaster=auto -o ControlPath=$controlPath -o ControlPersist=15"
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $sshCommand
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.Arguments = ('-T -o ConnectTimeout={0} -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=60 -o ServerAliveCountMax=3 {1} {2} "bash -s"' -f $connectTimeout, $sshControlArgs, $LinuxHost)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    Write-Info "SSH 接続中: $LinuxHost ..."
    [void]$process.Start()
    $process.StandardInput.NewLine = "`n"
    $process.StandardInput.Write($normalizedScript)
    if (-not $normalizedScript.EndsWith("`n")) {
        $process.StandardInput.WriteLine()
    }
    $process.StandardInput.Close()
    $process.WaitForExit()
    return $process.ExitCode
}

$launchContext = New-LauncherExecutionContext
$Config = $null
$instanceMutex = $null

try {
    $Config = Import-LauncherConfig -ConfigPath $ConfigPath
    $toolConfig = $Config.tools.claude
    if (-not $toolConfig.enabled) {
        throw 'Claude Code is disabled in config.json.'
    }

    Write-Info 'Checking Claude Code...'
    if (-not (Assert-LauncherToolAvailable -Command 'claude' -InstallCommand $toolConfig.installCommand -ToolLabel 'Claude Code' -NonInteractive:$NonInteractive)) {
        exit 1
    }
    Write-Ok 'Claude Code is available.'

    $apiKeyName = $toolConfig.apiKeyEnvVar
    $apiKey = Get-LauncherApiKeyValue -ApiKeyName $apiKeyName -EnvMap $toolConfig.env

    $Local = Resolve-LauncherMode -Config $Config -Local:$Local -NonInteractive:$NonInteractive -ConfigPath $ConfigPath

    if ($Local -and [string]::IsNullOrEmpty($apiKey)) {
        Show-LauncherApiKeyWarning -ApiKeyName $apiKeyName -LoginHint 'Use /login after Claude Code starts if you rely on account auth.' -ApiHint "Set environment variable $apiKeyName for API auth."
    }

    $linuxHost = $Config.linuxHost
    $linuxBase = $Config.linuxBase
    $Project = Resolve-LauncherProject -Config $Config -Project $Project -Local:$Local -NonInteractive:$NonInteractive -LinuxHost $linuxHost
    $modeName = Get-LauncherModeName -Local:$Local
    $launchContext.Project = $Project
    $launchContext.Mode = $modeName
    $launchContext.Tool = 'claude'
    $modeLabel = Get-LauncherModeLabel -Project $Project -Local:$Local -ProjectsDir $Config.projectsDir -LinuxHost $linuxHost -LinuxBase $linuxBase

    if (-not (Confirm-LauncherStart -ToolName 'Claude Code' -Project $Project -ModeLabel $modeLabel -NonInteractive:$NonInteractive)) {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    # --- WT Profile 環境変数: Watch-ClaudeLog / Session Info タブに伝搬 ---
    $wtProfileForSession = if (
        ($Config.PSObject.Properties.Name -contains 'windowsTerminal') -and $Config.windowsTerminal -and
        ($Config.windowsTerminal.PSObject.Properties.Name -contains 'profileName') -and $Config.windowsTerminal.profileName
    ) { [string]$Config.windowsTerminal.profileName } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($wtProfileForSession)) {
        $env:AI_STARTUP_WT_PROFILE = $wtProfileForSession
    }

    # --- Session Info Tab (v3.1.0) ---
    # session.json を生成して、Windows Terminal に情報タブを 1 枚開く。
    $sessionDurationMin = 300

    # state.json からプロジェクト タイムライン情報を読み取る
    $projRegDate   = ''
    $projDeadline  = ''
    $projDurMonths = 6
    $localProjDir  = Join-Path $Config.projectsDir $Project
    $stateJsonPath = Join-Path $localProjDir 'state.json'
    if (Test-Path $stateJsonPath) {
        try {
            $st = Get-Content $stateJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($st.project) {
                # registration_date 優先 → なければ旧フォーマットの start_date にフォールバック
                if ($st.project.PSObject.Properties.Name -contains 'registration_date' -and $st.project.registration_date) {
                    $projRegDate = [string]$st.project.registration_date
                } elseif ($st.project.PSObject.Properties.Name -contains 'start_date' -and $st.project.start_date) {
                    $projRegDate = [string]$st.project.start_date
                }
                if ($st.project.PSObject.Properties.Name -contains 'release_deadline' -and $st.project.release_deadline) {
                    $projDeadline = [string]$st.project.release_deadline
                }
                if ($st.project.PSObject.Properties.Name -contains 'duration_months' -and $st.project.duration_months) {
                    $projDurMonths = [int]$st.project.duration_months
                }
            }
        } catch { $null = $_ }
    }

    if ($Config.PSObject.Properties.Name -contains 'sessionTabs' -and $Config.sessionTabs.enabled) {
        try {
            $sessionsDir = if ($Config.sessionTabs.PSObject.Properties.Name -contains 'localSessionsDir') {
                [Environment]::ExpandEnvironmentVariables($Config.sessionTabs.localSessionsDir)
            } else { '' }

            $session = New-SessionInfo -Project $Project -DurationMinutes $sessionDurationMin `
                -Trigger 'manual' -Pid $PID -ConfigSessionsDir $sessionsDir `
                -ProjectRegistrationDate $projRegDate `
                -ProjectReleaseDeadline  $projDeadline `
                -ProjectDurationMonths   $projDurMonths
            $env:CLAUDE_SESSION_ID = $session.sessionId
            $launchContext | Add-Member -NotePropertyName 'SessionId' -NotePropertyValue $session.sessionId -Force

            $tabLauncher = Join-Path $ScriptRoot 'scripts\main\Show-SessionInfoTab.ps1'
            if (Test-Path $tabLauncher) {
                $tabArgs = @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tabLauncher,
                    '-SessionId', $session.sessionId
                )
                if (-not [string]::IsNullOrWhiteSpace($sessionsDir)) {
                    $tabArgs += @('-SessionsDir', $sessionsDir)
                }
                $wtProfileName = if (
                    ($Config.PSObject.Properties.Name -contains 'windowsTerminal') -and $Config.windowsTerminal -and
                    ($Config.windowsTerminal.PSObject.Properties.Name -contains 'profileName') -and $Config.windowsTerminal.profileName
                ) { [string]$Config.windowsTerminal.profileName } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($wtProfileName)) {
                    $tabArgs += @('-WtProfile', $wtProfileName)
                }
                Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $tabArgs -WindowStyle Hidden
                Write-Info "Session Info タブを起動: $($session.sessionId)"
            }
        }
        catch {
            Write-Warn "Session Info タブの起動をスキップ: $($_.Exception.Message)"
        }
    }

    # --- Instance Lock: 同一プロジェクトの多重起動を防止 ---
    # PTY bridge が stdin (fd 0) を同時にrawモードで取り合うと片方が永久にフリーズするため、
    # Named Mutex で同一プロジェクトのインスタンスを1つに制限する。
    $safeProjectName = $Project -replace '[^A-Za-z0-9_-]', '_'
    $mutexName = "Global\ClaudeCode_$safeProjectName"
    $instanceMutex = [System.Threading.Mutex]::new($false, $mutexName)
    $acquiredLock = $false
    try {
        $acquiredLock = $instanceMutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        # 前回プロセスが異常終了してMutexが放棄された場合は取得済みとして扱う
        $acquiredLock = $true
    }
    if (-not $acquiredLock) {
        Write-Warn "プロジェクト '$Project' の Claude Code は既に起動中です。"
        Write-Warn "同一プロジェクトへの多重起動は PTY bridge の stdin 競合によるフリーズを引き起こします。"
        Write-Warn "別プロジェクトを起動する場合は -Project パラメータでプロジェクト名を指定してください。"
        $launchContext.Result = 'cancelled'
        exit 1
    }

    if ($Local) {
        $localProjectDir = Join-Path $Config.projectsDir $Project
        Set-Location $localProjectDir
        Set-LauncherEnvironment -EnvMap $toolConfig.env

        # --- MCP Health Check (pre-launch) ---
        Write-Host ''
        Write-Host '=== Pre-Launch Diagnostics ===' -ForegroundColor Magenta
        Write-Host ''
        try {
            $mcpReport = Get-McpHealthReport -ProjectRoot $localProjectDir
            if ($mcpReport.configured) {
                $mcpAvailable = @($mcpReport.servers | Where-Object { $_.status -eq 'available' }).Count
                $mcpTotal = @($mcpReport.servers).Count
                if ($mcpAvailable -eq $mcpTotal) {
                    Write-Ok "MCP: $mcpAvailable/$mcpTotal servers available"
                }
                else {
                    Write-Warn "MCP: $mcpAvailable/$mcpTotal servers available"
                    foreach ($s in @($mcpReport.servers | Where-Object { $_.status -ne 'available' })) {
                        Write-Warn "  - $($s.name): $($s.status)"
                    }
                }
            }
            else {
                Write-Info 'MCP: 設定なし（.mcp.json 未検出）'
            }
        }
        catch {
            Write-Warn "MCP check skipped: $($_.Exception.Message)"
        }

        # --- Agent Teams Check (pre-launch) ---
        try {
            $agentReport = Get-AgentTeamReport -ProjectRoot $localProjectDir
            if ($agentReport.agentsDirExists) {
                Write-Ok "Agent Teams: $($agentReport.agentCount) agents loaded"
            }
            else {
                Write-Info 'Agent Teams: agents ディレクトリ未検出'
            }
        }
        catch {
            Write-Warn "Agent Teams check skipped: $($_.Exception.Message)"
        }
        Write-Host ''

        Sync-LauncherClaudeGlobalConfig -StartupRoot $ScriptRoot -ProjectDir $localProjectDir

        # Build-StartPrompt.ps1 で START_PROMPT.md を instructions/ から自動再生成
        $buildPromptScript = Join-Path $ScriptRoot 'Claude\templates\claude\Build-StartPrompt.ps1'
        if (Test-Path $buildPromptScript) {
            Write-Info "START_PROMPT.md を instructions/ から再ビルド中..."
            $psExeForBuild = (Get-Process -Id $PID).Path
            & $psExeForBuild -NoProfile -ExecutionPolicy Bypass -File $buildPromptScript
            if ($LASTEXITCODE -eq 0) { Write-Ok "START_PROMPT.md 再ビルド完了" }
            else { Write-Warn "START_PROMPT.md 再ビルド失敗（既存ファイルを使用）" }
        }

        $localPromptPath = Join-Path $ScriptRoot 'Claude\templates\claude\START_PROMPT.md'
        $localPromptArgs = @()
        if (Test-Path $localPromptPath) {
            $localPromptSections = Get-StartPromptSection -PromptPath $localPromptPath
            $localPromptArgs = @($localPromptSections.FullText)
            Write-Info "START_PROMPT を自動送信します ($localPromptPath)"
        }

        $claudeLocalArgs = @($toolConfig.args) + $localPromptArgs

        if ($DryRun) {
            foreach ($line in (New-LauncherDryRunMessage -Command 'claude' -Arguments $claudeLocalArgs -WorkingDirectory $localProjectDir)) {
                Write-Info $line
            }
            $launchContext.Result = 'success'
            exit 0
        }

        # 起動通知音（ノンブロッキング）
        Invoke-LauncherNotificationSound -Tool 'claude' -Config $Config -Wait $false

        & claude @claudeLocalArgs
        $launchContext.Result = if ($LASTEXITCODE -eq 0) { 'success' } else { 'failure' }
        exit $LASTEXITCODE
    }
}
catch {
    if ($_.Exception.Message -eq 'USER_CANCELLED') {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    $launchContext.Result = 'failure'
    Write-Error2 $_.Exception.Message
    exit 1
}
finally {
    if ($Config) {
        Complete-LauncherExecutionContext -Context $launchContext -Config $Config
    }

    # --- Session Info Tab: status を最終状態へ更新 (v3.1.0) ---
    if ($launchContext -and ($launchContext.PSObject.Properties.Name -contains 'SessionId') -and $launchContext.SessionId) {
        try {
            $sessionsDir = if ($Config -and $Config.PSObject.Properties.Name -contains 'sessionTabs' -and `
                $Config.sessionTabs.PSObject.Properties.Name -contains 'localSessionsDir') {
                [Environment]::ExpandEnvironmentVariables($Config.sessionTabs.localSessionsDir)
            } else { '' }

            $finalStatus = switch ($launchContext.Result) {
                'success' { 'completed' }
                'cancelled' { 'cancelled' }
                'failure' { 'failed' }
                default { 'exited' }
            }
            Set-SessionStatus -SessionId $launchContext.SessionId -Status $finalStatus -ConfigSessionsDir $sessionsDir | Out-Null
        }
        catch {
            Write-Debug "Session status update failed: $_"
        }
    }

    # 終了通知音（同期再生：セッション終了を確実に通知）
    Invoke-LauncherNotificationSound -Tool 'claude' -Config $Config -Wait $true
    # インスタンスロック解放
    if ($null -ne $instanceMutex) {
        try { $instanceMutex.ReleaseMutex() } catch { Write-Debug "ReleaseMutex failed (mutex may already be released): $_" }
        $instanceMutex.Dispose()
    }
}
