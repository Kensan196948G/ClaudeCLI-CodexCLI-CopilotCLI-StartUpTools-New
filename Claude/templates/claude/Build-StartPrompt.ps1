<#
.SYNOPSIS
    instructions/ 内の分割ファイルを結合して START_PROMPT.md を自動生成する

.DESCRIPTION
    _header.md + 01-*.md ~ 09-*.md + _footer.md を結合して START_PROMPT.md を生成。
    分割ファイルが「編集用ソース」、生成される START_PROMPT.md が「実行用」。

.EXAMPLE
    .\Build-StartPrompt.ps1
    .\Build-StartPrompt.ps1 -DryRun
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$instructionsDir = Join-Path $scriptDir 'instructions'
$outputFile = Join-Path $scriptDir 'START_PROMPT.md'
$headerFile = Join-Path $instructionsDir '_header.md'
$footerFile = Join-Path $instructionsDir '_footer.md'

# Validate
if (-not (Test-Path $instructionsDir)) {
    Write-Error "instructions/ directory not found: $instructionsDir"; exit 1
}
if (-not (Test-Path $headerFile)) {
    Write-Error "_header.md not found: $headerFile"; exit 1
}
if (-not (Test-Path $footerFile)) {
    Write-Error "_footer.md not found: $footerFile"; exit 1
}

# Get numbered instruction files (exclude _header, _footer)
$files = Get-ChildItem -Path $instructionsDir -Filter '*.md' |
    Where-Object { $_.Name -match '^\d' } |
    Sort-Object Name

if ($files.Count -eq 0) {
    Write-Error "No numbered .md files found in instructions/"; exit 1
}

# Read and concatenate
$sb = New-Object System.Text.StringBuilder

# Header
$header = [System.IO.File]::ReadAllText($headerFile, [System.Text.Encoding]::UTF8)
$sb.AppendLine($header.TrimEnd()) | Out-Null
$sb.AppendLine() | Out-Null

# Instruction files
foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $sb.AppendLine($content.TrimEnd()) | Out-Null
    $sb.AppendLine() | Out-Null
    $sb.AppendLine('---') | Out-Null
    $sb.AppendLine() | Out-Null
}

# Footer
$footer = [System.IO.File]::ReadAllText($footerFile, [System.Text.Encoding]::UTF8)
$sb.AppendLine($footer.TrimEnd()) | Out-Null
$sb.AppendLine() | Out-Null

$result = $sb.ToString()
$lineCount = ($result -split "`n").Count

if ($DryRun) {
    Write-Host "=== DRY RUN ===" -ForegroundColor Cyan
    Write-Host "Files: $($files.Count) instruction files + header + footer"
    foreach ($f in $files) { Write-Host "  - $($f.Name)" }
    Write-Host "Lines: $lineCount"
}
else {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($outputFile, $result, $utf8NoBom)
    Write-Host "START_PROMPT.md generated successfully." -ForegroundColor Green
    Write-Host "  Source: $($files.Count) files + header + footer"
    foreach ($f in $files) { Write-Host "    - $($f.Name)" }
    Write-Host "  Lines:  $lineCount"
    Write-Host "  Output: $outputFile"
}
