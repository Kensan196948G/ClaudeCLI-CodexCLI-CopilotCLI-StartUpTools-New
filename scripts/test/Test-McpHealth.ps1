<#
.SYNOPSIS
    MCP server health check script.
.DESCRIPTION
    Runs health checks on all configured MCP servers and displays results.
    Can be invoked from the Start-Menu or standalone.
#>

param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Import-Module (Join-Path $ProjectRoot 'scripts\lib\McpHealthCheck.psm1') -Force

$report = Get-McpHealthReport -ProjectRoot $ProjectRoot

if ($OutputFormat -eq 'Json') {
    $report | ConvertTo-Json -Depth 8
}
else {
    Show-McpHealthReport -Report $report
}
