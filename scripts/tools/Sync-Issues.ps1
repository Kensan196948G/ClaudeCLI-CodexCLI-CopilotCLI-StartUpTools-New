# Sync-Issues.ps1 - GitHub Issues <-> TASKS.md sync tool
# Actions: status, check, sync, sync-to-github
param(
    [ValidateSet('status', 'check', 'sync', 'sync-to-github')]
    [string]$Action = 'status',
    [switch]$DryRun,
    [string]$Owner = '',
    [string]$Repo = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $RepoRoot 'scripts\lib\IssueSyncManager.psm1') -Force -DisableNameChecking

$TasksPath = Get-TasksFilePath -RepoRoot $RepoRoot

# Auto-detect owner/repo from git remote if not provided
if (-not $Owner -or -not $Repo) {
    $remote = git remote get-url origin 2>$null
    if ($remote -match 'github\.com[:/]([^/]+)/([^/.]+)') {
        if (-not $Owner) { $Owner = $Matches[1] }
        if (-not $Repo) { $Repo = $Matches[2] }
    }
    else {
        throw "Cannot detect Owner/Repo from git remote. Specify -Owner and -Repo explicitly."
    }
}

switch ($Action) {
    'status' {
        $result = Get-SyncStatus -Owner $Owner -Repo $Repo -TasksPath $TasksPath
        Write-Host "Issue Sync Status:" -ForegroundColor Cyan
        Write-Host "  GitHub Issues: $($result.IssueCount)"
        Write-Host "  Tracked in TASKS.md: $($result.TrackedCount)"
        Write-Host "  In Sync: $($result.InSync)"
        if ($result.MissingInTasks.Count -gt 0) {
            Write-Host "  Missing in TASKS.md: #$($result.MissingInTasks -join ', #')" -ForegroundColor Yellow
        }
        if ($result.StaleInTasks.Count -gt 0) {
            Write-Host "  Stale in TASKS.md: #$($result.StaleInTasks -join ', #')" -ForegroundColor Yellow
        }
        exit 0
    }
    'check' {
        # CI-safe structural check (no GitHub API calls)
        $parsed = Get-TasksSections -TasksPath $TasksPath
        $hasIssueSection = $parsed.Sections.Contains('GitHub Issues Sync')
        $manualLines = @()
        if ($parsed.Sections.Contains('Manual Backlog')) {
            $manualLines = @($parsed.Sections['Manual Backlog'] | Where-Object { $_ -match '^\d+\.\s' })
        }
        $issueLines = @()
        if ($hasIssueSection) {
            $issueLines = @($parsed.Sections['GitHub Issues Sync'] | Where-Object { $_ -match '^\d+\.\s' })
        }
        $errors = @()

        # Validate task line format in all sections
        foreach ($line in ($manualLines + $issueLines)) {
            if ($line -notmatch '\[Priority:P[1-3]\]') {
                $errors += "Invalid priority format: $line"
            }
            if ($line -notmatch '\[Owner:[^\]]+\]') {
                $errors += "Missing owner: $line"
            }
            if ($line -notmatch '\[Source:[^\]]+\]') {
                $errors += "Missing source: $line"
            }
        }

        # Validate issue section lines have GitHub# source
        foreach ($line in $issueLines) {
            if ($line -notmatch '\[Source:GitHub#\d+\]') {
                $errors += "Issue sync line missing GitHub# source: $line"
            }
        }

        if ($errors.Count -gt 0) {
            $errors | ForEach-Object { Write-Host "ERROR: $_" -ForegroundColor Red }
            throw "TASKS.md format validation failed with $($errors.Count) error(s)."
        }

        Write-Host "TASKS.md format validation passed." -ForegroundColor Green
        Write-Host "  Manual Backlog items: $($manualLines.Count)"
        Write-Host "  GitHub Issues Sync items: $($issueLines.Count)"
        exit 0
    }
    'sync' {
        $result = Sync-IssuesToTasks -Owner $Owner -Repo $Repo -TasksPath $TasksPath -DryRun:$DryRun
        if ($DryRun) {
            Write-Host "DryRun - Would sync $($result.IssueCount) issues to $($result.TasksPath)" -ForegroundColor Yellow
            $result.Content | ForEach-Object { Write-Host $_ }
        }
        else {
            Write-Host "Synced $($result.IssueCount) issues to $($result.TasksPath)" -ForegroundColor Green
        }
        exit 0
    }
    'sync-to-github' {
        $result = Sync-TasksToIssues -Owner $Owner -Repo $Repo -TasksPath $TasksPath -DryRun:$DryRun
        if ($DryRun) {
            Write-Host "DryRun - Would create $($result.Count) issues:" -ForegroundColor Yellow
            $result.WouldCreate | ForEach-Object { Write-Host "  - $_" }
        }
        else {
            Write-Host "Created $($result.Count) issues:" -ForegroundColor Green
            $result.Created | ForEach-Object { Write-Host "  - $($_.Title): $($_.Url)" }
        }
        exit 0
    }
}
