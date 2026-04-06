# ============================================================
# AgentTeams.psm1 - Agent Teams runtime engine
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.7.0
# ============================================================

Set-StrictMode -Version Latest

$script:CoreRoles = @(
    [pscustomobject]@{ role = 'CTO';       emoji = '🧠'; agents = @('loop-operator', 'planner') }
    [pscustomobject]@{ role = 'Architect';  emoji = '🏗'; agents = @('architect', 'api-designer') }
    [pscustomobject]@{ role = 'Developer';  emoji = '👨‍💻'; agents = @() }
    [pscustomobject]@{ role = 'QA';         emoji = '🧪'; agents = @('qa', 'tdd-guide', 'e2e-runner') }
    [pscustomobject]@{ role = 'Security';   emoji = '🔐'; agents = @('security', 'security-reviewer') }
    [pscustomobject]@{ role = 'DevOps';     emoji = '🚀'; agents = @('ops', 'release-manager') }
    [pscustomobject]@{ role = 'Reviewer';   emoji = '🔎'; agents = @('code-reviewer') }
)

$script:TaskTypePatterns = @(
    [pscustomobject]@{ type = 'api';       pattern = 'API|REST|endpoint|backend|サーバー';                      agents = @('dev-api', 'api-designer') }
    [pscustomobject]@{ type = 'ui';        pattern = 'UI|frontend|フロントエンド|React|Vue|画面';               agents = @('dev-ui') }
    [pscustomobject]@{ type = 'database';  pattern = 'DB|database|migration|スキーマ|テーブル';                 agents = @('database-reviewer') }
    [pscustomobject]@{ type = 'security';  pattern = 'security|auth|認証|権限|脆弱性|secret';                  agents = @('security-reviewer') }
    [pscustomobject]@{ type = 'ci';        pattern = 'CI|CD|pipeline|Actions|build|デプロイ';                   agents = @('ops', 'build-error-resolver') }
    [pscustomobject]@{ type = 'test';      pattern = 'test|テスト|Pester|Jest|E2E|品質';                       agents = @('tester', 'tdd-guide', 'e2e-runner') }
    [pscustomobject]@{ type = 'refactor';  pattern = 'refactor|リファクタ|整理|命名|技術負債';                  agents = @('refactor-cleaner') }
    [pscustomobject]@{ type = 'docs';      pattern = 'docs|README|ドキュメント|documentation';                  agents = @('doc-updater') }
    [pscustomobject]@{ type = 'incident';  pattern = 'incident|障害|緊急|ダウン|復旧';                          agents = @('incident-triager', 'build-error-resolver') }
    [pscustomobject]@{ type = 'typescript';pattern = 'TypeScript|ts|tsx|Node\.js';                              agents = @('typescript-reviewer') }
    [pscustomobject]@{ type = 'python';    pattern = 'Python|Django|Flask|FastAPI|pip';                         agents = @('python-reviewer') }
    [pscustomobject]@{ type = 'go';        pattern = 'Go|golang|go\.mod';                                      agents = @('go-reviewer', 'go-build-resolver') }
    [pscustomobject]@{ type = 'rust';      pattern = 'Rust|cargo|Cargo\.toml';                                  agents = @('rust-reviewer', 'rust-build-resolver') }
    [pscustomobject]@{ type = 'java';      pattern = 'Java|Spring|Maven|Gradle';                                agents = @('java-reviewer', 'java-build-resolver') }
    [pscustomobject]@{ type = 'cpp';       pattern = 'C\+\+|cpp|CMake';                                        agents = @('cpp-reviewer', 'cpp-build-resolver') }
    [pscustomobject]@{ type = 'kotlin';    pattern = 'Kotlin|Android';                                          agents = @('kotlin-reviewer', 'kotlin-build-resolver') }
)

