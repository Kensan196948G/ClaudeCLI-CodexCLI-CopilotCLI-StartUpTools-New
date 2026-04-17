<#
.SYNOPSIS
    MCP 実環境ヘルスチェック

.DESCRIPTION
    CI とは分離して、実 MCP 環境が利用可能な端末だけで実行するための
    ランタイムチェックです。Test-AllTools.ps1 の診断に runtime probe を
    有効化して、startup / health / shutdown の結果を JSON またはテキストで返します。
#>

param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',
    [string]$ConfigPath = '',
    [string]$McpConfigPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StartupRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $StartupRoot 'scripts\test\Test-AllTools.ps1'
$originalProbe = $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE
$originalConfigPath = $env:AI_STARTUP_CONFIG_PATH
$originalMcpConfigPath = $env:AI_STARTUP_MCP_CONFIG_PATH
$requestedOutputFormat = $OutputFormat

try {
    $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE = '1'
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $env:AI_STARTUP_CONFIG_PATH = $ConfigPath
    }
    if (-not [string]::IsNullOrWhiteSpace($McpConfigPath)) {
        $env:AI_STARTUP_MCP_CONFIG_PATH = $McpConfigPath
    }
    . $scriptPath
    $configPath = Get-StartupConfigPath -StartupRoot $StartupRoot
    $report = Get-AllToolsDiagnostic -ConfigPath $configPath

    if ($requestedOutputFormat -eq 'Json') {
        $report | ConvertTo-Json -Depth 8
    }
    else {
        Show-AllToolsDiagnostic -Report $report
    }
}
finally {
    if ($null -eq $originalProbe) {
        Remove-Item Env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE -ErrorAction SilentlyContinue
    }
    else {
        $env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE = $originalProbe
    }

    if ($null -eq $originalConfigPath) {
        Remove-Item Env:AI_STARTUP_CONFIG_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:AI_STARTUP_CONFIG_PATH = $originalConfigPath
    }

    if ($null -eq $originalMcpConfigPath) {
        Remove-Item Env:AI_STARTUP_MCP_CONFIG_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:AI_STARTUP_MCP_CONFIG_PATH = $originalMcpConfigPath
    }
}
