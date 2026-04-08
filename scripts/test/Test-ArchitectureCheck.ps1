# ============================================================
# Test-ArchitectureCheck.ps1 - Architecture Check standalone runner
# ============================================================
[CmdletBinding()]
param(
    [string]$Path = '',
    [ValidateSet('Table', 'Json')]
    [string]$OutputFormat = 'Table',
    [switch]$IncludeWarnings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$ModulePath = Join-Path $ScriptDir '..' 'lib' 'ArchitectureCheck.psm1'
Import-Module $ModulePath -Force -DisableNameChecking

if (-not $Path) {
    $Path = Split-Path $ScriptDir -Parent | Split-Path -Parent
}

if ($OutputFormat -eq 'Json') {
    $result = Invoke-ArchitectureCheck -Path $Path -IncludeWarnings:$IncludeWarnings
    $result | ConvertTo-Json -Depth 5
} else {
    $result = Show-ArchitectureCheckReport -Path $Path
}

if (-not $result.Passed) {
    exit 1
}
exit 0
