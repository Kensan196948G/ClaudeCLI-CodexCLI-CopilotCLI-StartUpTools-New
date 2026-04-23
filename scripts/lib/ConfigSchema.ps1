# ============================================================
# ConfigSchema.ps1 - 設定スキーマ定義・検証
# ============================================================
Set-StrictMode -Version Latest

# Required field definitions (script scope — shared with dot-sourced siblings)
$script:RequiredFields = @('version', 'linuxHost', 'tools')
$script:TemplateRequiredFields = @('version', 'projectsDir', 'sshProjectsDir', 'projectsDirUnc', 'linuxHost', 'linuxBase', 'tools')
$script:TemplateToolRequiredFields = @{
    claude  = @('enabled', 'command', 'args', 'installCommand', 'env', 'apiKeyEnvVar')
    codex   = @('enabled', 'command', 'args', 'installCommand', 'env', 'apiKeyEnvVar')
    copilot = @('enabled', 'command', 'args', 'installCommand', 'env')
}
$script:AllowedDefaultTools = @('claude', 'codex', 'copilot')
$script:AllowedLauncherModes = @('local', 'ssh')

function Test-IntegerValueInRange {
    param(
        [object]$Value,
        [int]$Minimum,
        [int]$Maximum = [int]::MaxValue
    )

    if ($null -eq $Value) {
        return $false
    }

    try {
        $number = [int64]$Value
    }
    catch {
        return $false
    }

    return ($number -ge $Minimum -and $number -le $Maximum)
}

function Add-SchemaError {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors,
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    $Errors.Add($Message)
}

<#
.SYNOPSIS
    Validates a startup configuration object against the required schema and returns a list of errors.
#>
function Test-StartupConfigSchema {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($field in $script:TemplateRequiredFields) {
        $value = $Config.PSObject.Properties[$field]?.Value
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: $field"
        }
    }

    if ($null -eq $Config.tools) {
        Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: tools"
        return @($errors)
    }

    if ([string]::IsNullOrWhiteSpace($Config.tools.defaultTool)) {
        Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: tools.defaultTool"
    }
    elseif ($Config.tools.defaultTool -notin $script:AllowedDefaultTools) {
        Add-SchemaError -Errors $errors -Message "tools.defaultTool は claude/codex/copilot のいずれかである必要があります"
    }

    foreach ($pathField in @('projectsDir', 'sshProjectsDir', 'projectsDirUnc', 'linuxHost', 'linuxBase')) {
        $value = $Config.PSObject.Properties[$pathField]?.Value
        if ($null -ne $value -and $value -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "$pathField は文字列である必要があります"
        }
    }

    if ($null -ne $Config.localExcludes -and $Config.localExcludes -isnot [System.Array]) {
        Add-SchemaError -Errors $errors -Message "localExcludes は配列である必要があります"
    }

    foreach ($toolName in $script:TemplateToolRequiredFields.Keys) {
        $toolConfig = $Config.tools.PSObject.Properties[$toolName]?.Value
        if ($null -eq $toolConfig) {
            Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: tools.$toolName"
            continue
        }

        foreach ($field in $script:TemplateToolRequiredFields[$toolName]) {
            $value = $toolConfig.PSObject.Properties[$field]?.Value
            if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
                Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: tools.$toolName.$field"
            }
        }

        if ($toolConfig.enabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.enabled は boolean である必要があります"
        }
        if ($toolConfig.command -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.command は文字列である必要があります"
        }
        if ($toolConfig.args -isnot [System.Array]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.args は配列である必要があります"
        }
        if ($toolConfig.installCommand -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.installCommand は文字列である必要があります"
        }
        if ($null -eq $toolConfig.env -or $toolConfig.env -is [string] -or $toolConfig.env -is [System.Array]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.env はオブジェクトである必要があります"
        }
        if (($toolName -ne 'copilot') -and ($toolConfig.apiKeyEnvVar -isnot [string])) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.apiKeyEnvVar は文字列である必要があります"
        }
    }

    if ($null -ne $Config.recentProjects) {
        if ($Config.recentProjects.enabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "recentProjects.enabled は boolean である必要があります"
        }
        if (-not (Test-IntegerValueInRange -Value $Config.recentProjects.maxHistory -Minimum 1)) {
            Add-SchemaError -Errors $errors -Message "recentProjects.maxHistory は 1 以上の整数である必要があります"
        }
        if ($Config.recentProjects.historyFile -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "recentProjects.historyFile は文字列である必要があります"
        }
    }

    if ($null -ne $Config.logging) {
        if ($Config.logging.enabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "logging.enabled は boolean である必要があります"
        }
        if ($null -ne $Config.logging.logDir -and $Config.logging.logDir -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "logging.logDir は文字列である必要があります"
        }
        if ($null -ne $Config.logging.logPrefix -and $Config.logging.logPrefix -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "logging.logPrefix は文字列である必要があります"
        }
        if ($null -ne $Config.logging.successKeepDays -and -not (Test-IntegerValueInRange -Value $Config.logging.successKeepDays -Minimum 1 -Maximum 3650)) {
            Add-SchemaError -Errors $errors -Message "logging.successKeepDays は 1 から 3650 の整数である必要があります"
        }
        if ($null -ne $Config.logging.failureKeepDays -and -not (Test-IntegerValueInRange -Value $Config.logging.failureKeepDays -Minimum 1 -Maximum 3650)) {
            Add-SchemaError -Errors $errors -Message "logging.failureKeepDays は 1 から 3650 の整数である必要があります"
        }
    }

    if ($null -ne $Config.ssh) {
        if ($null -ne $Config.ssh.autoCleanup -and $Config.ssh.autoCleanup -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "ssh.autoCleanup は boolean である必要があります"
        }
        if ($null -ne $Config.ssh.options -and $Config.ssh.options -isnot [System.Array]) {
            Add-SchemaError -Errors $errors -Message "ssh.options は配列である必要があります"
        }
    }

    if ($null -ne $Config.backupConfig) {
        if ($null -ne $Config.backupConfig.enabled -and $Config.backupConfig.enabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "backupConfig.enabled は boolean である必要があります"
        }
        if ($null -ne $Config.backupConfig.backupDir -and $Config.backupConfig.backupDir -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "backupConfig.backupDir は文字列である必要があります"
        }
        if ($null -ne $Config.backupConfig.maxBackups -and -not (Test-IntegerValueInRange -Value $Config.backupConfig.maxBackups -Minimum 1 -Maximum 1000)) {
            Add-SchemaError -Errors $errors -Message "backupConfig.maxBackups は 1 から 1000 の整数である必要があります"
        }
        if ($null -ne $Config.backupConfig.maskSensitive -and $Config.backupConfig.maskSensitive -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "backupConfig.maskSensitive は boolean である必要があります"
        }
        if ($null -ne $Config.backupConfig.sensitiveKeys -and $Config.backupConfig.sensitiveKeys -isnot [System.Array]) {
            Add-SchemaError -Errors $errors -Message "backupConfig.sensitiveKeys は配列である必要があります"
        }
    }

    return @($errors)
}

<#
.SYNOPSIS
    Loads and validates a config.json file, throwing on any schema errors.
#>
function Assert-StartupConfigSchema {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }

    try {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $config = $content | ConvertFrom-Json
    }
    catch {
        throw "config.jsonのJSONパースに失敗しました: $_"
    }

    $errors = Test-StartupConfigSchema -Config $config
    if ($errors.Count -gt 0) {
        throw ($errors -join "`n")
    }

    return $true
}
