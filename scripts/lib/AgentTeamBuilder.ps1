# ============================================================
# AgentTeamBuilder.ps1 - チーム組成・レポート生成
# Depends on: AgentDefinition.ps1 (dot-sourced first in AgentTeams.psm1)
# ============================================================
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Assembles an agent team based on task description and available agent definitions.
#>
function New-AgentTeam {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal autonomous CLI function; ShouldProcess disrupts unattended operation')]
    param(
        [Parameter(Mandatory)]
        [string]$TaskDescription,
        [string]$AgentsDir,
        [string]$RulesPath
    )

    $analysis = Get-TaskTypeAnalysis -TaskDescription $TaskDescription
    $backlogRule = Get-BacklogRuleMatch -TaskDescription $TaskDescription -RulesPath $RulesPath

    $availableAgents = @()
    if ($AgentsDir -and (Test-Path $AgentsDir)) {
        $availableAgents = @(Import-AgentDefinition -AgentsDir $AgentsDir)
    }

    $team = [ordered]@{
        taskDescription = $TaskDescription
        taskTypes       = $analysis.types
        priority        = $backlogRule.priority
        owner           = $backlogRule.owner
        coreTeam        = @()
        specialists     = @()
        allAgentIds     = @()
        teamSize        = 0
    }

    foreach ($coreRole in $script:CoreRoles) {
        $roleAgents = @()
        foreach ($agentId in $coreRole.agents) {
            $found = $availableAgents | Where-Object { $_.id -eq $agentId } | Select-Object -First 1
            if ($found) {
                $roleAgents += $found
            }
        }
        $team.coreTeam += [pscustomobject]@{
            role       = $coreRole.role
            emoji      = $coreRole.emoji
            agentIds   = @($coreRole.agents)
            agentCount = $roleAgents.Count
        }
    }

    $specialistIds = @()
    foreach ($agentId in $analysis.agents) {
        $coreAgentIds = @($script:CoreRoles | ForEach-Object { $_.agents } | ForEach-Object { $_ })
        if ($agentId -notin $coreAgentIds) {
            $found = $availableAgents | Where-Object { $_.id -eq $agentId } | Select-Object -First 1
            if ($found) {
                $team.specialists += [pscustomobject]@{
                    id          = $found.id
                    name        = $found.name
                    description = $found.description
                    reason      = "Task type match: $($analysis.types -join ', ')"
                }
                $specialistIds += $found.id
            }
        }
    }

    $team.allAgentIds = @(
        @($script:CoreRoles | ForEach-Object { $_.agents } | ForEach-Object { $_ }) +
        $specialistIds
    ) | Select-Object -Unique
    $team.teamSize = $team.coreTeam.Count + $team.specialists.Count

    return [pscustomobject]$team
}

<#
.SYNOPSIS
    Formats an agent team composition as a discussion-style text block.
#>
function Format-AgentTeamDiscussion {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Team,
        [string]$Topic
    )

    $lines = @()
    $lines += ''
    $lines += "=== Agent Teams Discussion ==="
    $lines += "Topic: $Topic"
    $lines += "Task Types: $($Team.taskTypes -join ', ')"
    $lines += "Priority: $($Team.priority) | Owner: $($Team.owner)"
    $lines += ''

    foreach ($role in @($Team.coreTeam)) {
        $agentList = if ($role.agentIds.Count -gt 0) { $role.agentIds -join ', ' } else { '(auto-assign)' }
        $lines += "  $($role.emoji) **$($role.role)**: [$agentList]"
    }

    if (@($Team.specialists).Count -gt 0) {
        $lines += ''
        $lines += '  --- Specialists ---'
        foreach ($specialist in @($Team.specialists)) {
            $lines += "  + $($specialist.name): $($specialist.description)"
            $lines += "    Reason: $($specialist.reason)"
        }
    }

    $lines += ''
    $lines += "Team Size: $($Team.teamSize) roles ($(@($Team.specialists).Count) specialists)"
    $lines += "=== End Discussion ==="
    $lines += ''

    return ($lines -join "`n")
}

