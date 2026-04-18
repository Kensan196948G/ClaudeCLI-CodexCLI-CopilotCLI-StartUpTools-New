# ============================================================
# AgentTeams.psm1 - Agent Teams runtime engine（オーケストレーター）
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.7.0
#
# 実装は以下の .ps1 ファイルに分割されています:
#   AgentDefinition.ps1      — CoreRoles / TaskTypePatterns / Import-AgentDefinition / Get-TaskTypeAnalysis / Get-BacklogRuleMatch
#   AgentTeamBuilder.ps1     — New-AgentTeam / Format-AgentTeamDiscussion / Show-AgentTeamComposition / Get-AgentTeamReport / Show-AgentTeamReport
#   AgentCapabilityMatrix.ps1 — Get-AgentCapabilityMatrix / Show-AgentCapabilityMatrix / Get-AgentQuickStatus
# ============================================================

Set-StrictMode -Version Latest

# Dot-source submodules in dependency order — functions land in this module's scope
. (Join-Path $PSScriptRoot 'AgentDefinition.ps1')
. (Join-Path $PSScriptRoot 'AgentTeamBuilder.ps1')
. (Join-Path $PSScriptRoot 'AgentCapabilityMatrix.ps1')

Export-ModuleMember -Function '*'
