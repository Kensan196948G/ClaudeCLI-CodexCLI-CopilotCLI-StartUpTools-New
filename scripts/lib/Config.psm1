# ============================================================
# Config.psm1 - 設定管理モジュール
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.0.0
# ============================================================

# 必須フィールドの定義
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

function Test-StartupConfigSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($field in $script:TemplateRequiredFields) {
        $value = $Config.$field
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
        $value = $Config.$pathField
        if ($null -ne $value -and $value -isnot [string]) {
            Add-SchemaError -Errors $errors -Message "$pathField は文字列である必要があります"
        }
    }

    if ($null -ne $Config.localExcludes -and $Config.localExcludes -isnot [System.Array]) {
        Add-SchemaError -Errors $errors -Message "localExcludes は配列である必要があります"
    }

    foreach ($toolName in $script:TemplateToolRequiredFields.Keys) {
        $toolConfig = $Config.tools.$toolName
        if ($null -eq $toolConfig) {
            Add-SchemaError -Errors $errors -Message "必須フィールドが不足しています: tools.$toolName"
            continue
        }

        foreach ($field in $script:TemplateToolRequiredFields[$toolName]) {
            $value = $toolConfig.$field
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

function Assert-StartupConfigSchema {
    [CmdletBinding()]
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

<#
.SYNOPSIS
    config.jsonを読み込んで検証

.DESCRIPTION
    指定されたパスからconfig.jsonを読み込み、必須フィールドの存在確認と
    ツール設定の検証を行う。検証失敗時は例外をスローする。

.PARAMETER ConfigPath
    config.jsonのファイルパス

.EXAMPLE
    $config = Import-StartupConfig -ConfigPath ".\config\config.json"
#>
function Import-StartupConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )

    # ファイル存在確認
    if (-not (Test-Path $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }

    # JSON読み込み
    try {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $config = $content | ConvertFrom-Json
        Write-Host "[INFO]  設定ファイル読み込み: $ConfigPath" -ForegroundColor Cyan
    }
    catch {
        throw "config.jsonのJSONパースに失敗しました: $_"
    }

    # 必須フィールド検証
    foreach ($field in $script:RequiredFields) {
        $value = $config.$field
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            throw "config.jsonに必須フィールドがありません: '$field'"
        }
    }
    Write-Host "[ OK ]  必須フィールド検証OK" -ForegroundColor Green

    # プレースホルダーの検出
    if ($config.linuxHost -eq "<your-linux-host>") {
        Write-Warning "config.json の linuxHost がプレースホルダーのままです。実際のホスト名に変更してください。"
    }

    # ツール設定の検証
    $validTools = @('claude', 'codex', 'copilot')
    foreach ($toolName in $validTools) {
        $toolConf = $config.tools.$toolName
        if ($null -ne $toolConf) {
            if ($null -eq $toolConf.enabled) {
                Write-Warning "tools.$toolName.enabled が未設定です"
            }
            if ($null -eq $toolConf.command) {
                Write-Warning "tools.$toolName.command が未設定です"
            }
        }
    }
    Write-Host "[ OK ]  ツール設定検証OK" -ForegroundColor Green

    return $config
}

# 後方互換性のためのラッパー関数
function Import-DevToolsConfig {
    param([string]$ConfigPath)
    Import-StartupConfig -ConfigPath $ConfigPath
}

<#
.SYNOPSIS
    タイムスタンプ付きバックアップを作成

.DESCRIPTION
    設定ファイルをタイムスタンプ付きでバックアップする。
    機密情報のマスキングと最大バックアップ数の管理を行う。

.PARAMETER ConfigPath
    バックアップ元のファイルパス

.PARAMETER BackupDir
    バックアップ先ディレクトリ

.PARAMETER MaxBackups
    保持する最大バックアップ数（デフォルト: 10）

.PARAMETER MaskSensitive
    機密情報をマスクするか（デフォルト: $true）

.PARAMETER SensitiveKeys
    マスクするキーのリスト（例: @('tools.codex.env.OPENAI_API_KEY')）

.EXAMPLE
    Backup-ConfigFile -ConfigPath ".\config\config.json" -BackupDir ".\config\backups"
#>
function Backup-ConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath,

        [Parameter(Mandatory=$true)]
        [string]$BackupDir,

        [Parameter(Mandatory=$false)]
        [int]$MaxBackups = 10,

        [Parameter(Mandatory=$false)]
        [bool]$MaskSensitive = $true,

        [Parameter(Mandatory=$false)]
        [string[]]$SensitiveKeys = @()
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "バックアップ元ファイルが見つかりません: $ConfigPath"
        return
    }

    # バックアップディレクトリ作成
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    # タイムスタンプ付きファイル名
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
    $ext = [System.IO.Path]::GetExtension($ConfigPath)
    $backupFile = Join-Path $BackupDir "${baseName}_${timestamp}${ext}"

    try {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8

        # 機密情報のマスキング
        if ($MaskSensitive -and $SensitiveKeys.Count -gt 0) {
            try {
                $json = $content | ConvertFrom-Json
                foreach ($keyPath in $SensitiveKeys) {
                    $parts = $keyPath -split '\.'
                    $obj = $json
                    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                        if ($null -ne $obj.($parts[$i])) {
                            $obj = $obj.($parts[$i])
                        }
                    }
                    $lastKey = $parts[-1]
                    if ($null -ne $obj -and $null -ne $obj.$lastKey -and $obj.$lastKey -ne "") {
                        $obj.$lastKey = "***MASKED***"
                    }
                }
                $content = $json | ConvertTo-Json -Depth 10
            }
            catch {
                Write-Warning "機密情報マスキング中にエラー（マスクなしでバックアップ）: $_"
            }
        }

        Set-Content -Path $backupFile -Value $content -Encoding UTF8
        Write-Host "[INFO]  設定バックアップ作成: $backupFile" -ForegroundColor Cyan

        # 古いバックアップを削除（MaxBackupsを超えた分）
        $pattern = "${baseName}_*${ext}"
        $backups = Get-ChildItem -Path $BackupDir -Filter $pattern | Sort-Object LastWriteTime -Descending
        if ($backups.Count -gt $MaxBackups) {
            $toDelete = $backups | Select-Object -Skip $MaxBackups
            foreach ($old in $toDelete) {
                Remove-Item -Path $old.FullName -Force
                Write-Host "[INFO]  古いバックアップ削除: $($old.Name)" -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Warning "バックアップ作成中にエラーが発生しました: $_"
    }
}