function Import-AgentDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$AgentsDir
    )

    $agents = @()
    if (-not (Test-Path $AgentsDir)) {
        return $agents
    }

    foreach ($file in @(Get-ChildItem -Path $AgentsDir -Filter '*.md' -File | Where-Object { $_.Name -ne 'CLAUDE.md' })) {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $agent = [ordered]@{
            id          = $file.BaseName
            name        = $file.BaseName
            description = ''
            tools       = @()
            filePath    = $file.FullName
        }

        if ($content -match '(?s)^---\s*\r?\n(.+?)\r?\n---') {
            $frontmatter = $Matches[1]
            foreach ($line in ($frontmatter -split '\r?\n')) {
                if ($line -match '^name:\s*(.+)$') {
                    $agent.name = $Matches[1].Trim()
                }
                elseif ($line -match '^description:\s*(.+)$') {
                    $agent.description = $Matches[1].Trim()
                }
                elseif ($line -match '^tools:\s*(.+)$') {
                    $agent.tools = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }
            }
        }

        if (-not $agent.description) {
            $bodyLines = ($content -replace '(?s)^---\s*\r?\n.+?\r?\n---\s*\r?\n', '') -split '\r?\n'
            foreach ($bodyLine in $bodyLines) {
                $trimmed = $bodyLine.Trim()
                if ($trimmed -and $trimmed -notmatch '^#') {
                    $agent.description = $trimmed
                    break
                }
            }
        }

        $agents += [pscustomobject]$agent
    }

    return $agents
}

function Get-TaskTypeAnalysis {
    param(
        [Parameter(Mandatory)]
        [string]$TaskDescription
    )

    $matchedTypes = @()
    $matchedAgents = @()

    foreach ($tp in $script:TaskTypePatterns) {
        if ($TaskDescription -match $tp.pattern) {
            $matchedTypes += $tp.type
            $matchedAgents += $tp.agents
        }
    }

    $matchedAgents = @($matchedAgents | Select-Object -Unique)

    if ($matchedTypes.Count -eq 0) {
        $matchedTypes = @('general')
    }

    return [pscustomobject]@{
        types  = $matchedTypes
        agents = $matchedAgents
    }
}

function Get-BacklogRuleMatch {
    param(
        [Parameter(Mandatory)]
        [string]$TaskDescription,
        [string]$RulesPath
    )

    $result = [pscustomobject]@{
        priority = 'P2'
        owner    = 'ScrumMaster'
        source   = 'AgentTeamsMatrix'
        matched  = $false
    }

    if (-not $RulesPath -or -not (Test-Path $RulesPath)) {
        return $result
    }

    try {
        $rules = Get-Content -Path $RulesPath -Raw -Encoding UTF8 | ConvertFrom-Json

        foreach ($rule in @($rules.rules)) {
            if ($TaskDescription -match $rule.pattern) {
                $result.priority = $rule.priority
                $result.owner = $rule.owner
                $result.matched = $true
                break
            }
        }

        if (-not $result.matched -and $rules.default) {
            $result.priority = $rules.default.priority
            $result.owner = $rules.default.owner
            $result.source = $rules.default.source
        }
    }
    catch {
        # rules file parse error - use defaults
    }

    return $result
}

function New-AgentTeam {
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
        $availableAgents = @(Import-AgentDefinitions -AgentsDir $AgentsDir)
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
        $availableAgents = @(Import-AgentDefinitions -AgentsDir $agentsDir)
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

    $agents = Import-AgentDefinitions -AgentsDir $AgentsDir

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

Export-ModuleMember -Function @(
    'Import-AgentDefinitions',
    'Get-TaskTypeAnalysis',
    'Get-BacklogRuleMatch',
    'New-AgentTeam',
    'Format-AgentTeamDiscussion',
    'Show-AgentTeamComposition',
    'Get-AgentTeamReport',
    'Show-AgentTeamReport',
    'Get-AgentCapabilityMatrix',
    'Show-AgentCapabilityMatrix',
    'Get-AgentQuickStatus'
)
