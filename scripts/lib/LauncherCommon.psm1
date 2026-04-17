function Get-StartupRoot {
    param(
        [Parameter(Mandatory)]
        [string]$PSScriptRootPath
    )

    return (Split-Path -Parent (Split-Path -Parent $PSScriptRootPath))
}

function Get-StartupConfigPath {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot
    )

    if ($env:AI_STARTUP_CONFIG_PATH) {
        return $env:AI_STARTUP_CONFIG_PATH
    }

    return (Join-Path $StartupRoot "config\\config.json")
}

function Import-LauncherConfig {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }

    return (Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Find-AvailableDriveLetter {
    [CmdletBinding()]
    param(
        [string[]]$PreferredLetters = @('P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'Y'),
        [string[]]$ExcludeLetters = @()
    )

    $usedLetters = @((Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Name)

    foreach ($letter in $PreferredLetters) {
        if ($letter -notin $usedLetters -and $letter -notin $ExcludeLetters) {
            return $letter
        }
    }

    # Preferred list exhausted — scan Z down to D
    for ($code = [int][char]'Z'; $code -ge [int][char]'D'; $code--) {
        $letter = [char]$code
        if ("$letter" -notin $usedLetters -and "$letter" -notin $ExcludeLetters) {
            return "$letter"
        }
    }

    return $null
}

function Resolve-SshProjectsDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $sshDir = $Config.sshProjectsDir

    if ([string]::IsNullOrWhiteSpace($sshDir) -or $sshDir -eq 'auto') {
        # Auto-detect: check if already mapped to projectsDirUnc
        $uncPath = $Config.projectsDirUnc
        if (-not [string]::IsNullOrWhiteSpace($uncPath)) {
            $existingDrive = Get-SmbMapping -ErrorAction SilentlyContinue |
                Where-Object { $_.RemotePath -eq $uncPath -and $_.Status -eq 'OK' } |
                Select-Object -First 1

            if ($existingDrive) {
                $letter = ($existingDrive.LocalPath -replace ':', '')
                Write-Host "[INFO]  既存マッピング検出: ${letter}:\ -> $uncPath" -ForegroundColor Cyan
                return "${letter}:\"
            }
        }

        # No existing mapping — find available letter and map
        $letter = Find-AvailableDriveLetter
        if (-not $letter) {
            throw "空きドライブレターが見つかりません。config.json の sshProjectsDir に明示的なドライブレターを指定してください。"
        }

        if (-not [string]::IsNullOrWhiteSpace($uncPath)) {
            try {
                $null = New-PSDrive -Name $letter -PSProvider FileSystem -Root $uncPath -Persist -Scope Global -ErrorAction Stop
                Write-Host "[INFO]  ドライブ自動マッピング: ${letter}:\ -> $uncPath" -ForegroundColor Green
            }
            catch {
                Write-Warning "ドライブ自動マッピングに失敗しました (${letter}: -> $uncPath): $_"
                Write-Host "[INFO]  SSH 直接接続にフォールバックします。" -ForegroundColor Yellow
                return "auto:unmapped"
            }
        }
        else {
            Write-Host "[INFO]  projectsDirUnc 未設定のため、SSH 直接接続を使用します。" -ForegroundColor Yellow
            return "auto:unmapped"
        }

        return "${letter}:\"
    }

    return $sshDir
}

function Test-LauncherCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Assert-LauncherToolAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [string]$InstallCommand,
        [Parameter(Mandatory)]
        [string]$ToolLabel,
        [switch]$NonInteractive
    )

    if (Test-LauncherCommand -Command $Command) {
        return $true
    }

    Write-Host "[WARN] $Command コマンドが見つかりません。" -ForegroundColor Yellow
    Write-Host "[INFO] インストール: $InstallCommand" -ForegroundColor Cyan
    if ($NonInteractive) {
        return $false
    }

    $answer = Read-Host "今すぐインストールしますか？ [y/N]"
    if ($answer -match '^[yY]') {
        $installParts = $InstallCommand -split '\s+' | Where-Object { $_ }
        & $installParts[0] ($installParts[1..($installParts.Count - 1)])
        return (Test-LauncherCommand -Command $Command)
    }

    return $false
}

function Get-LauncherApiKeyValue {
    param(
        [string]$ApiKeyName,
        [object]$EnvMap
    )

    if ([string]::IsNullOrWhiteSpace($ApiKeyName)) {
        return $null
    }

    $value = [Environment]::GetEnvironmentVariable($ApiKeyName)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
    }

    if ($EnvMap) {
        $envProperty = $EnvMap.PSObject.Properties[$ApiKeyName]
        if ($envProperty -and -not [string]::IsNullOrWhiteSpace($envProperty.Value)) {
            return $envProperty.Value
        }
    }

    return $null
}

function Show-LauncherApiKeyWarning {
    param(
        [string]$ApiKeyName,
        [string]$LoginHint,
        [string]$ApiHint
    )

    if ([string]::IsNullOrWhiteSpace($ApiKeyName)) {
        return
    }

    Write-Host "[WARN] $ApiKeyName は未設定です。" -ForegroundColor Yellow
    if ($LoginHint) {
        Write-Host "[INFO] $LoginHint" -ForegroundColor Cyan
    }
    if ($ApiHint) {
        Write-Host "[INFO] $ApiHint" -ForegroundColor Cyan
    }
}

