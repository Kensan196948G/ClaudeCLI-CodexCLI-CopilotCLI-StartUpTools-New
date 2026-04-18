<#
.SYNOPSIS
    Core launcher utility functions — config, mode, project selection, SSH, environment.
    Template sync functions are in TemplateSyncManager.psm1.
    Session logging functions are in SessionLogger.psm1.
    Both are dot-sourced below for full backward compatibility with all callers.
#>

<#
.SYNOPSIS
    Returns the repository root directory by walking two levels up from the script root path.
#>
function Get-StartupRoot {
    param(
        [Parameter(Mandatory)]
        [string]$PSScriptRootPath
    )

    return (Split-Path -Parent (Split-Path -Parent $PSScriptRootPath))
}

<#
.SYNOPSIS
    Returns the config.json path, honoring the AI_STARTUP_CONFIG_PATH environment variable override.
#>
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

<#
.SYNOPSIS
    Reads and parses the launcher config.json file from the specified path.
#>
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

<#
.SYNOPSIS
    Finds and returns the first available Windows drive letter not currently in use.
#>
function Find-AvailableDriveLetter {
    [CmdletBinding()]
    [OutputType([System.String])]
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

<#
.SYNOPSIS
    Resolves the SSH projects directory path, auto-mapping a UNC drive when sshProjectsDir is 'auto'.
#>
function Resolve-SshProjectsDir {
    [CmdletBinding()]
    [OutputType([System.String])]
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

<#
.SYNOPSIS
    Returns true if the specified command is available in the current environment.
#>
function Test-LauncherCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Checks that a required CLI tool is installed and optionally prompts to install it if missing.
#>
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

    Write-Host "[WARN] $ToolLabel ($Command) コマンドが見つかりません。" -ForegroundColor Yellow
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

<#
.SYNOPSIS
    Retrieves an API key value from environment variables or the EnvMap config object.
#>
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

<#
.SYNOPSIS
    Displays a warning and setup hints when a required API key environment variable is not set.
#>
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

<#
.SYNOPSIS
    Determines whether to run in local or SSH mode, prompting the user if linuxHost is unconfigured.
#>
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
            Write-Host "config.json を開いてください: $ConfigPath" -ForegroundColor Yellow
            throw "USER_CANCELLED"
        }
        default {
            throw "USER_CANCELLED"
        }
    }
}

<#
.SYNOPSIS
    Resolves the target project name, prompting the user with a directory listing when not specified.
#>
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

    Show-LauncherProjectChoice -Projects $dirs.Name -Local:$Local -LinuxHost $LinuxHost

    $num = Read-Host "番号を入力してください"
    $numInt = $num -as [int]
    if (-not $numInt -or $numInt -lt 1 -or $numInt -gt $dirs.Count) {
        throw "USER_CANCELLED"
    }

    return $dirs[$numInt - 1].Name
}

<#
.SYNOPSIS
    Displays a numbered list of projects for the user to select from.
#>
function Show-LauncherProjectChoice {
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

<#
.SYNOPSIS
    Returns a human-readable label describing the current execution mode (local or SSH) and project path.
#>
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

<#
.SYNOPSIS
    Returns 'local' or 'ssh' as the canonical mode name string.
#>
function Get-LauncherModeName {
    param([switch]$Local)

    if ($Local) {
        return 'local'
    }

    return 'ssh'
}

<#
.SYNOPSIS
    Returns a dry-run message string describing the command that would be executed.
#>
function New-LauncherDryRunMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function returns in-memory object; no persistent system state is modified')]
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

<#
.SYNOPSIS
    Prompts the user to confirm the launcher start unless NonInteractive mode is set.
#>
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

<#
.SYNOPSIS
    Sets process-scoped environment variables from the provided EnvMap object.
#>
function Set-LauncherEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal autonomous CLI function; ShouldProcess disrupts unattended operation')]
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

<#
.SYNOPSIS
    Converts an EnvMap object into a newline-separated string of Bash export statements.
#>
function ConvertTo-BashExport {
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

<#
.SYNOPSIS
    Executes a shell script on a remote Linux host via SSH and returns the exit code.
#>
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

<#
.SYNOPSIS
    Returns the PowerShell executable name, preferring pwsh over powershell.exe when available.
#>
function Get-LauncherShell {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return "pwsh.exe"
    }

    return "powershell.exe"
}

# Dot-source submodules — functions land in this module's scope
. (Join-Path $PSScriptRoot 'TemplateSyncManager.ps1')
. (Join-Path $PSScriptRoot 'SessionLogger.ps1')

# Export all public functions (core + TemplateSyncManager + SessionLogger)
Export-ModuleMember -Function '*'
