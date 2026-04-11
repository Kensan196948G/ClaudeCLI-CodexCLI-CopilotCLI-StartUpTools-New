# sync-role-contracts.ps1
#
# Synchronizes role-contracts.md and related core files between the
# project-local .claude/claudeos/ and the user-global ~/.claude/claudeos/.
#
# Why this exists:
# - Git on Windows typically has core.symlinks=false, so a symlink
#   would be serialized as a plain text file containing the link target,
#   corrupting the file for fresh clones on other machines.
# - Two physical files are safer. This script prevents drift between them.
#
# Direction: project -> global (project is the version-controlled source of truth).
#
# Usage:
#   pwsh .claude/claudeos/scripts/sync-role-contracts.ps1
#   pwsh .claude/claudeos/scripts/sync-role-contracts.ps1 -CheckOnly
#   pwsh .claude/claudeos/scripts/sync-role-contracts.ps1 -Reverse   # global -> project
#
# Exit codes:
#   0 : synced successfully (or already in sync)
#   1 : drift detected (CheckOnly mode)
#   2 : source file missing

param(
    [switch]$CheckOnly,
    [switch]$Reverse
)

$ErrorActionPreference = 'Stop'

$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot '..')
# Build global path with platform-neutral separators so the script also works
# under Linux/macOS pwsh (where '.claude\claudeos' would be treated as a
# single directory name because backslash is not a path separator).
$GlobalDir  = Join-Path (Join-Path $HOME '.claude') 'claudeos'

# Only role-contracts.md is kept byte-identical across both locations.
# The other files (orchestrator, loop-guard, token-budget, loops/*) are
# intentionally divergent: global holds a minimal baseline, project holds
# an expanded operational version. Do NOT add them to this list.
$FilesToSync = @(
    'system\role-contracts.md'
)

if ($Reverse) {
    $SourceDir = $GlobalDir
    $TargetDir = $ProjectDir
    $Direction = 'global -> project'
} else {
    $SourceDir = $ProjectDir
    $TargetDir = $GlobalDir
    $Direction = 'project -> global'
}

Write-Host "Direction: $Direction"
Write-Host "Source: $SourceDir"
Write-Host "Target: $TargetDir"
Write-Host ""

$driftCount = 0
$syncCount  = 0

foreach ($rel in $FilesToSync) {
    $src = Join-Path $SourceDir $rel
    $dst = Join-Path $TargetDir $rel

    if (-not (Test-Path $src)) {
        Write-Warning "SOURCE MISSING: $rel"
        exit 2
    }

    $srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
    $dstHash = if (Test-Path $dst) { (Get-FileHash $dst -Algorithm SHA256).Hash } else { '(missing)' }

    if ($srcHash -eq $dstHash) {
        Write-Host "[ok]    $rel"
        continue
    }

    $driftCount++
    Write-Host "[drift] $rel"
    Write-Host "        src: $srcHash"
    Write-Host "        dst: $dstHash"

    if ($CheckOnly) { continue }

    $dstParent = Split-Path $dst -Parent
    if (-not (Test-Path $dstParent)) {
        New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
    }

    Copy-Item -Path $src -Destination $dst -Force
    $syncCount++
    Write-Host "[sync]  $rel"
}

Write-Host ""
if ($CheckOnly) {
    if ($driftCount -gt 0) {
        Write-Host "Drift detected in $driftCount file(s). Run without -CheckOnly to sync."
        exit 1
    } else {
        Write-Host "All files in sync."
        exit 0
    }
} else {
    Write-Host "Synced $syncCount file(s). $($FilesToSync.Count - $syncCount - $driftCount + $syncCount) already in sync."
    exit 0
}