function Resolve-LauncherMode {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [switch]$Local,
        [switch]$NonInteractive,
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if ($Local) {
        return $true
    }

    if ($Config.linuxHost) {
        return $false
    }

    Write-Host ""
    Write-Host "=== Linux接続先未設定 ===" -ForegroundColor Yellow
    Write-Host "config.json に linuxHost が設定されていません。" -ForegroundColor Yellow
    Write-Host "リモート実行を使うには設定が必要です。" -ForegroundColor Yellow
    Write-Host ""

    if ($NonInteractive) {
        throw "config.json に linuxHost が未設定のため、非対話モードでは続行できません: $ConfigPath"
    }

    Write-Host "[L] ローカル実行を続ける" -ForegroundColor Cyan
    Write-Host "[C] config.json を開いて設定する" -ForegroundColor Cyan
    Write-Host "[0] 終了" -ForegroundColor Cyan
    $choice = Read-Host "選択してください"

    switch ($choice.ToUpper()) {
        "L" { return $true }
        "C" {
            Start-Process notepad.exe $ConfigPath
            throw "USER_CANCELLED"
        }
        default {
            throw "USER_CANCELLED"
        }
    }
}

function Resolve-LauncherProject {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [string]$Project,
        [switch]$Local,
        [switch]$NonInteractive,
        [string]$LinuxHost
    )

    if ($Project) {
        return $Project
    }

    $projectsRoot = if ($Local) { $Config.projectsDir } else { Resolve-SshProjectsDir -Config $Config }
    $dirs = $null

    if (Test-Path $projectsRoot) {
        $dirs = Get-ChildItem -Path $projectsRoot -Directory | Sort-Object Name
        if ($Local -and $Config.localExcludes) {
            $dirs = $dirs | Where-Object { $_.Name -notin $Config.localExcludes }
        }
    }
    elseif (-not $Local -and $LinuxHost -and $Config.linuxBase) {
        # ドライブ未接続または auto:unmapped — SSH 経由でリモートのプロジェクト一覧を取得
        if ($projectsRoot -eq 'auto:unmapped') {
            Write-Host "[INFO] ドライブマッピングなし。SSH 経由でプロジェクト一覧を取得します..." -ForegroundColor Cyan
        } else {
            Write-Host "[INFO] $projectsRoot にアクセスできません。SSH 経由でプロジェクト一覧を取得します..." -ForegroundColor Cyan
        }
        $sshCommand = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { "ssh" }
        $connectTimeout = if ($env:AI_STARTUP_SSH_CONNECT_TIMEOUT) { $env:AI_STARTUP_SSH_CONNECT_TIMEOUT } else { "10" }
        try {
            $remoteDirs = & $sshCommand -o "ConnectTimeout=$connectTimeout" -o "StrictHostKeyChecking=accept-new" $LinuxHost "ls -d $($Config.linuxBase)/*/ 2>/dev/null" 2>&1
            if ($LASTEXITCODE -eq 0 -and $remoteDirs) {
                $dirNames = @($remoteDirs | ForEach-Object { ($_ -replace '/$', '').Split('/')[-1] } | Sort-Object)
                if ($dirNames.Count -gt 0) {
                    $dirs = $dirNames | ForEach-Object { [pscustomobject]@{ Name = $_ } }
                }
            }
            else {
                throw "SSH 接続またはディレクトリ取得に失敗しました (exit=$LASTEXITCODE)"
            }
        }
        catch {
            throw @"
SSH プロジェクトフォルダにアクセスできません。

ローカルパス ($projectsRoot) が未接続で、SSH 経由の取得にも失敗しました:
  $_

確認事項:
  1. Linux ホスト ($LinuxHost) が起動しているか確認
  2. ssh $LinuxHost echo test で手動接続を確認
  3. ネットワークドライブを接続: net use $($projectsRoot.Substring(0,2)) $($Config.projectsDirUnc)
"@
        }
    }
    else {
        throw "プロジェクトルートが見つかりません: $projectsRoot"
    }

    if (-not $dirs -or @($dirs).Count -eq 0) {
        throw "プロジェクトが見つかりません: $projectsRoot"
    }

    if ($NonInteractive) {
        throw "非対話モードでは -Project の指定が必要です。"
    }

    Show-LauncherProjectChoices -Projects $dirs.Name -Local:$Local -LinuxHost $LinuxHost

    $num = Read-Host "番号を入力してください"
    $numInt = $num -as [int]
    if (-not $numInt -or $numInt -lt 1 -or $numInt -gt $dirs.Count) {
        throw "USER_CANCELLED"
    }

    return $dirs[$numInt - 1].Name
}

