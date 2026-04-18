# ============================================================
# AgentCapabilityMatrix.ps1 - ケイパビリティマトリクス・クイックステータス
# Depends on: AgentDefinition.ps1, AgentTeamBuilder.ps1 (dot-sourced first in AgentTeams.psm1)
# ============================================================

function Get-AgentCapabilityMatrix {
    <#
    .SYNOPSIS
        Returns a capability matrix showing all agents grouped by domain.
    .PARAMETER AgentsDir
        Directory containing agent .md files.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AgentsDir
    )

    $agents = Import-AgentDefinition -AgentsDir $AgentsDir

    $domains = [ordered]@{
        'Core Team'     = @('planner', 'architect', 'orchestrator', 'loop-operator', 'chief-of-staff')
        'Quality'       = @('code-reviewer', 'security-reviewer', 'tdd-guide', 'qa', 'tester', 'e2e-runner', 'harness-optimizer', 'refactor-cleaner')
        'Language'      = @('typescript-reviewer', 'python-reviewer', 'go-reviewer', 'java-reviewer', 'kotlin-reviewer', 'rust-reviewer', 'cpp-reviewer')
        'Build'         = @('build-error-resolver', 'go-build-resolver', 'java-build-resolver', 'kotlin-build-resolver', 'rust-build-resolver', 'cpp-build-resolver', 'pytorch-build-resolver')
        'Infrastructure'= @('ops', 'release-manager', 'security', 'database-reviewer', 'dev-api', 'dev-ui', 'api-designer')
        'Documentation' = @('doc-updater', 'docs-lookup', 'incident-triager')
    }

    $matrix = @()
    foreach ($domain in $domains.GetEnumerator()) {
        $domainAgents = @()
        foreach ($agentId in $domain.Value) {
            $agent = $agents | Where-Object { $_.id -eq $agentId }
            if ($agent) {
                $domainAgents += [pscustomobject]@{
                    Id          = $agent.id
                    Name        = $agent.name
                    Description = $agent.description
                    Tools       = if ($agent.tools) { $agent.tools } else { @() }
                }
            }
        }
        $matrix += [pscustomobject]@{
            Domain = $domain.Key
            Agents = $domainAgents
            Count  = $domainAgents.Count
        }
    }

    return $matrix
}

function Show-AgentCapabilityMatrix {
    <#
    .SYNOPSIS
        Displays the agent capability matrix in a formatted table.
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Matrix
    )

    Write-Host ''
    Write-Host '=== Agent Capability Matrix ===' -ForegroundColor Magenta
    Write-Host ''

    foreach ($domain in $Matrix) {
        Write-Host "  $($domain.Domain) ($($domain.Count) agents)" -ForegroundColor Yellow
        foreach ($agent in $domain.Agents) {
            $desc = if ($agent.Description) { " - $($agent.Description.Substring(0, [Math]::Min(60, $agent.Description.Length)))" } else { '' }
            Write-Host "    $($agent.Id)$desc" -ForegroundColor Cyan
        }
        Write-Host ''
    }
}

function Get-AgentQuickStatus {
    <#
    .SYNOPSIS
        Returns a one-line Agent Teams status string for dashboard display.
    #>
    param([string]$ProjectRoot)

    try {
        $report = Get-AgentTeamReport -ProjectRoot $ProjectRoot
        if ($report.agentsDirExists) {
            return "Agents: [OK] $($report.agentCount) loaded"
        }
        return 'Agents: not configured'
    }
    catch {
        return 'Agents: check failed'
    }
}
