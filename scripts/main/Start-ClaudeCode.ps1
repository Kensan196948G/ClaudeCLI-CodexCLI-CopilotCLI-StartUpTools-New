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
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return ""
    }

    $content = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
    $normalizedTargetPath = $TargetPath.Replace('\', '/')
    $mkdir = ""
    if ($EnsureParentDirectory) {
        $mkdir = "mkdir -p `"`$(dirname `"$normalizedTargetPath`")`"`n"
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

function Get-StartPromptSections {
    param([Parameter(Mandatory)][string]$PromptPath)

    $content = Get-Content -Path $PromptPath -Raw -Encoding UTF8
    $content = $content.TrimStart([char]0xFEFF)

    $loopMatch = [regex]::Match($content, '(?ms)^##\s*LOOP_COMMANDS[^\r\n]*\r?\n(.*?)(?=^##\s*PROMPT_BODY\b)')
    $bodyMatch = [regex]::Match($content, '(?ms)^##\s*PROMPT_BODY[^\r\n]*\r?\n(.*)$')

    if (-not $loopMatch.Success -or -not $bodyMatch.Success) {
        throw "START_PROMPT.md の形式が不正です。'## LOOP_COMMANDS' と '## PROMPT_BODY' が必要です。"
    }

    # PromptBody を先頭に配置する。
    # LoopCommands（/loop ...）が先頭だと Claude Code のスラッシュコマンド解析が
    # 発火して PromptBody 全体が /loop スキルの引数として消費されるため、
    # 通常テキスト（PromptBody）を先に送り、/loop 行は末尾で Claude に読ませる。
    return [pscustomobject]@{
        LoopCommands = ($loopMatch.Groups[1].Value.Trim())
        PromptBody   = ($bodyMatch.Groups[1].Value.Trim())
        FullText     = (($bodyMatch.Groups[1].Value.Trim()) + "`r`n`r`n" + ($loopMatch.Groups[1].Value.Trim())).Trim()
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

        $localPromptPath = Join-Path $ScriptRoot 'Claude\templates\claude\START_PROMPT.md'
        $localPromptArgs = @()
        if (Test-Path $localPromptPath) {
            $localPromptSections = Get-StartPromptSections -PromptPath $localPromptPath
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

    $linuxProject = "$linuxBase/$Project"
    $claudeArgs = if ($toolConfig.args) { $toolConfig.args -join ' ' } else { '' }
    $claudeCommand = "export LANG=C.UTF-8; export LC_ALL=C.UTF-8; cd $(ConvertTo-BashSingleQuoted -Value $linuxProject) && claude $claudeArgs".Trim()

    $templateClaude = Join-Path $ScriptRoot 'Claude\templates\claude\CLAUDE.md'
    $templateSettings = Join-Path $ScriptRoot 'Claude\templates\claude\settings.json'
    $templatePrompt = Join-Path $ScriptRoot 'Claude\templates\claude\START_PROMPT.md'
    $bridgeSource = Join-Path $ScriptRoot 'scripts\helpers\claude_pty_bridge.py'

    $promptSections = Get-StartPromptSections -PromptPath $templatePrompt

    # --- Pre-Launch Diagnostics (SSH mode) ---
    Write-Host ''
    Write-Host '=== Pre-Launch Diagnostics (SSH) ===' -ForegroundColor Magenta
    try {
        $agentReport = Get-AgentTeamReport -ProjectRoot $ScriptRoot
        if ($agentReport.agentsDirExists) {
            Write-Ok "Agent Teams: $($agentReport.agentCount) agents loaded (template)"
        }
    }
    catch {
        Write-Warn "Agent Teams check skipped: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "=== Claude 設定サマリー ===" -ForegroundColor Yellow
    Write-Host "Template : $templateClaude"
    Write-Host "Settings : $templateSettings"
    Write-Host "Prompt   : $templatePrompt"
    Write-Host "Language : 日本語"
    Write-Host "Structure: .claude/claudeos"
    Write-Host "Mode     : Auto Mode + Agent Teams / WorkTree"
    Write-Host "Loop     : Monitor -> Build -> Verify -> Improve"
    Write-Host "Git Rule : main 直接 push 禁止 / PR 必須 / CI 成功のみ merge"
    Write-Host "Stop     : 8 時間 / Loop Guard / Token 95% / 重大リスク"
    if ($toolConfig.env) {
        $envLabels = @($toolConfig.env.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value })
        if ($envLabels.Count -gt 0) {
            Write-Host ("Env      : " + ($envLabels -join ', '))
        }
    }

    Write-Host ""
    Write-Host "=== Claude 起動プロンプト ===" -ForegroundColor Yellow
    Write-Host "SSH 自動投入時も以下を基準に送信します。" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[LOOP_COMMANDS]" -ForegroundColor DarkGray
    Write-Host $promptSections.LoopCommands
    Write-Host ""
    Write-Host "[PROMPT_BODY]" -ForegroundColor DarkGray
    Write-Host $promptSections.PromptBody

    $remoteBootstrap = "$linuxProject/.claude/claude_startup_bridge.sh"
    $remoteBridgePath = "$linuxProject/.claude/claude_pty_bridge.py"

    $startupCmdB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($claudeCommand))
    $promptB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($promptSections.FullText))

    $deployParts = @(
        "set -e"
        "mkdir -p $(ConvertTo-BashSingleQuoted -Value "$linuxProject/.claude")"
        (New-RemoteTemplateDeployScript -TemplatePath $templateClaude -TargetPath "$linuxProject/CLAUDE.md" -Label 'CLAUDE.md')
        (New-RemoteTemplateDeployScript -TemplatePath $templateClaude -TargetPath "$linuxProject/.claude/CLAUDE.md" -Label '.claude/CLAUDE.md' -EnsureParentDirectory)
        (New-RemoteTemplateDeployScript -TemplatePath $templateSettings -TargetPath "$linuxProject/.claude/settings.json" -Label '.claude/settings.json' -EnsureParentDirectory)
        (New-RemoteTemplateDeployScript -TemplatePath $templatePrompt -TargetPath "$linuxProject/.claude/START_PROMPT.md" -Label '.claude/START_PROMPT.md' -EnsureParentDirectory)
        (New-RemoteTemplateDeployScript -TemplatePath $bridgeSource -TargetPath $remoteBridgePath -Label '.claude/claude_pty_bridge.py' -EnsureParentDirectory)
        (New-RemoteTemplateDeployScript -TemplatePath (Join-Path $ScriptRoot 'scripts\templates\claude-statusline.py') -TargetPath "$linuxProject/.claude/statusline.py" -Label '.claude/statusline.py' -EnsureParentDirectory)
@"
cat > $(ConvertTo-BashSingleQuoted -Value $remoteBootstrap) <<'EOF'
#!/usr/bin/env bash
set -e
cd $(ConvertTo-BashSingleQuoted -Value $linuxProject)
export STARTUP_CMD_B64='${startupCmdB64}'
export PROMPT_B64='${promptB64}'
export CLAUDE_PROJECT='${Project}'
exec python3 $(ConvertTo-BashSingleQuoted -Value $remoteBridgePath)
EOF
chmod +x $(ConvertTo-BashSingleQuoted -Value $remoteBootstrap)
"@
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $deployScript = ($deployParts -join "`n`n") + "`n"

    if ($DryRun) {
        Write-Info "SSH接続先: $linuxHost"
        Write-Host $deployScript
        Write-Host ""
        Write-Host ("exec bash " + (ConvertTo-BashSingleQuoted -Value $remoteBootstrap))
        $launchContext.Result = 'success'
        exit 0
    }

    Write-Info "Connecting via SSH: $linuxHost"
    $deployExitCode = Invoke-ClaudeSshViaStdin -LinuxHost $linuxHost -ScriptText $deployScript
    if ($deployExitCode -ne 0) {
        $launchContext.Result = 'failure'
        exit $deployExitCode
    }

    # SSH起動通知音（ノンブロッキング：デプロイ完了後、セッション開始前）
    Invoke-LauncherNotificationSound -Tool 'claude' -Config $Config -Wait $false

    $runScript = "cd $(ConvertTo-BashSingleQuoted -Value $linuxProject) && exec bash $(ConvertTo-BashSingleQuoted -Value $remoteBootstrap)"
    $sshExitCode = Invoke-LauncherSshScript -LinuxHost $linuxHost -RunScript $runScript -RemoteScriptName "run-claude-$Project.sh"
    if ($sshExitCode -eq 255) {
        $launchContext.Result = 'failure'
        exit $sshExitCode
    }

    $launchContext.Result = if ($sshExitCode -eq 0) { 'success' } else { 'failure' }
    if ($sshExitCode -eq 0) {
        Write-Ok 'Claude Code session finished.'
    }
    exit $sshExitCode
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
    # 終了通知音（同期再生：セッション終了を確実に通知）
    Invoke-LauncherNotificationSound -Tool 'claude' -Config $Config -Wait $true
    # インスタンスロック解放
    if ($null -ne $instanceMutex) {
        try { $instanceMutex.ReleaseMutex() } catch { Write-Debug "ReleaseMutex failed (mutex may already be released): $_" }
        $instanceMutex.Dispose()
    }
}