function Show-LauncherProjectChoices {
    param(
        [Parameter(Mandatory)]
        [string[]]$Projects,
        [switch]$Local,
        [string]$LinuxHost
    )

    Write-Host ""
    Write-Host "=== プロジェクト選択 ===" -ForegroundColor Cyan
    if (-not $Local -and $LinuxHost) {
        Write-Host "接続先: $LinuxHost" -ForegroundColor DarkGray
    }
    for ($i = 0; $i -lt $Projects.Count; $i++) {
        "{0,2}: {1}" -f ($i + 1), $Projects[$i] | Write-Host
    }
}

function Get-LauncherModeLabel {
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        [switch]$Local,
        [string]$ProjectsDir,
        [string]$LinuxHost,
        [string]$LinuxBase
    )

    if ($Local) {
        return "ローカル  $ProjectsDir\$Project"
    }

    return "SSH  $LinuxHost → $LinuxBase/$Project"
}

function Get-LauncherModeName {
    param([switch]$Local)

    if ($Local) {
        return 'local'
    }

    return 'ssh'
}

function New-LauncherDryRunMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [string]$LinuxHost = '',
        [string]$RemoteScript = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($RemoteScript)) {
        return @(
            "[DryRun] SSH接続先: $LinuxHost"
            $RemoteScript
        )
    }

    $joinedArgs = if ($Arguments.Count -gt 0) { " " + ($Arguments -join ' ') } else { '' }
    return @("[DryRun] cd $WorkingDirectory && $Command$joinedArgs")
}

function Confirm-LauncherStart {
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,
        [Parameter(Mandatory)]
        [string]$Project,
        [Parameter(Mandatory)]
        [string]$ModeLabel,
        [switch]$NonInteractive
    )

    if ($NonInteractive) {
        return $true
    }

    Write-Host ""
    Write-Host "=== 起動確認 ===" -ForegroundColor Yellow
    Write-Host "ツール   : $ToolName"
    Write-Host "プロジェクト: $Project"
    Write-Host "実行モード: $ModeLabel"
    $confirm = Read-Host "開始しますか？ (Y/n)"
    if ([string]::IsNullOrWhiteSpace($confirm)) {
        return $true
    }
    return ($confirm -notmatch '^(n|no)$')
}

function Set-LauncherEnvironment {
    param(
        [Parameter(Mandatory)]
        [object]$EnvMap
    )

    foreach ($p in $EnvMap.PSObject.Properties) {
        if ($null -ne $p.Value -and "$($p.Value)" -ne "") {
            [Environment]::SetEnvironmentVariable($p.Name, "$($p.Value)", "Process")
        }
    }
}

function ConvertTo-BashExports {
    param(
        [Parameter(Mandatory)]
        [object]$EnvMap
    )

    $lines = @()
    foreach ($p in $EnvMap.PSObject.Properties) {
        if ($null -ne $p.Value -and "$($p.Value)" -ne "") {
            $escaped = "$($p.Value)".Replace('"', '\"')
            $lines += "export $($p.Name)=""$escaped"""
        }
    }

    return ($lines -join "`n")
}

function Sync-ProjectTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return
    }

    if ($EnsureParentDirectory) {
        $parent = Split-Path -Parent $TargetPath
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    $needsCopy = $true
    if (Test-Path $TargetPath) {
        $src = Get-Content $TemplatePath -Raw -Encoding UTF8
        $dst = Get-Content $TargetPath -Raw -Encoding UTF8
        if ($src -eq $dst) {
            $needsCopy = $false
        }
    }

    if ($needsCopy) {
        Copy-Item $TemplatePath $TargetPath -Force
        Write-Host "[OK] $Label を配置/更新しました: $TargetPath" -ForegroundColor Green
    } else {
        Write-Host "[INFO] $Label は最新です: $TargetPath" -ForegroundColor Cyan
    }
}

function Sync-ProjectDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDirectory,
        [Parameter(Mandatory)]
        [string]$TargetDirectory,
        [Parameter(Mandatory)]
        [string]$Label
    )

    if (-not (Test-Path $SourceDirectory)) {
        return
    }

    if (-not (Test-Path $TargetDirectory)) {
        New-Item -ItemType Directory -Force -Path $TargetDirectory | Out-Null
    }

    Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $TargetDirectory -Recurse -Force
    Write-Host "[OK] $Label を配置/更新しました: $TargetDirectory" -ForegroundColor Green
}

function Sync-ProjectTemplateDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateDir,
        [Parameter(Mandatory)]
        [string]$TargetDir,
        [string]$Label = 'template directory'
    )

    if (-not (Test-Path $TemplateDir)) {
        return
    }

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    }

    $files = @(Get-ChildItem -Path $TemplateDir -Recurse -File | Sort-Object FullName)
    if ($files.Count -eq 0) {
        return
    }

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($TemplateDir.Length).TrimStart('\', '/')
        $targetPath = Join-Path $TargetDir $relativePath
        $parentDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
        }

        Sync-ProjectTemplate -TemplatePath $file.FullName -TargetPath $targetPath -Label "$Label/$relativePath"
    }
}

