<#
.SYNOPSIS
    Claude Code 統合開発環境セットアップスクリプト v1.3.0

.DESCRIPTION
    Edge/Chrome ブラウザと Linux 上の Claude Code を統合したリモート開発環境をセットアップします。
    モジュール化アーキテクチャにより、Edge/Chrome 共通の処理を一元管理します。

.PARAMETER Browser
    使用するブラウザ ('edge' または 'chrome')。省略時は対話的に選択。

.PARAMETER Project
    プロジェクト名 (ZDrive配下のディレクトリ名)。省略時は対話的に選択。

.PARAMETER Port
    DevTools ポート番号 (1024-65535)。省略時は自動選択。

.PARAMETER NonInteractive
    対話モードを無効化します。-Browser と -Project の指定が必須になります。

.PARAMETER DryRun
    実際には実行せず、実行内容のプレビューのみ表示します。

.PARAMETER Layout
    tmux レイアウト名 ('auto', 'default', 'review-team', 'fullstack-dev-team', 'debug-team', 'none')。
    'none' を指定すると tmux を強制無効化します。

.EXAMPLE
    .\Claude-DevTools.ps1
    対話モードで起動（デフォルト）

.EXAMPLE
    .\Claude-DevTools.ps1 -Browser chrome -Project "my-app"
    Chrome + my-app で起動

.EXAMPLE
    .\Claude-DevTools.ps1 -Browser edge -Project "backend-api" -Port 9223 -NonInteractive
    完全非対話モードで起動（CI/CD 対応）

.EXAMPLE
    .\Claude-DevTools.ps1 -DryRun
    実行内容のプレビューのみ表示
#>

param(
    [ValidateSet('edge', 'chrome', '')]
    [string]$Browser = '',

    [string]$Project = '',

    [ValidateRange(0, 65535)]
    [int]$Port = 0,

    [switch]$NonInteractive,

    [switch]$DryRun,

    [string]$Layout = ''
)

$ErrorActionPreference = "Stop"

# ===== ログ記録開始（LogManager: Config読み込み後に再設定） =====
$LogPath = $null

# ===== モジュール読み込み =====
$LibPath = Join-Path (Split-Path $PSScriptRoot -Parent) "lib"

$modulesToLoad = @(
    "ErrorHandler.psm1",
    "Config.psm1",
    "LogManager.psm1",
    "PortManager.psm1",
    "SSHHelper.psm1",
    "BrowserManager.psm1",
    "UI.psm1",
    "ScriptGenerator.psm1"
)

foreach ($mod in $modulesToLoad) {
    $modPath = Join-Path $LibPath $mod
    if (Test-Path $modPath) {
        Import-Module $modPath -Force -ErrorAction Stop
    } else {
        Write-Warning "モジュールが見つかりません: $modPath（一部機能が制限される可能性があります）"
    }
}

# ===== グローバル変数 (クリーンアップ用) =====
$Global:BrowserProcess = $null
$Global:DevToolsPort = $null
$Global:LinuxHost = $null

# ===== エラートラップ (クリーンアップハンドラー) =====
trap {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host "⚠️ エラーが発生しました" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host "`n❌ エラー詳細: $_" -ForegroundColor Red
    Write-Host "   発生場所: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n" -ForegroundColor Red
    Write-Host "🧹 クリーンアップ中..." -ForegroundColor Yellow

    if ($Global:BrowserProcess) {
        try {
            if (-not $Global:BrowserProcess.HasExited) {
                Write-Host "🧹 ブラウザプロセスを終了中 (PID: $($Global:BrowserProcess.Id))..."
                $Global:BrowserProcess | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
        } catch { }
    }

    if ($LogPath) {
        Write-Host "`n📄 詳細ログ: $LogPath" -ForegroundColor Cyan
    }

    if ($Global:DevToolsPort -and $Global:LinuxHost) {
        try {
            ssh -o ConnectTimeout=3 -o BatchMode=yes $Global:LinuxHost "fuser -k $($Global:DevToolsPort)/tcp 2>/dev/null || true" 2>$null
        } catch { }
    }

    Write-Host "`n❌ スクリプトを中断しました。`n" -ForegroundColor Red
    exit 1
}

# ===== バナー表示 =====
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  🤖 Claude DevTools セットアップ v1.3.0" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  🔍 DRY RUN モード（実際の変更は行いません）" -ForegroundColor Yellow
}
Write-Host ""

