#Requires -Version 7.0
<#
.SYNOPSIS
  Fact-check harness for ClaudeOS Evaluation Methodology §10.

.DESCRIPTION
  Reads a YAML or JSON claim list and verifies that referenced files and
  directories actually exist. Produces a verdict per claim and an overall
  accuracy score suitable for inclusion in an evaluation report.

.PARAMETER ClaimList
  Path to a JSON file with the following schema:

  [
    { "type": "file", "path": ".claude/claudeos/system/orchestrator.md" },
    { "type": "dir",  "path": "mcp-configs/" },
    { "type": "file_with_content",
      "path": ".github/workflows/ci.yml",
      "must_contain": "Pester" }
  ]

.EXAMPLE
  pwsh ./scripts/eval/fact-check.ps1 -ClaimList ./claims.json
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ClaimList,

    [string]$OutputPath = "./fact-check-report.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ClaimList)) {
    Write-Error "Claim list not found: $ClaimList"
    exit 1
}

$claims = Get-Content $ClaimList -Raw | ConvertFrom-Json
$results = @()
$passed = 0
$failed = 0

foreach ($claim in $claims) {
    $verdict = [ordered]@{
        type   = $claim.type
        path   = $claim.path
        status = "unknown"
        reason = ""
    }

    switch ($claim.type) {
        "file" {
            if (Test-Path $claim.path -PathType Leaf) {
                $verdict.status = "verified"
                $passed++
            } else {
                $verdict.status = "false_claim"
                $verdict.reason = "File does not exist"
                $failed++
            }
        }
        "dir" {
            if (Test-Path $claim.path -PathType Container) {
                $verdict.status = "verified"
                $passed++
            } else {
                $verdict.status = "false_claim"
                $verdict.reason = "Directory does not exist"
                $failed++
            }
        }
        "file_with_content" {
            if (-not (Test-Path $claim.path -PathType Leaf)) {
                $verdict.status = "false_claim"
                $verdict.reason = "File does not exist"
                $failed++
            } else {
                $content = Get-Content $claim.path -Raw
                if ($content -match [regex]::Escape($claim.must_contain)) {
                    $verdict.status = "verified"
                    $passed++
                } else {
                    $verdict.status = "content_mismatch"
                    $verdict.reason = "File exists but does not contain: $($claim.must_contain)"
                    $failed++
                }
            }
        }
        default {
            $verdict.status = "unsupported_type"
            $verdict.reason = "Unknown claim type: $($claim.type)"
            $failed++
        }
    }

    $results += [pscustomobject]$verdict
}

$total = $passed + $failed
$accuracy = if ($total -gt 0) { [math]::Round($passed / $total * 100, 1) } else { 0 }

$report = [ordered]@{
    schema_version = "1.0"
    timestamp      = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    claim_list     = (Resolve-Path $ClaimList).Path
    total          = $total
    verified       = $passed
    false_claims   = $failed
    accuracy_pct   = $accuracy
    results        = $results
}

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "[fact-check] total=$total verified=$passed false_claims=$failed accuracy=$accuracy%"
Write-Host "[fact-check] written: $OutputPath"

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "=== FALSE CLAIMS DETECTED ===" -ForegroundColor Red
    $results | Where-Object { $_.status -ne "verified" } | ForEach-Object {
        Write-Host "  [$($_.status)] $($_.path) :: $($_.reason)" -ForegroundColor Yellow
    }
    exit 1
}

exit 0