function Seed-ProjectTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return
    }

    if ($EnsureParentDirectory) {
        $parent = Split-Path -Parent $TargetPath
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    if (Test-Path $TargetPath) {
        Write-Host "[INFO] 既存の $Label を維持します: $TargetPath" -ForegroundColor Cyan
        return
    }

    Copy-Item $TemplatePath $TargetPath -Force
    Write-Host "[OK] $Label を初期配置しました: $TargetPath" -ForegroundColor Green
}

function Sync-LauncherClaudeGlobalConfig {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot,
        [Parameter(Mandatory)]
        [string]$ProjectDir
    )

    $claudeTemplatePath = Join-Path $StartupRoot 'Claude\templates\claude\CLAUDE.md'
    if (-not (Test-Path $claudeTemplatePath)) {
        $claudeTemplatePath = Join-Path $StartupRoot 'scripts\templates\CLAUDE.md'
    }

    Sync-ProjectTemplate `
        -TemplatePath $claudeTemplatePath `
        -TargetPath (Join-Path $ProjectDir 'CLAUDE.md') `
        -Label 'CLAUDE.md'

    Sync-ProjectTemplateDirectory `
        -TemplateDir (Join-Path $StartupRoot 'scripts\templates\claudeos') `
        -TargetDir (Join-Path $ProjectDir '.claude\claudeos') `
        -Label '.claude/claudeos'

    $settingsTemplatePath = Join-Path $StartupRoot 'scripts\templates\claude-settings.json'
    Seed-ProjectTemplate `
        -TemplatePath $settingsTemplatePath `
        -TargetPath (Join-Path $ProjectDir '.claude\settings.json') `
        -Label '.claude/settings.json' `
        -EnsureParentDirectory

    Seed-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\claude-mcp.json') `
        -TargetPath (Join-Path $ProjectDir '.mcp.json') `
        -Label '.mcp.json'

    Sync-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\claude-statusline.py') `
        -TargetPath (Join-Path $ProjectDir '.claude\statusline.py') `
        -Label '.claude/statusline.py' `
        -EnsureParentDirectory
}

function Sync-LauncherCodexGlobalConfig {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot,
        [Parameter(Mandatory)]
        [string]$ProjectDir
    )

    $agentsTemplatePath = Join-Path $StartupRoot 'Codex\AGENTS.md'
    if (-not (Test-Path $agentsTemplatePath)) {
        $agentsTemplatePath = Join-Path $StartupRoot 'scripts\templates\AGENTS.md'
    }

    Sync-ProjectTemplate `
        -TemplatePath $agentsTemplatePath `
        -TargetPath (Join-Path $ProjectDir 'AGENTS.md') `
        -Label 'AGENTS.md'

    Seed-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\codex-config.toml') `
        -TargetPath (Join-Path $ProjectDir '.codex\config.toml') `
        -Label '.codex/config.toml' `
        -EnsureParentDirectory
}

function Sync-LauncherCopilotGlobalConfig {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot,
        [Parameter(Mandatory)]
        [string]$ProjectDir
    )

    $copilotTemplatePath = Join-Path $StartupRoot 'CopilotCLI\AGENTS.md'
    if (-not (Test-Path $copilotTemplatePath)) {
        $copilotTemplatePath = Join-Path $StartupRoot 'scripts\templates\copilot-instructions.md'
    }

    Sync-ProjectTemplate `
        -TemplatePath $copilotTemplatePath `
        -TargetPath (Join-Path $ProjectDir '.github\copilot-instructions.md') `
        -Label 'copilot-instructions.md' `
        -EnsureParentDirectory

    Seed-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\copilot-mcp.json') `
        -TargetPath (Join-Path $ProjectDir '.github\mcp.json') `
        -Label '.github/mcp.json' `
        -EnsureParentDirectory
}

