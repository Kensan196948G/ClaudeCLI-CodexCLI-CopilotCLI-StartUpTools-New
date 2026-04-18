# ============================================================
# ConfigLoader.ps1 - 設定ファイル読み込み・バックアップ
# Depends on: ConfigSchema.ps1 (dot-sourced first in Config.psm1)
# ============================================================

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

    if (-not (Test-Path $ConfigPath)) {
        throw "設定ファイルが見つかりません: $ConfigPath"
    }

    try {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $config = $content | ConvertFrom-Json
        Write-Host "[INFO]  設定ファイル読み込み: $ConfigPath" -ForegroundColor Cyan
    }
    catch {
        throw "config.jsonのJSONパースに失敗しました: $_"
    }

    foreach ($field in $script:RequiredFields) {
        $value = $config.$field
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
            throw "config.jsonに必須フィールドがありません: '$field'"
        }
    }
    Write-Host "[ OK ]  必須フィールド検証OK" -ForegroundColor Green

    if ($config.linuxHost -eq "<your-linux-host>") {
        Write-Warning "config.json の linuxHost がプレースホルダーのままです。実際のホスト名に変更してください。"
    }

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

# Backward-compatible wrapper
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

    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
    $ext = [System.IO.Path]::GetExtension($ConfigPath)
    $backupFile = Join-Path $BackupDir "${baseName}_${timestamp}${ext}"

    try {
        $content = Get-Content -Path $ConfigPath -Raw -Encoding UTF8

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