<#
.SYNOPSIS
    最近使用プロジェクト履歴を取得

.PARAMETER HistoryPath
    履歴ファイルのパス（%USERPROFILE% などの環境変数を展開する）

.EXAMPLE
    $recent = Get-RecentProject -HistoryPath "%USERPROFILE%\.ai-startup\recent-projects.json"
#>
function Get-RecentProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath
    )

    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($HistoryPath)

    if (-not (Test-Path $expandedPath)) {
        return @()
    }

    try {
        $content = Get-Content -Path $expandedPath -Raw -Encoding UTF8
        $data = $content | ConvertFrom-Json

        if ($null -eq $data -or $null -eq $data.projects) {
            return @()
        }

        $normalized = @()
        foreach ($entry in @($data.projects)) {
            if ($entry -is [string]) {
                $normalized += [pscustomobject]@{
                    project = $entry
                    tool = $null
                    mode = $null
                    timestamp = $null
                    result = $null
                    elapsedMs = $null
                }
                continue
            }

            if ($entry.PSObject.Properties.Name -contains 'project') {
                $tool = if ($entry.PSObject.Properties.Name -contains 'tool') { "$($entry.tool)" } else { $null }
                $mode = if ($entry.PSObject.Properties.Name -contains 'mode') { "$($entry.mode)" } else { $null }
                $timestamp = if ($entry.PSObject.Properties.Name -contains 'timestamp') { "$($entry.timestamp)" } else { $null }
                $normalized += [pscustomobject]@{
                    project = "$($entry.project)"
                    tool = if ([string]::IsNullOrWhiteSpace($tool)) { $null } else { $tool }
                    mode = if ([string]::IsNullOrWhiteSpace($mode)) { $null } else { $mode }
                    timestamp = if ([string]::IsNullOrWhiteSpace($timestamp)) { $null } else { $timestamp }
                    result = if ($entry.PSObject.Properties.Name -contains 'result' -and -not [string]::IsNullOrWhiteSpace("$($entry.result)")) { "$($entry.result)" } else { $null }
                    elapsedMs = if ($entry.PSObject.Properties.Name -contains 'elapsedMs' -and $null -ne $entry.elapsedMs) { [int]$entry.elapsedMs } else { $null }
                }
            }
        }

        return @($normalized)
    }
    catch {
        Write-Warning "最近使用プロジェクト履歴の読み込みに失敗しました: $_"
        return @()
    }
}