function Invoke-LauncherSshScript {
    param(
        [Parameter(Mandatory)]
        [string]$LinuxHost,
        [Parameter(Mandatory)]
        [string]$RunScript,
        [Parameter(Mandatory)]
        [string]$RemoteScriptName
    )

    # Bash on the remote side must receive LF-only content.
    $normalizedRunScript = (($RunScript -replace "`r`n", "`n") -replace "`r", "`n")

    if ($env:AI_STARTUP_SSH_CAPTURE_DIR) {
        $captureDir = $env:AI_STARTUP_SSH_CAPTURE_DIR
        if (-not (Test-Path $captureDir)) {
            New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
        }

        Set-Content -Path (Join-Path $captureDir "host.txt") -Value $LinuxHost -Encoding UTF8
        Set-Content -Path (Join-Path $captureDir "script-name.txt") -Value $RemoteScriptName -Encoding UTF8
        Set-Content -Path (Join-Path $captureDir "script.sh") -Value $normalizedRunScript -Encoding UTF8
        Write-Host "[INFO] SSH_CAPTURE $LinuxHost $RemoteScriptName" -ForegroundColor DarkGray
        return 0
    }

    $sshCommand = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { "ssh" }
    $connectTimeout = if ($env:AI_STARTUP_SSH_CONNECT_TIMEOUT) { $env:AI_STARTUP_SSH_CONNECT_TIMEOUT } else { "10" }

    # PowerShell の & 演算子は対話型プログラムのコンソール制御を妨げることがある。
    # Start-Process -NoNewWindow -Wait でコンソールを直接 SSH に渡す。
    Write-Host "[INFO] SSH 接続中: $LinuxHost ..." -ForegroundColor Cyan

    # Windows OpenSSH は ControlMaster のUnixソケットをサポートしないため無効化する。
    # Linuxでのみ ControlMaster=auto を使用して多重接続時の TCP 競合を回避する。
    $cmArgs = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        @("-o", "ControlMaster=no")
    } else {
        @("-o", "ControlMaster=auto",
          "-o", "ControlPath=/tmp/ssh_cm_%r@%h_%p",
          "-o", "ControlPersist=15")
    }
    $sshArgList = @("-tt",
        "-o", "ConnectTimeout=$connectTimeout",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ServerAliveInterval=60",
        "-o", "ServerAliveCountMax=3") +
        $cmArgs +
        @($LinuxHost, $normalizedRunScript)

    $process = Start-Process -FilePath $sshCommand -ArgumentList $sshArgList `
        -NoNewWindow -Wait -PassThru
    $exitCode = if ($null -ne $process.ExitCode) { $process.ExitCode } else { 0 }

    if ($exitCode -eq 255) {
        Write-Host "[ERR]  SSH 接続に失敗しました: $LinuxHost" -ForegroundColor Red
        Write-Host "[INFO] 確認事項:" -ForegroundColor Cyan
        Write-Host "  1. ssh $LinuxHost echo test  で手動接続を確認" -ForegroundColor White
        Write-Host "  2. ~/.ssh/config のホスト名・鍵設定を確認" -ForegroundColor White
        Write-Host "  3. ping $LinuxHost  でネットワーク疎通を確認" -ForegroundColor White
        Write-Host "  4. ssh -vvv $LinuxHost  で詳細ログを確認" -ForegroundColor White
    }

    return $exitCode
}

function Get-LauncherShell {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return "pwsh.exe"
    }

    return "powershell.exe"
}

function Write-LauncherExecutionResult {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Project,
        [Parameter(Mandatory)]
        [ValidateSet('claude', 'codex', 'copilot')]
        [string]$Tool,
        [Parameter(Mandatory)]
        [ValidateSet('local', 'ssh')]
        [string]$Mode,
        [Parameter(Mandatory)]
        [ValidateSet('success', 'failure', 'cancelled', 'unknown')]
        [string]$Result,
        [int]$ElapsedMs = 0
    )

    if (-not (Get-Command Update-RecentProjects -ErrorAction SilentlyContinue)) {
        return
    }

    if ($null -eq $Config.recentProjects -or -not $Config.recentProjects.enabled -or [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        return
    }

    Update-RecentProjects `
        -ProjectName $Project `
        -Tool $Tool `
        -Mode $Mode `
        -Result $Result `
        -ElapsedMs $ElapsedMs `
        -HistoryPath $Config.recentProjects.historyFile `
        -MaxHistory $Config.recentProjects.maxHistory
}

function Get-LauncherMetadataLogPath {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    if ($Config.logging -and -not [string]::IsNullOrWhiteSpace($Config.logging.logDir)) {
        return (Join-Path $Config.logging.logDir ("launch-metadata-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd')))
    }

    if ($Config.recentProjects -and -not [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        $historyDir = Split-Path -Parent ([Environment]::ExpandEnvironmentVariables($Config.recentProjects.historyFile))
        if (-not [string]::IsNullOrWhiteSpace($historyDir)) {
            return (Join-Path $historyDir ("launch-metadata-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd')))
        }
    }

    return $null
}

function Get-LauncherMetadataEntries {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$MaxCount = 20
    )

    $logPath = Get-LauncherMetadataLogPath -Config $Config
    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return @()
    }

    $logDir = Split-Path -Parent $logPath
    if ([string]::IsNullOrWhiteSpace($logDir) -or -not (Test-Path $logDir)) {
        return @()
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -Path $logDir -Filter 'launch-metadata-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    foreach ($file in $files) {
        foreach ($line in @(Get-Content -Path $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            try {
                $entries.Add(($line | ConvertFrom-Json))
            }
            catch {
                Write-Debug "Skipping malformed JSON history entry: $_"
            }
            if ($entries.Count -ge $MaxCount) {
                break
            }
        }
        if ($entries.Count -ge $MaxCount) {
            break
        }
    }

    return @(
        $entries |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First $MaxCount
    )
}

function Get-LauncherBacklogSummary {
    param(
        [string]$TasksPath = (Join-Path (Get-Location) 'TASKS.md')
    )

    if (-not (Test-Path $TasksPath)) {
        return [pscustomobject]@{
            Count = 0
            Priorities = @()
        }
    }

    $tasks = @(Get-Content -Path $TasksPath -Encoding UTF8 | Where-Object {
        $_ -match '^\d+\.\s' -and $_ -notmatch '\[DONE\]'
    })
    $priorities = @(
        $tasks |
            ForEach-Object {
                if ($_ -match '\[Priority:([^\]]+)\]') { $Matches[1] }
            } |
            Where-Object { $_ } |
            Group-Object |
            Sort-Object Name |
            ForEach-Object { "{0}:{1}" -f $_.Name, $_.Count }
    )

    return [pscustomobject]@{
        Count = $tasks.Count
        Priorities = $priorities
    }
}

function Write-LauncherMetadataLog {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [pscustomobject]$Entry
    )

    $logPath = Get-LauncherMetadataLogPath -Config $Config
    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return
    }

    $logDir = Split-Path -Parent $logPath
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $line = $Entry | ConvertTo-Json -Compress -Depth 6

    # 複数インスタンスが同時に書き込むと IOException が発生する。
    # 最大5回リトライして競合を回避する。
    $maxRetries = 5
    $retryDelay = 50  # ms
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            $stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::UTF8)
                $writer.WriteLine($line)
                $writer.Flush()
            }
            finally {
                $stream.Close()
            }
            break
        }
        catch [System.IO.IOException] {
            if ($i -lt ($maxRetries - 1)) {
                Start-Sleep -Milliseconds $retryDelay
            }
            # 最終リトライも失敗した場合はログ書き込みをスキップ（起動をブロックしない）
        }
    }
}