<#
.SYNOPSIS
    Displays the agent team composition in a formatted console output.
#>
function Show-AgentTeamComposition {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Team
    )

    Write-Host ''
    Write-Host '=== Agent Team Composition ===' -ForegroundColor Magenta
    Write-Host "Task: $($Team.taskDescription)" -ForegroundColor Cyan
    Write-Host "Types: $($Team.taskTypes -join ', ') | Priority: $($Team.priority) | Owner: $($Team.owner)" -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  Core Team:' -ForegroundColor Yellow
    foreach ($role in @($Team.coreTeam)) {
        $agentList = if ($role.agentIds.Count -gt 0) { $role.agentIds -join ', ' } else { '(auto-assign)' }
        Write-Host "    $($role.emoji) $($role.role): $agentList" -ForegroundColor Green
    }

    if (@($Team.specialists).Count -gt 0) {
        Write-Host ''
        Write-Host '  Specialists:' -ForegroundColor Yellow
        foreach ($specialist in @($Team.specialists)) {
            Write-Host "    + $($specialist.name)" -ForegroundColor Cyan
            Write-Host "      $($specialist.description)" -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host "  Team Size: $($Team.teamSize) roles ($(@($Team.specialists).Count) specialists)" -ForegroundColor Magenta
    Write-Host ''
}

<#
.SYNOPSIS
    Generates a report of available agents and optionally builds an agent team for a given task.
#>
function Get-AgentTeamReport {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [string]$TaskDescription = ''
    )

    $agentsDir = Join-Path $ProjectRoot '.claude\claudeos\agents'
    $rulesPath = Join-Path $ProjectRoot 'config\agent-teams-backlog-rules.json'

    $availableAgents = @()
    if (Test-Path $agentsDir) {
        $availableAgents = @(Import-AgentDefinition -AgentsDir $agentsDir)
    }

    $report = [ordered]@{
        agentsDir       = $agentsDir
        agentsDirExists = (Test-Path $agentsDir)
        agentCount      = $availableAgents.Count
        agents          = $availableAgents
        rulesPath       = $rulesPath
        rulesExist      = (Test-Path $rulesPath)
        team            = $null
    }

    if ($TaskDescription) {
        $report.team = New-AgentTeam -TaskDescription $TaskDescription -AgentsDir $agentsDir -RulesPath $rulesPath
    }

    return [pscustomobject]$report
}

<#
.SYNOPSIS
    Displays the agent team report to the console with formatted output.
#>
function Show-AgentTeamReport {
    param([pscustomobject]$Report)

    Write-Host ''
    Write-Host '=== Agent Teams Runtime ===' -ForegroundColor Magenta
    Write-Host ''

    if ($Report.agentsDirExists) {
        Write-Host "[ OK ] Agent definitions: $($Report.agentCount) agents loaded" -ForegroundColor Green
        Write-Host "       Path: $($Report.agentsDir)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[WARN] Agent definitions directory not found: $($Report.agentsDir)" -ForegroundColor Yellow
    }

    if ($Report.rulesExist) {
        Write-Host "[ OK ] Backlog rules: $($Report.rulesPath)" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Backlog rules not found: $($Report.rulesPath)" -ForegroundColor Yellow
    }

    Write-Host ''

    if ($Report.agentCount -gt 0) {
        Write-Host '  Available Agents:' -ForegroundColor Yellow
        foreach ($agent in @($Report.agents)) {
            $desc = if ($agent.description) { " - $($agent.description)" } else { '' }
            Write-Host "    $($agent.id)$desc" -ForegroundColor Cyan
        }
    }

    if ($null -ne $Report.team) {
        Write-Host ''
        Show-AgentTeamComposition -Team $Report.team
    }

    Write-Host ''
}