<#
.SYNOPSIS
    最近使用プロジェクト履歴を更新

.PARAMETER ProjectName
    追加するプロジェクト名

.PARAMETER HistoryPath
    履歴ファイルのパス

.PARAMETER MaxHistory
    保持する最大履歴数（デフォルト: 10）

.EXAMPLE
    Update-RecentProject -ProjectName "MyProject" -HistoryPath "%USERPROFILE%\.ai-startup\recent-projects.json"
#>
function Update-RecentProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectName,

        [Parameter(Mandatory=$false)]
        [ValidateSet('claude', 'codex', 'copilot', '')]
        [string]$Tool = '',

        [Parameter(Mandatory=$false)]
        [ValidateSet('local', 'ssh', '')]
        [string]$Mode = '',

        [Parameter(Mandatory=$false)]
        [ValidateSet('success', 'failure', 'cancelled', 'unknown', '')]
        [string]$Result = '',

        [Parameter(Mandatory=$false)]
        [Nullable[int]]$ElapsedMs = $null,

        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,

        [Parameter(Mandatory=$false)]
        [int]$MaxHistory = 10
    )

    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($HistoryPath)

    $dir = Split-Path $expandedPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $projects = [System.Collections.Generic.List[object]]::new()
    $existing = Get-RecentProject -HistoryPath $HistoryPath
    foreach ($p in $existing) {
        $sameProject = ($p.project -eq $ProjectName)
        $sameTool = (([string]::IsNullOrWhiteSpace($Tool) -and [string]::IsNullOrWhiteSpace($p.tool)) -or ($p.tool -eq $Tool))
        $sameMode = (([string]::IsNullOrWhiteSpace($Mode) -and [string]::IsNullOrWhiteSpace($p.mode)) -or ($p.mode -eq $Mode))
        if (-not ($sameProject -and $sameTool -and $sameMode)) {
            $projects.Add($p)
        }
    }

    $projects.Insert(0, [pscustomobject]@{
        project = $ProjectName
        tool = if ([string]::IsNullOrWhiteSpace($Tool)) { $null } else { $Tool }
        mode = if ([string]::IsNullOrWhiteSpace($Mode)) { $null } else { $Mode }
        timestamp = (Get-Date).ToString('o')
        result = if ([string]::IsNullOrWhiteSpace($Result)) { $null } else { $Result }
        elapsedMs = if ($PSBoundParameters.ContainsKey('ElapsedMs') -and $null -ne $ElapsedMs) { [int]$ElapsedMs } else { $null }
    })

    if ($projects.Count -gt $MaxHistory) {
        $projects = [System.Collections.Generic.List[object]]($projects | Select-Object -First $MaxHistory)
    }

    try {
        $data = @{ projects = @($projects) }
        $json = $data | ConvertTo-Json -Depth 3
        Set-Content -Path $expandedPath -Value $json -Encoding UTF8
        Write-Host "[INFO]  最近使用プロジェクト更新: $ProjectName" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "最近使用プロジェクト履歴の保存に失敗しました: $_"
    }
}

function Test-RecentProjectsEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    return ($null -ne $Config.recentProjects -and $Config.recentProjects.enabled -and -not [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile))
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Import-StartupConfig',
    'Import-DevToolsConfig',
    'Test-StartupConfigSchema',
    'Assert-StartupConfigSchema',
    'Backup-ConfigFile',
    'Get-RecentProject',
    'Update-RecentProject',
    'Test-RecentProjectsEnabled'
)