function New-LauncherExecutionContext {
    return [pscustomobject]@{
        StartTime = Get-Date
        Result = 'unknown'
        Project = $null
        Mode = $null
        Tool = $null
    }
}

function Complete-LauncherExecutionContext {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,
        [Parameter(Mandatory)]
        [object]$Config
    )

    if (-not $Context.Project -or -not $Context.Mode -or -not $Context.Tool) {
        return
    }

    $elapsedMs = [int][Math]::Max(0, ((Get-Date) - $Context.StartTime).TotalMilliseconds)
    Write-LauncherExecutionResult -Config $Config -Project $Context.Project -Tool $Context.Tool -Mode $Context.Mode -Result $Context.Result -ElapsedMs $elapsedMs
    Write-LauncherMetadataLog -Config $Config -Entry ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        project = $Context.Project
        tool = $Context.Tool
        mode = $Context.Mode
        result = $Context.Result
        elapsedMs = $elapsedMs
        host = if ($Config.linuxHost) { $Config.linuxHost } else { $env:COMPUTERNAME }
    })
}

function Get-LauncherRecentSummary {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    $total = @($Entries).Count
    if ($total -eq 0) {
        return [pscustomobject]@{
            Total = 0
            SuccessRate = 0
            AverageElapsedMs = 0
        }
    }

    $successCount = @($Entries | Where-Object { $_.result -eq 'success' }).Count
    $elapsedEntries = @($Entries | Where-Object { $null -ne $_.elapsedMs })
    $avgElapsed = if ($elapsedEntries.Count -gt 0) {
        [int](($elapsedEntries | Measure-Object -Property elapsedMs -Average).Average)
    }
    else {
        0
    }

    return [pscustomobject]@{
        Total = $total
        SuccessRate = [int][Math]::Round(($successCount / $total) * 100)
        AverageElapsedMs = $avgElapsed
    }
}

function Get-LauncherToolStatistics {
    param(
        [AllowEmptyCollection()]
        [object[]]$Entries = @(),
        [string[]]$Tools = @('claude', 'codex', 'copilot')
    )

    $stats = [System.Collections.Generic.List[object]]::new()
    foreach ($tool in $Tools) {
        $toolEntries = @($Entries | Where-Object { $_.tool -eq $tool })
        $summary = Get-LauncherRecentSummary -Entries $toolEntries
        $latest = @(
            $toolEntries |
                Sort-Object @{ Expression = {
                    if ($_.timestamp) {
                        try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                    }
                    else {
                        [datetimeoffset]::MinValue
                    }
                }; Descending = $true } |
                Select-Object -First 1
        )
        $stats.Add([pscustomobject]@{
            tool = $tool
            runs = $summary.Total
            successRate = $summary.SuccessRate
            averageElapsedMs = $summary.AverageElapsedMs
            lastResult = if ($latest.Count -gt 0 -and $latest[0].result) { $latest[0].result } else { 'none' }
            lastProject = if ($latest.Count -gt 0) { $latest[0].project } else { $null }
            lastTimestamp = if ($latest.Count -gt 0) { $latest[0].timestamp } else { $null }
        })
    }

    return @($stats)
}

