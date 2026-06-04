<#
.SYNOPSIS
    Core launcher utility functions — config, mode, project selection, environment.
    Template sync functions are in TemplateSyncManager.psm1.
    Session logging functions are in SessionLogger.psm1.
    Both are dot-sourced below for full backward compatibility with all callers.
#>
Set-StrictMode -Version Latest

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
    Determines whether to run in local mode. Always returns $true (Phase 3: SSH removed).
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

    return $true
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
        [switch]$NonInteractive
    )

    if ($Project) {
        return $Project
    }

    # Phase 4: ローカル一本化完了。projectsDir のみ使用。
    $localDir = $Config.projectsDir
    $projectsRoot = $localDir
    $dirs = $null

    if (Test-Path $projectsRoot) {
        $dirs = Get-ChildItem -Path $projectsRoot -Directory | Sort-Object Name
        if ($Config.localExcludes) {
            $dirs = $dirs | Where-Object { $_.Name -notin $Config.localExcludes }
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

    Show-LauncherProjectChoice -Projects $dirs.Name

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
        [string[]]$Projects
    )

    Write-Host ""
    Write-Host "=== プロジェクト選択 ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Projects.Count; $i++) {
        "{0,2}: {1}" -f ($i + 1), $Projects[$i] | Write-Host
    }
}

<#
.SYNOPSIS
    Returns a human-readable label describing the local execution mode and project path.
#>
function Get-LauncherModeLabel {
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        [switch]$Local,
        [string]$ProjectsDir
    )

    return "ローカル  $ProjectsDir\$Project"
}

<#
.SYNOPSIS
    Returns 'local' as the canonical mode name string (Phase 3: SSH removed).
#>
function Get-LauncherModeName {
    param([switch]$Local)

    return 'local'
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
        [string]$WorkingDirectory = ''
    )

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