# ===== NonInteractive チェック =====
if ($NonInteractive) {
    if (-not $Browser) { throw "-NonInteractive モードでは -Browser (edge/chrome) の指定が必須です" }
    if (-not $Project) { throw "-NonInteractive モードでは -Project の指定が必須です" }
    Write-Host "🤖 非対話モードで実行: Browser=$Browser, Project=$Project" -ForegroundColor Cyan
}

# ===== 設定ファイル読み込み =====
$RootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $RootDir "config\config.json"

$Config = Import-DevToolsConfig -ConfigPath $ConfigPath

$ZRoot     = $Config.zDrive
$ZUncPath  = $Config.zDriveUncPath
$LinuxHost = $Config.linuxHost
$LinuxBase = $Config.linuxBase
$EdgeExe   = $Config.edgeExe
$ChromeExe = $Config.chromeExe

$Global:LinuxHost = $LinuxHost

# config.json バックアップ
if ($Config.backupConfig -and $Config.backupConfig.enabled -and -not $DryRun) {
    try {
        Backup-ConfigFile `
            -ConfigPath $ConfigPath `
            -BackupDir $Config.backupConfig.backupDir `
            -MaxBackups $Config.backupConfig.maxBackups `
            -MaskSensitive $Config.backupConfig.maskSensitive `
            -SensitiveKeys $Config.backupConfig.sensitiveKeys
    } catch {
        Write-Warning "バックアップに失敗しましたが続行します: $_"
    }
}

# ===== ポート選択 =====
if ($Port -gt 0) {
    # CLI指定ポートを使用
    if (-not (Test-PortAvailable -Port $Port)) {
        Write-Warning "指定されたポート $Port は使用中です。自動選択に切り替えます。"
        $Port = 0
    }
}

if ($Port -eq 0) {
    $DevToolsPort = Get-AvailablePort -Ports $Config.ports
    if (-not $DevToolsPort) {
        throw "❌ 利用可能なポートがありません。ポート $($Config.ports -join ', ') はすべて使用中です。"
    }
} else {
    $DevToolsPort = $Port
}

$Global:DevToolsPort = $DevToolsPort
Write-Host "✅ DevTools ポート: $DevToolsPort"

# ===== SSH 接続事前確認 =====
Write-Host "`n🔍 SSH 接続確認中: $LinuxHost ..." -ForegroundColor Cyan
if (-not $DryRun) {
    if (-not (Test-SSHConnection -Host $LinuxHost)) {
        throw "SSH 接続テストに失敗しました。上記の確認事項を参照してください。"
    }
    Write-Host "✅ SSH 接続成功" -ForegroundColor Green
} else {
    Write-Host "  [DryRun] SSH 接続テストをスキップ" -ForegroundColor Gray
}

# ===== ブラウザ選択 =====
if ($Browser -eq '' -and -not $NonInteractive) {
    $browserInfo = Select-Browser -DefaultBrowser $Config.defaultBrowser -EdgeExe $EdgeExe -ChromeExe $ChromeExe
} else {
    $browserType = if ($Browser -eq '') { $Config.defaultBrowser } else { $Browser }
    $browserInfo = @{
        Type    = $browserType
        Exe     = if ($browserType -eq 'chrome') { $ChromeExe } else { $EdgeExe }
        Name    = if ($browserType -eq 'chrome') { 'Google Chrome' } else { 'Microsoft Edge' }
    }
}

$SelectedBrowser = $browserInfo.Type
$BrowserExe      = $browserInfo.Exe
$BrowserName     = $browserInfo.Name

if (-not (Test-Path $BrowserExe)) {
    throw "❌ $BrowserName が見つかりません: $BrowserExe"
}

Write-Host "🌐 ブラウザ: $BrowserName" -ForegroundColor Cyan

# ===== プロジェクトルート解決 =====
Write-Host "`n🔍 プロジェクトルート確認..." -ForegroundColor Cyan
$ProjectRootPath = Resolve-ProjectRootPath -ZRoot $ZRoot -ZUncPath $ZUncPath

$Projects = Get-ChildItem $ProjectRootPath -Directory | Sort-Object Name
if ($Projects.Count -eq 0) {
    throw "❌ プロジェクトルート ($ProjectRootPath) にプロジェクトが見つかりません"
}

# ===== プロジェクト選択 =====
$HistoryEnabled = $Config.recentProjects -and $Config.recentProjects.enabled
$HistoryPath = if ($HistoryEnabled) {
    [System.Environment]::ExpandEnvironmentVariables($Config.recentProjects.historyFile)
} else { '' }

$RecentProjects = @()
if ($HistoryEnabled -and $HistoryPath) {
    $RecentProjects = Get-RecentProjects -HistoryPath $HistoryPath
}

if ($Project -ne '' -and -not $NonInteractive) {
    # -Project 指定時はマッチするプロジェクトを検索
    $selectedProject = $Projects | Where-Object { $_.Name -eq $Project } | Select-Object -First 1
    if (-not $selectedProject) {
        throw "❌ 指定されたプロジェクトが見つかりません: $Project"
    }
} elseif ($NonInteractive -and $Project -ne '') {
    $selectedProject = $Projects | Where-Object { $_.Name -eq $Project } | Select-Object -First 1
    if (-not $selectedProject) {
        throw "❌ 指定されたプロジェクトが見つかりません: $Project"
    }
} else {
    $selectedProject = Select-Project -ProjectRootPath $ProjectRootPath -Projects $Projects -RecentProjects $RecentProjects
}

$ProjectName = $selectedProject.Name
$ProjectRoot = $selectedProject.FullName

Write-Host "`n✅ 選択プロジェクト: $ProjectName" -ForegroundColor Green

# ===== LogManager によるセッションログ開始 =====
if (-not $DryRun) {
    $logResult = Start-SessionLog -Config $Config -ProjectName $ProjectName -Browser $SelectedBrowser -Port $DevToolsPort
    $LogPath = $logResult.LogPath
}

if ($HistoryEnabled -and $HistoryPath -and -not $DryRun) {
    try {
        Update-RecentProjects -ProjectName $ProjectName -HistoryPath $HistoryPath -MaxHistory $Config.recentProjects.maxHistory
    } catch {
        Write-Warning "履歴更新に失敗しましたが続行します: $_"
    }
}

# ===== DryRun プレビュー =====
if ($DryRun) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host "🔍 DryRun プレビュー" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ブラウザ    : $BrowserName"
    Write-Host "  プロジェクト: $ProjectName"
    Write-Host "  ポート      : $DevToolsPort"
    Write-Host "  Linux ホスト: $LinuxHost"
    Write-Host "  Linux パス  : $LinuxBase/$ProjectName"
    Write-Host "  プロファイル: $($Config.browserProfileDir)DevTools-$SelectedBrowser-$DevToolsPort"
    $effectiveLayout = if ($Layout -ne '') { $Layout } else { $Config.tmux.defaultLayout }
    Write-Host "  tmux レイアウト: $effectiveLayout (enabled: $($Config.tmux.enabled))"
    Write-Host ""
    Write-Host "  実行される処理:"
    Write-Host "  1. ブラウザ起動 (--remote-debugging-port=$DevToolsPort)"
    Write-Host "  2. run-claude.sh 生成 → Linux 側に転送"
    Write-Host "  3. SSH バッチセットアップ (statusline/settings/MCP)"
    Write-Host "  4. SSH 接続 + run-claude.sh 実行"
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow

    exit 0
}

# ===== ブラウザ起動 =====
$ProfileBaseDir = if ($Config.browserProfileDir) {
    [System.Environment]::ExpandEnvironmentVariables($Config.browserProfileDir)
} else { "C:\" }

$BrowserProfile = Join-Path $ProfileBaseDir "DevTools-$SelectedBrowser-$DevToolsPort"
$ProcessName    = if ($SelectedBrowser -eq "edge") { "msedge" } else { "chrome" }

Write-Host "`n🌐 $BrowserName DevTools 起動準備..."

# 既存プロセス終了
Remove-ExistingBrowserProfiles -ProcessName $ProcessName -BrowserType $SelectedBrowser -Port $DevToolsPort

# プロファイルディレクトリ作成
if (-not (Test-Path $BrowserProfile)) {
    New-Item -ItemType Directory -Path $BrowserProfile -Force | Out-Null
    Write-Host "📁 プロファイルディレクトリ作成: $BrowserProfile"
}

# DevTools Preferences 設定 (Edge のみ)
if ($SelectedBrowser -eq "edge") {
    Set-BrowserDevToolsPreferences -BrowserProfile $BrowserProfile
}

# ブラウザ起動
$StartUrl = "http://localhost:$DevToolsPort"
$browserProc = Start-DevToolsBrowser `
    -BrowserExe $BrowserExe `
    -BrowserName $BrowserName `
    -BrowserProfile $BrowserProfile `
    -DevToolsPort $DevToolsPort `
    -StartUrl $StartUrl

$Global:BrowserProcess = $browserProc

# DevTools 準備待機
$versionInfo = Wait-DevToolsReady -Port $DevToolsPort -MaxWaitSeconds 15

if ($versionInfo) {
    Write-Host "✅ $BrowserName DevTools 接続成功!" -ForegroundColor Green
    Write-Host "   Browser: $($versionInfo.Browser)"
    Write-Host "   Protocol: $($versionInfo.'Protocol-Version')"
} else {
    Write-Warning "$BrowserName DevTools の応答がありません。続行しますか？"
    $continue = Read-Host "続行しますか？ (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") { exit 1 }
}

# ===== run-claude.sh 生成 =====
Write-Host "`n📝 run-claude.sh 生成中..."

# INIT_PROMPT テンプレート読み込み（言語設定に応じて自動選択）
$TemplatesDir = Join-Path (Split-Path $PSScriptRoot -Parent) "templates"
$langSetting  = if ($Config.claudeCode -and $Config.claudeCode.settings) { $Config.claudeCode.settings.language } else { "" }
$lang         = if ($langSetting -match '英語|english|en') { 'en' } else { 'ja' }
$InitPromptFile = Join-Path $TemplatesDir "init-prompt-${lang}.txt"
$InitPromptContent = ""
if (Test-Path $InitPromptFile) {
    $InitPromptContent = Get-Content $InitPromptFile -Raw -Encoding UTF8
    Write-Host "  📖 INIT_PROMPT: テンプレートファイルから読み込み ($InitPromptFile)" -ForegroundColor Gray
} else {
    Write-Host "  ⚠️  INIT_PROMPT テンプレートが見つかりません: $InitPromptFile" -ForegroundColor Yellow
}

# tmux 設定
$effectiveLayout = if ($Layout -eq 'none') {
    'none'
} elseif ($Layout -ne '') {
    $Layout
} else {
    $Config.tmux.defaultLayout
}

$tmuxEnabled = ($Config.tmux.enabled -and $effectiveLayout -ne 'none')

$runClaudeParams = @{
    Port           = $DevToolsPort
    LinuxBase      = $LinuxBase
    ProjectName    = $ProjectName
    Layout         = $effectiveLayout
    TmuxEnabled    = $tmuxEnabled
    InitPrompt     = $InitPromptContent
    Language       = $lang
    EnvVars        = $Config.claudeCode.env
}

$RunClaudeContent = New-RunClaudeScript -Params $runClaudeParams
$RunClaudePath = Join-Path $ProjectRoot "run-claude.sh"
$LinuxPath = "$LinuxBase/$ProjectName/run-claude.sh"

# CRLF → LF 変換
$RunClaudeContent = $RunClaudeContent -replace "`r`n", "`n" -replace "`r", "`n"
[System.IO.File]::WriteAllText($RunClaudePath, $RunClaudeContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "✅ run-claude.sh 生成完了: $RunClaudePath" -ForegroundColor Green

# ===== リモートセットアップ (SSH バッチ) =====
Write-Host "`n🔧 リモートセットアップ実行中..." -ForegroundColor Cyan

# statusline.sh 読み込み
$StatuslineSource = Join-Path (Split-Path $PSScriptRoot -Parent) "statusline.sh"
$statuslineEnabled = $Config.statusline -and $Config.statusline.enabled -and (Test-Path $StatuslineSource)
$encodedStatusline = ""
$encodedSettings   = ""
$encodedGlobalScript = ""

if ($statuslineEnabled) {
    $statuslineContent = Get-Content $StatuslineSource -Raw
    $statuslineContent = $statuslineContent -replace "`r`n", "`n" -replace "`r", "`n"
    $encodedStatusline = ConvertTo-Base64Utf8 -Content $statuslineContent

    # settings.json 生成
    $settingsObj = @{
        statusLine = @{
            type    = "command"
            command = "$LinuxBase/$ProjectName/.claude/statusline.sh"
            padding = 0
        }
    }
    $settingsJson = $settingsObj | ConvertTo-Json -Depth 3 -Compress
    $encodedSettings = ConvertTo-Base64Utf8 -Content $settingsJson

    # グローバル設定更新スクリプト生成
    $jsonParts = Build-ClaudeCodeJsonFromConfig -ClaudeEnv $Config.claudeCode.env -ClaudeSettings $Config.claudeCode.settings
    $globalScript = @"
#!/bin/bash
SETTINGS_FILE="`$HOME/.claude/settings.json"
mkdir -p "`$HOME/.claude"

if [ -f "`$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
    jq '. + $($jsonParts.SettingsJson) + {
      "statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}
    } | .env = ((.env // {}) + $($jsonParts.EnvJson))' "`$SETTINGS_FILE" > "`$SETTINGS_FILE.tmp" && mv "`$SETTINGS_FILE.tmp" "`$SETTINGS_FILE"
    echo "✅ グローバル設定をマージ更新しました"
else
    cat > "`$SETTINGS_FILE" << 'SETTINGSEOF'
$($jsonParts.FullJson)
SETTINGSEOF
    echo "✅ グローバル設定を新規作成しました"
fi
"@
    $globalScript = $globalScript -replace "`r`n", "`n" -replace "`r", "`n"
    $encodedGlobalScript = ConvertTo-Base64Utf8 -Content $globalScript
}

# MCP セットアップ
$McpSetupSource = Join-Path (Split-Path $PSScriptRoot -Parent) "mcp\setup-mcp.sh"
$McpEnabled = $Config.mcp -and $Config.mcp.enabled -and $Config.mcp.autoSetup -and (Test-Path $McpSetupSource)
$EncodedMcpScript = ""
$GithubTokenB64 = if ($Config.mcp.githubToken) { $Config.mcp.githubToken } else { "" }
$BraveApiKey    = if ($Config.mcp.braveApiKey) { $Config.mcp.braveApiKey } else { "" }

if ($McpEnabled) {
    $mcpContent = Get-Content $McpSetupSource -Raw
    $mcpContent = $mcpContent -replace "`r`n", "`n" -replace "`r", "`n"
    $EncodedMcpScript = ConvertTo-Base64Utf8 -Content $mcpContent
}

# 変数エスケープ
$EscapedLinuxBase    = Escape-SSHArgument $LinuxBase
$EscapedProjectName  = Escape-SSHArgument $ProjectName
$EscapedLinuxPath    = Escape-SSHArgument $LinuxPath
$EscapedDevToolsPort = Escape-SSHArgument "$DevToolsPort"
$McpBackupTimestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'

# 統合セットアップスクリプト生成
$SetupScript = @"
#!/bin/bash
set -euo pipefail

MCP_ENABLED=$($McpEnabled.ToString().ToLower())
MCP_BACKUP_TIMESTAMP='$McpBackupTimestamp'

echo "🔍 jq パッケージ確認..."
if ! command -v jq &>/dev/null; then
    echo "⚠️  jq インストール中..."
    apt-get update && apt-get install -y jq 2>/dev/null || \
    yum install -y jq 2>/dev/null || \
    echo "❌ jq インストール失敗（手動でインストールしてください）"
fi

echo "📁 ディレクトリ作成中..."
mkdir -p $EscapedLinuxBase/$EscapedProjectName/.claude
mkdir -p ~/.claude

$(if ($statuslineEnabled -and $encodedStatusline) {
"echo '📝 statusline.sh 配置中...'
echo '$encodedStatusline' | base64 -d > $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh
chmod +x $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh
cp $EscapedLinuxBase/$EscapedProjectName/.claude/statusline.sh ~/.claude/statusline.sh

echo '⚙️  settings.json 配置中...'
echo '$encodedSettings' | base64 -d > $EscapedLinuxBase/$EscapedProjectName/.claude/settings.json

echo '🔄 グローバル設定更新中...'
echo '$encodedGlobalScript' | base64 -d > /tmp/update_global_settings.sh
chmod +x /tmp/update_global_settings.sh
/tmp/update_global_settings.sh
rm /tmp/update_global_settings.sh"
} else { "echo 'ℹ️  Statusline 無効'" })

echo "📦 .mcp.json バックアップ中..."
if [ -f $EscapedLinuxBase/$EscapedProjectName/.mcp.json ]; then
    cp $EscapedLinuxBase/$EscapedProjectName/.mcp.json $EscapedLinuxBase/$EscapedProjectName/.mcp.json.bak.`${MCP_BACKUP_TIMESTAMP}
    echo "✅ バックアップ完了"
fi

if [ "`$MCP_ENABLED" = "true" ]; then
    echo "🔌 MCP セットアップ中..."
    MCP_SETUP_SCRIPT="/tmp/setup-mcp-`${MCP_BACKUP_TIMESTAMP}.sh"
    echo '$EncodedMcpScript' | base64 -d > "`${MCP_SETUP_SCRIPT}"
    chmod +x "`${MCP_SETUP_SCRIPT}"
    "`${MCP_SETUP_SCRIPT}" "$EscapedLinuxBase/$EscapedProjectName" '$GithubTokenB64' '$BraveApiKey' || echo "⚠️  MCP セットアップでエラーが発生しましたが続行します"
    rm -f "`${MCP_SETUP_SCRIPT}"
fi

echo "🔧 run-claude.sh 実行権限付与中..."
chmod +x $EscapedLinuxPath

echo "🧹 ポート $EscapedDevToolsPort クリーンアップ中..."
fuser -k $EscapedDevToolsPort/tcp 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ リモートセットアップ完了"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"@

$SetupScript = $SetupScript -replace "`r`n", "`n" -replace "`r", "`n"
$encodedSetup = ConvertTo-Base64Utf8 -Content $SetupScript
$setupResult = ssh $LinuxHost "echo '$encodedSetup' | base64 -d > /tmp/remote_setup.sh && chmod +x /tmp/remote_setup.sh && /tmp/remote_setup.sh && rm /tmp/remote_setup.sh"
if ($LASTEXITCODE -ne 0) {
    throw "リモートセットアップが失敗しました (exit code: $LASTEXITCODE)"
}
Write-Host $setupResult

if ($statuslineEnabled) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Statusline 反映: Claude Code で /statusline を実行" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

# ===== SSH 接続 + Claude 起動 =====
Write-Host "`n🎉 セットアップ完了"
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "🚀 Claude Code を起動します..."
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

$EscapedLinuxBaseForSSH   = Escape-SSHArgument $LinuxBase
$EscapedProjectNameForSSH = Escape-SSHArgument $ProjectName

# SSH stderr 出力（ポートフォワーディング警告等）が $ErrorActionPreference="Stop" で
# terminating error になるのを防止するため、stderr を抑制し $LASTEXITCODE で判定する
$ErrorActionPreference = "Continue"
ssh -t -o ControlMaster=no -o ControlPath=none -R "${DevToolsPort}:127.0.0.1:${DevToolsPort}" $LinuxHost "cd $EscapedLinuxBaseForSSH/$EscapedProjectNameForSSH && ./run-claude.sh" 2>$null
$sshExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"

if ($sshExitCode -ne 0) {
    Write-Warning "SSH セッションが終了コード $sshExitCode で終了しました"
}

# ===== ログ記録終了 =====
if ($LogPath) {
    $sshSuccess = ($sshExitCode -eq 0)
    Stop-SessionLog -Success $sshSuccess
    Invoke-LogRotation -Config $Config
}