function Get-LauncherAgentLaneEvents {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [AllowEmptyCollection()]
        [object[]]$MetadataEntries = @(),
        [AllowNull()]
        [object]$BacklogSummary = $null
    )

    $architectLatest = @(
        $MetadataEntries |
            Where-Object { $_.tool -in @('claude', 'codex') } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 1
    )
    $opsLatest = @(
        $MetadataEntries |
            Where-Object { $_.tool -eq 'copilot' } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 1
    )
    $overallSummary = Get-LauncherRecentSummary -Entries $MetadataEntries
    $priorityLabel = if ($BacklogSummary -and @($BacklogSummary.Priorities).Count -gt 0) { @($BacklogSummary.Priorities) -join ', ' } else { 'none' }

    $recentArchitectEvents = @(
        $MetadataEntries |
            Where-Object { $_.tool -in @('claude', 'codex') } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )
    $recentOpsEvents = @(
        $MetadataEntries |
            Where-Object { $_.tool -eq 'copilot' } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )
    $recentQaEvents = @(
        $MetadataEntries |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )

    $architectRecentLabel = @($recentArchitectEvents | ForEach-Object { '{0}:{1}' -f $_.project, $_.result }) -join ', '
    $qaRecentLabel = @($recentQaEvents | ForEach-Object { '{0}/{1}' -f $_.tool, $_.result }) -join ', '
    $opsRecentLabel = @($recentOpsEvents | ForEach-Object { '{0}:{1}' -f $_.project, $_.result }) -join ', '

    return @(
        [pscustomobject]@{
            lane = 'Architect'
            message = if ($architectLatest.Count -gt 0) {
                "latest=$($architectLatest[0].tool)/$($architectLatest[0].project) result=$($architectLatest[0].result) recent=$architectRecentLabel"
            }
            else {
                "defaultTool=$($Config.tools.defaultTool) recent=none"
            }
        },
        [pscustomobject]@{
            lane = 'QA'
            message = "runs=$($overallSummary.Total) success=$($overallSummary.SuccessRate)% avg=$($overallSummary.AverageElapsedMs)ms recent=$qaRecentLabel"
        },
        [pscustomobject]@{
            lane = 'Ops'
            message = if ($opsLatest.Count -gt 0) {
                "backlog=$($BacklogSummary.Count) priorities=$priorityLabel lastCopilot=$($opsLatest[0].result) recent=$opsRecentLabel"
            }
            else {
                "backlog=$($BacklogSummary.Count) priorities=$priorityLabel lastCopilot=none"
            }
        }
    )
}

function Get-LauncherTokenBudgetStatus {
    $pct = if ($env:AI_STARTUP_TOKEN_USAGE_PCT) { [int]$env:AI_STARTUP_TOKEN_USAGE_PCT } else { -1 }
    if ($pct -lt 0) {
        return [pscustomobject]@{ Percent = $null; Zone = 'Unknown'; Status = 'Token usage unavailable' }
    }
    if ($pct -lt 60) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Green'; Status = 'Normal development' }
    }
    if ($pct -lt 75) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Yellow'; Status = 'Reduced build activity' }
    }
    if ($pct -lt 90) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Orange'; Status = 'Monitor priority' }
    }

    return [pscustomobject]@{ Percent = $pct; Zone = 'Red'; Status = 'Development stop threshold' }
}

function Get-LauncherRecentEntries {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$MaxCount = 20
    )

    if (-not (Get-Command Get-RecentProjects -ErrorAction SilentlyContinue)) {
        return @()
    }
    if ($null -eq $Config.recentProjects -or -not $Config.recentProjects.enabled -or [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        return @()
    }

    return @(
        Get-RecentProjects -HistoryPath $Config.recentProjects.historyFile |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First $MaxCount
    )
}

function Get-LauncherRecentToolResults {
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,
        [string[]]$Tools = @('claude', 'codex', 'copilot')
    )

    $results = @()
    foreach ($tool in $Tools) {
        $latest = @($Entries | Where-Object { $_.tool -eq $tool } | Select-Object -First 1)
        if ($latest.Count -eq 0) {
            $results += [pscustomobject]@{
                tool = $tool
                result = 'none'
                elapsedMs = $null
                timestamp = $null
            }
            continue
        }

        $results += [pscustomobject]@{
            tool = $tool
            result = if ($latest[0].result) { $latest[0].result } else { 'unknown' }
            elapsedMs = $latest[0].elapsedMs
            timestamp = $latest[0].timestamp
        }
    }

    return @($results)
}

