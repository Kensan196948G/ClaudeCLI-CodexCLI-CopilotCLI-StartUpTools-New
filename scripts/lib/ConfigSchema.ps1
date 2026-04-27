# ============================================================
# ConfigSchema.ps1 - 設定スキーマ定義・検証
# ============================================================

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

    # Normalize Hashtable inputs to PSCustomObject so PSObject.Properties works uniformly
    if ($Config -is [System.Collections.Hashtable]) {
        $Config = $Config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($field in $script:TemplateRequiredFields) {
        $value = $Config.PSObject.Properties[$field]?.Value
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: $field"
        }
    }

    $configTools = $Config.PSObject.Properties['tools']?.Value
    if ($null -eq $configTools) {
        Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: tools"
        return @($errors)
    }

    $defaultTool = $configTools.PSObject.Properties['defaultTool']?.Value
    if ([string]::IsNullOrWhiteSpace($defaultTool)) {
        Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: tools.defaultTool"
    }
    elseif ($defaultTool -notin $script:AllowedDefaultTools) {
        Add-SchemaError -Errors $errors -Message "tools.defaultTool は claude/codex/copilot のいずれかである必要があります"
    }

    foreach ($pathField in @('projectsDir', 'sshProjectsDir', 'projectsDirUnc', 'linuxHost', 'linuxBase')) {
        $value = $Config.PSObject.Properties[$pathField]?.Value
        if ($null -ne $value -and $value -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "$pathField は文字列である必要があります"
        }
    }

    $localExcludes = $Config.PSObject.Properties['localExcludes']?.Value
    if ($null -ne $localExcludes -and $localExcludes -isnot [System.Array]) {
        Add-SchemaError -Errors $errors -Message "localExcludes は配列である必要があります"
    }

    foreach ($toolName in $script:TemplateToolRequiredFields.Keys) {
        $toolConfig = $configTools.PSObject.Properties[$toolName]?.Value
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

        $tcEnabled        = $toolConfig.PSObject.Properties['enabled']?.Value
        $tcCommand        = $toolConfig.PSObject.Properties['command']?.Value
        $tcArgs           = $toolConfig.PSObject.Properties['args']?.Value
        $tcInstallCommand = $toolConfig.PSObject.Properties['installCommand']?.Value
        $tcEnv            = $toolConfig.PSObject.Properties['env']?.Value
        $tcApiKeyEnvVar   = $toolConfig.PSObject.Properties['apiKeyEnvVar']?.Value

        if ($tcEnabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.enabled は boolean である必要があります"
        }
        if ($tcCommand -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.command は文字列である必要があります"
        }
        if ($tcArgs -isnot [System.Array]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.args は配列である必要があります"
        }
        if ($tcInstallCommand -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.installCommand は文字列である必要があります"
        }
        if ($tcEnv -isnot [pscustomobject] -and $tcEnv -isnot [System.Collections.IDictionary]) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.env はオブジェクトである必要があります"
        }
        if (($toolName -ne 'copilot') -and ($tcApiKeyEnvVar -isnot [string])) {
            Add-SchemaError -Errors $errors -Message "tools.$toolName.apiKeyEnvVar は文字列である必要があります"
        }
    }

    $rp = $Config.PSObject.Properties['recentProjects']?.Value
    if ($null -ne $rp) {
        $rpEnabled     = $rp.PSObject.Properties['enabled']?.Value
        $rpMaxHistory  = $rp.PSObject.Properties['maxHistory']?.Value
        $rpHistoryFile = $rp.PSObject.Properties['historyFile']?.Value
        if ($rpEnabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "recentProjects.enabled は boolean である必要があります"
        }
        if (-not (Test-IntegerValueInRange -Value $rpMaxHistory -Minimum 1)) {
            Add-SchemaError -Errors $errors -Message "recentProjects.maxHistory は 1 以上の整数である必要があります"
        }
        if ($rpHistoryFile -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "recentProjects.historyFile は文字列である必要があります"
        }
    }

    $logging = $Config.PSObject.Properties['logging']?.Value
    if ($null -ne $logging) {
        $logEnabled        = $logging.PSObject.Properties['enabled']?.Value
        $logDir            = $logging.PSObject.Properties['logDir']?.Value
        $logPrefix         = $logging.PSObject.Properties['logPrefix']?.Value
        $logSuccessKeep    = $logging.PSObject.Properties['successKeepDays']?.Value
        $logFailureKeep    = $logging.PSObject.Properties['failureKeepDays']?.Value
        if ($logEnabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "logging.enabled は boolean である必要があります"
        }
        if ($null -ne $logDir -and $logDir -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "logging.logDir は文字列である必要があります"
        }
        if ($null -ne $logPrefix -and $logPrefix -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "logging.logPrefix は文字列である必要があります"
        }
        if ($null -ne $logSuccessKeep -and -not (Test-IntegerValueInRange -Value $logSuccessKeep -Minimum 1 -Maximum 3650)) {
            Add-SchemaError -Errors $errors -Message "logging.successKeepDays は 1 から 3650 の整数である必要があります"
        }
        if ($null -ne $logFailureKeep -and -not (Test-IntegerValueInRange -Value $logFailureKeep -Minimum 1 -Maximum 3650)) {
            Add-SchemaError -Errors $errors -Message "logging.failureKeepDays は 1 から 3650 の整数である必要があります"
        }
    }

    $ssh = $Config.PSObject.Properties['ssh']?.Value
    if ($null -ne $ssh) {
        $sshAutoCleanup = $ssh.PSObject.Properties['autoCleanup']?.Value
        $sshOptions     = $ssh.PSObject.Properties['options']?.Value
        if ($null -ne $sshAutoCleanup -and $sshAutoCleanup -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "ssh.autoCleanup は boolean である必要があります"
        }
        if ($null -ne $sshOptions -and $sshOptions -isnot [System.Array]) {
            Add-SchemaError -Errors $errors -Message "ssh.options は配列である必要があります"
        }
    }

    $bc = $Config.PSObject.Properties['backupConfig']?.Value
    if ($null -ne $bc) {
        $bcEnabled       = $bc.PSObject.Properties['enabled']?.Value
        $bcBackupDir     = $bc.PSObject.Properties['backupDir']?.Value
        $bcMaxBackups    = $bc.PSObject.Properties['maxBackups']?.Value
        $bcMaskSensitive = $bc.PSObject.Properties['maskSensitive']?.Value
        $bcSensitiveKeys = $bc.PSObject.Properties['sensitiveKeys']?.Value
        if ($null -ne $bcEnabled -and $bcEnabled -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "backupConfig.enabled は boolean である必要があります"
        }
        if ($null -ne $bcBackupDir -and $bcBackupDir -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "backupConfig.backupDir は文字列である必要があります"
        }
        if ($null -ne $bcMaxBackups -and -not (Test-IntegerValueInRange -Value $bcMaxBackups -Minimum 1 -Maximum 1000)) {
            Add-SchemaError -Errors $errors -Message "backupConfig.maxBackups は 1 から 1000 の整数である必要があります"
        }
        if ($null -ne $bcMaskSensitive -and $bcMaskSensitive -isnot [bool]) {
            Add-SchemaError -Errors $errors -Message "backupConfig.maskSensitive は boolean である必要があります"
        }
        if ($null -ne $bcSensitiveKeys -and $bcSensitiveKeys -isnot [System.Array]) {
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

    $errors = @(Test-StartupConfigSchema -Config $config)
    if ($errors.Count -gt 0) {
        throw ($errors -join "`n")
    }

    return $true
}
