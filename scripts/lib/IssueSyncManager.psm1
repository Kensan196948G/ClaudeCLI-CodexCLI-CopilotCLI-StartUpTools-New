# ============================================================
# IssueSyncManager.psm1 - GitHub Issues <-> TASKS.md sync
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.7.0
# Issue #33: Issue / Backlog auto-generation
# ============================================================

Set-StrictMode -Version Latest

$script:DefaultTasksPath = 'TASKS.md'
$script:ManualSection = 'Manual Backlog'
$script:AutoSection = 'Auto Extracted From Agent Teams Matrix'
$script:IssueSection = 'GitHub Issues Sync'

function Get-TasksFilePath {
    param([string]$RepoRoot)
    if (-not $RepoRoot) {
        $RepoRoot = (git rev-parse --show-toplevel 2>$null)
    }
    return Join-Path $RepoRoot $script:DefaultTasksPath
}

function Get-GitHubIssues {
    <#
    .SYNOPSIS
        Fetches open GitHub Issues for the repository.
    .PARAMETER Owner
        Repository owner.
    .PARAMETER Repo
        Repository name.
    .PARAMETER Labels
        Optional label filter.
    .PARAMETER State
        Issue state (open/closed/all). Default: open.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repo,

        [string[]]$Labels = @(),
        [string]$State = 'open'
    )

    # Exclude 'body' field: not needed for TASKS.md sync and may contain
    # multi-line Japanese text that causes ConvertFrom-Json failures on
    # PowerShell 5.1 / CP932 console environments.
    $ghArgs = @('issue', 'list', '--repo', "$Owner/$Repo", '--state', $State, '--json', 'number,title,labels,state,assignees', '--limit', '100')
    if ($Labels.Count -gt 0) {
        $ghArgs += '--label'
        $ghArgs += ($Labels -join ',')
    }

    # Ensure gh UTF-8 output is captured correctly on PowerShell 5.1 (CP932 default).
    $prevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        $raw = & gh @ghArgs 2>&1
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch issues: $raw"
    }

    $issues = $raw | ConvertFrom-Json
    return @($issues)
}

function ConvertTo-TaskLine {
    <#
    .SYNOPSIS
        Converts a GitHub Issue to a TASKS.md line.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Issue,

        [int]$Index = 0
    )

    $priority = 'P2'
    $labelNames = @()
    if ($Issue.labels) {
        $labelNames = @($Issue.labels | ForEach-Object { $_.name })
    }
    if ($labelNames -contains 'bug') { $priority = 'P1' }
    if ($labelNames -contains 'enhancement') { $priority = 'P2' }
    if ($labelNames -contains 'documentation') { $priority = 'P3' }

    $owner = 'Unassigned'
    if ($Issue.assignees -and $Issue.assignees.Count -gt 0) {
        $owner = $Issue.assignees[0].login
    }

    $state = if ($Issue.state -eq 'closed') { '[DONE] ' } else { '' }
    $num = if ($Index -gt 0) { "$Index. " } else { '' }

    return "${num}${state}[Priority:$priority][Owner:$owner][Source:GitHub#$($Issue.number)] $($Issue.title)"
}

function ConvertFrom-TaskLine {
    <#
    .SYNOPSIS
        Parses a TASKS.md line back into structured data.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Line
    )

    $result = [ordered]@{
        Index    = 0
        Done     = $false
        Priority = 'P2'
        Owner    = 'Unassigned'
        Source   = ''
        IssueNum = $null
        Title    = ''
        Raw      = $Line
    }

    if ($Line -match '^\d+') {
        $result.Index = [int]($Matches[0])
    }

    $result.Done = $Line -match '\[DONE\]'

    if ($Line -match '\[Priority:([^\]]+)\]') {
        $result.Priority = $Matches[1]
    }
    if ($Line -match '\[Owner:([^\]]+)\]') {
        $result.Owner = $Matches[1]
    }
    if ($Line -match '\[Source:([^\]]+)\]') {
        $result.Source = $Matches[1]
    }
    if ($Line -match '\[Source:GitHub#(\d+)\]') {
        $result.IssueNum = [int]$Matches[1]
    }

    # Extract title: everything after the last ] bracket
    if ($Line -match '\]\s+(.+)$') {
        $result.Title = $Matches[1]
    }

    return [pscustomobject]$result
}

function Get-TasksSections {
    <#
    .SYNOPSIS
        Parses TASKS.md into sections with their content lines.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TasksPath
    )

    if (-not (Test-Path $TasksPath)) {
        return @{
            Header = @('# TASKS', '')
            Sections = @{}
            SectionOrder = @()
        }
    }

    $lines = Get-Content -Path $TasksPath -Encoding UTF8
    $header = @()
    $sections = [ordered]@{}
    $sectionOrder = @()
    $currentSection = $null

    foreach ($line in $lines) {
        if ($line -match '^##\s+(.+)$') {
            $currentSection = $Matches[1].Trim()
            $sections[$currentSection] = @()
            $sectionOrder += $currentSection
            continue
        }
        if ($null -eq $currentSection) {
            $header += $line
        }
        else {
            $sections[$currentSection] += $line
        }
    }

    return @{
        Header = $header
        Sections = $sections
        SectionOrder = $sectionOrder
    }
}