Export-ModuleMember -Function Get-StartupRoot
Export-ModuleMember -Function Get-StartupConfigPath
Export-ModuleMember -Function Import-LauncherConfig
Export-ModuleMember -Function Find-AvailableDriveLetter
Export-ModuleMember -Function Resolve-SshProjectsDir
Export-ModuleMember -Function Test-LauncherCommand
Export-ModuleMember -Function Assert-LauncherToolAvailable
Export-ModuleMember -Function Get-LauncherApiKeyValue
Export-ModuleMember -Function Show-LauncherApiKeyWarning
Export-ModuleMember -Function Resolve-LauncherMode
Export-ModuleMember -Function Resolve-LauncherProject
Export-ModuleMember -Function Show-LauncherProjectChoices
Export-ModuleMember -Function Get-LauncherModeLabel
Export-ModuleMember -Function Get-LauncherModeName
Export-ModuleMember -Function New-LauncherDryRunMessage
Export-ModuleMember -Function Confirm-LauncherStart
Export-ModuleMember -Function Set-LauncherEnvironment
Export-ModuleMember -Function ConvertTo-BashExports
Export-ModuleMember -Function Sync-ProjectTemplate
Export-ModuleMember -Function Sync-ProjectTemplateDirectory
Export-ModuleMember -Function Seed-ProjectTemplate
Export-ModuleMember -Function Sync-LauncherClaudeGlobalConfig
Export-ModuleMember -Function Sync-LauncherCodexGlobalConfig
Export-ModuleMember -Function Sync-LauncherCopilotGlobalConfig
Export-ModuleMember -Function New-RemoteTemplateDeployScript
Export-ModuleMember -Function Invoke-LauncherSshScript
Export-ModuleMember -Function Get-LauncherShell
Export-ModuleMember -Function Write-LauncherExecutionResult
Export-ModuleMember -Function Get-LauncherMetadataLogPath
Export-ModuleMember -Function Get-LauncherMetadataEntries
Export-ModuleMember -Function Write-LauncherMetadataLog
Export-ModuleMember -Function New-LauncherExecutionContext
Export-ModuleMember -Function Complete-LauncherExecutionContext
Export-ModuleMember -Function Get-LauncherRecentSummary
Export-ModuleMember -Function Get-LauncherRecentEntries
Export-ModuleMember -Function Get-LauncherRecentToolResults
Export-ModuleMember -Function Get-LauncherToolStatistics
Export-ModuleMember -Function Get-LauncherAgentLaneEvents
Export-ModuleMember -Function Get-LauncherTokenBudgetStatus
Export-ModuleMember -Function Get-LauncherBacklogSummary

# WinMM type definition is loaded lazily inside Invoke-LauncherNotificationSound

function Invoke-LauncherNotificationSound {
    <#
    .SYNOPSIS
        通知音を再生する。MP3/WAV に対応し、ウィンドウを開かずバックグラウンドで再生する。
    .PARAMETER Tool
        ツール名 (claude / codex / copilot)。config.json の notifications.sounds からパスを取得。
    .PARAMETER Config
        Import-LauncherConfig で読み込んだ設定オブジェクト。
    .PARAMETER Wait
        $true の場合、音の再生が完了するまでブロックする（終了通知向け）。
        $false の場合はノンブロッキング（起動通知向け）。デフォルト $false。
    #>
    param(
        [string]$Tool = 'claude',
        [object]$Config,
        [bool]$Wait = $false
    )

    if ($null -eq $Config) { return }
    # StrictMode 対応: PSObject.Properties 経由で安全にアクセス
    $notifProp = $Config.PSObject.Properties['notifications']
    if ($null -eq $notifProp) { return }
    $notif = $notifProp.Value
    if ($null -eq $notif -or -not $notif.soundEnabled) { return }

    # ツール別サウンドパスを取得。個別設定がなければ共通パスにフォールバック。
    $soundPath = $null
    if ($notif.sounds -and $notif.sounds.PSObject.Properties[$Tool]) {
        $soundPath = $notif.sounds.PSObject.Properties[$Tool].Value
    }
    if ([string]::IsNullOrWhiteSpace($soundPath)) { return }
    $soundPath = [Environment]::ExpandEnvironmentVariables($soundPath)
    if (-not (Test-Path $soundPath)) {
        Write-Warning "[Sound] ファイルが見つかりません: $soundPath"
        return
    }

    try {
        # WinMM MCI API 型定義（初回呼び出し時のみ）
        if (-not ([System.Management.Automation.PSTypeName]'LauncherWinMM').Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class LauncherWinMM {
    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    public static extern int mciSendString(string lpstrCommand, StringBuilder lpstrReturnString, int uReturnLength, IntPtr hwndCallback);
}
'@ -ErrorAction SilentlyContinue
        }
        if (-not ([System.Management.Automation.PSTypeName]'LauncherWinMM').Type) { return }

        $alias = "launcher_notif_$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
        $escaped = $soundPath -replace '"', ''

        [void][LauncherWinMM]::mciSendString("open `"$escaped`" alias $alias", $null, 0, [IntPtr]::Zero)
        if ($Wait) {
            [void][LauncherWinMM]::mciSendString("play $alias wait", $null, 0, [IntPtr]::Zero)
            [void][LauncherWinMM]::mciSendString("close $alias", $null, 0, [IntPtr]::Zero)
        } else {
            [void][LauncherWinMM]::mciSendString("play $alias", $null, 0, [IntPtr]::Zero)
            # ノンブロッキングの場合、8秒後にバックグラウンドでクローズ
            $localAlias = $alias
            $null = [System.Threading.Tasks.Task]::Run([Action]{
                Start-Sleep -Milliseconds 8000
                try { [void][LauncherWinMM]::mciSendString("close $localAlias", $null, 0, [IntPtr]::Zero) } catch { Write-Debug "Audio close failed for '$localAlias': $_" }
            })
        }
    }
    catch {
        # 音声再生の失敗はサイレントに無視（起動をブロックしない）
        Write-Debug "Audio playback failed (suppressed to avoid blocking startup): $_"
    }
}
Export-ModuleMember -Function Invoke-LauncherNotificationSound

function New-RemoteTemplateDeployScript {
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return ""
    }

    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
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

Export-ModuleMember -Function New-RemoteTemplateDeployScript
Export-ModuleMember -Function Sync-ProjectDirectory
