<#
.SYNOPSIS
    Agent Teams runtime diagnostic and team composition tool.
.DESCRIPTION
    Displays available agents, analyzes a task description, and shows
    the recommended team composition with specialist assignments.
#>

param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',
    [string]$ProjectRoot,
    [string]$Task = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Import-Module (Join-Path $ProjectRoot 'scripts\lib\AgentTeams.psm1') -Force

$report = Get-AgentTeamReport -ProjectRoot $ProjectRoot -TaskDescription $Task

if ($OutputFormat -eq 'Json') {
    $report | ConvertTo-Json -Depth 8
}
else {
    Show-AgentTeamReport -Report $report
}