function Sync-IssuesToTasks {
    <#
    .SYNOPSIS
        Syncs GitHub Issues into the TASKS.md file under a dedicated section.
    .PARAMETER Owner
        Repository owner.
    .PARAMETER Repo
        Repository name.
    .PARAMETER TasksPath
        Path to TASKS.md.
    .PARAMETER DryRun
        If set, returns what would be written without modifying the file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repo,

        [string]$TasksPath,
        [switch]$DryRun
    )

    if (-not $TasksPath) {
        $TasksPath = Get-TasksFilePath
    }

    $issues = Get-GitHubIssues -Owner $Owner -Repo $Repo -State 'open'

    # Filter out pull requests (they also appear as issues)
    $issues = @($issues | Where-Object { -not ($_.PSObject.Properties.Name -contains 'pull_request') })

    $parsed = Get-TasksSections -TasksPath $TasksPath

    # Build new issue section lines
    $issueLines = @('')
    for ($i = 0; $i -lt $issues.Count; $i++) {
        $issueLines += (ConvertTo-TaskLine -Issue $issues[$i] -Index ($i + 1))
    }
    if ($issues.Count -eq 0) {
        $issueLines += '(No open issues)'
    }
    $issueLines += ''

    # Update or add section
    $parsed.Sections[$script:IssueSection] = $issueLines
    if ($script:IssueSection -notin $parsed.SectionOrder) {
        $parsed.SectionOrder += $script:IssueSection
    }

    # Rebuild file
    $output = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $parsed.Header) {
        $output.Add($line)
    }
    foreach ($sectionName in $parsed.SectionOrder) {
        $output.Add("## $sectionName")
        foreach ($line in $parsed.Sections[$sectionName]) {
            $output.Add($line)
        }
    }

    if ($DryRun) {
        return @{
            Content    = $output.ToArray()
            IssueCount = $issues.Count
            TasksPath  = $TasksPath
        }
    }

    [System.IO.File]::WriteAllLines($TasksPath, $output, [System.Text.UTF8Encoding]::new($false))

    return @{
        Synced     = $true
        IssueCount = $issues.Count
        TasksPath  = $TasksPath
    }
}

function Sync-TasksToIssues {
    <#
    .SYNOPSIS
        Creates GitHub Issues from TASKS.md manual entries that don't have a GitHub source.
    .PARAMETER Owner
        Repository owner.
    .PARAMETER Repo
        Repository name.
    .PARAMETER TasksPath
        Path to TASKS.md.
    .PARAMETER DryRun
        If set, returns what would be created without actually creating issues.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repo,

        [string]$TasksPath,
        [switch]$DryRun
    )

    if (-not $TasksPath) {
        $TasksPath = Get-TasksFilePath
    }

    $parsed = Get-TasksSections -TasksPath $TasksPath

    $manualLines = @()
    if ($parsed.Sections.Contains($script:ManualSection)) {
        $manualLines = @($parsed.Sections[$script:ManualSection] | Where-Object { $_ -match '^\d+\.\s' })
    }

    $toCreate = @()
    foreach ($line in $manualLines) {
        $task = ConvertFrom-TaskLine -Line $line
        if ($task.Done) { continue }
        if ($task.Source -match 'GitHub#') { continue }
        if ([string]::IsNullOrWhiteSpace($task.Title)) { continue }
        $toCreate += $task
    }

    if ($DryRun) {
        return @{
            WouldCreate = @($toCreate | ForEach-Object { $_.Title })
            Count       = $toCreate.Count
        }
    }

    $created = @()
    foreach ($task in $toCreate) {
        $body = "Auto-created from TASKS.md`n`nPriority: $($task.Priority)`nOwner: $($task.Owner)`nSource: $($task.Source)"
        $result = & gh issue create --repo "$Owner/$Repo" --title $task.Title --body $body 2>&1
        if ($LASTEXITCODE -eq 0) {
            $created += @{ Title = $task.Title; Url = $result }
        }
    }

    return @{
        Created = $created
        Count   = $created.Count
    }
}

function Get-SyncStatus {
    <#
    .SYNOPSIS
        Returns a comparison of TASKS.md vs GitHub Issues.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repo,

        [string]$TasksPath
    )

    if (-not $TasksPath) {
        $TasksPath = Get-TasksFilePath
    }

    $issues = Get-GitHubIssues -Owner $Owner -Repo $Repo
    $parsed = Get-TasksSections -TasksPath $TasksPath

    $issueSyncLines = @()
    if ($parsed.Sections.Contains($script:IssueSection)) {
        $issueSyncLines = @($parsed.Sections[$script:IssueSection] | Where-Object { $_ -match '^\d+\.\s' })
    }

    $trackedNums = @()
    foreach ($line in $issueSyncLines) {
        $task = ConvertFrom-TaskLine -Line $line
        if ($task.IssueNum) { $trackedNums += $task.IssueNum }
    }

    $issueNums = @($issues | ForEach-Object { $_.number })
    $missing = @($issueNums | Where-Object { $_ -notin $trackedNums })
    $stale = @($trackedNums | Where-Object { $_ -notin $issueNums })

    return [pscustomobject]@{
        InSync       = ($missing.Count -eq 0 -and $stale.Count -eq 0)
        MissingInTasks = $missing
        StaleInTasks   = $stale
        IssueCount     = $issueNums.Count
        TrackedCount   = $trackedNums.Count
    }
}

Export-ModuleMember -Function @(
    'Get-GitHubIssues'
    'ConvertTo-TaskLine'
    'ConvertFrom-TaskLine'
    'Get-TasksSections'
    'Sync-IssuesToTasks'
    'Sync-TasksToIssues'
    'Get-SyncStatus'
    'Get-TasksFilePath'
)
