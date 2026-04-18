# ============================================================
# RecentProjects.ps1 - 最近使用プロジェクト履歴管理
# ============================================================

<#
.SYNOPSIS
    最近使用プロジェクト履歴を取得

.PARAMETER HistoryPath
    履歴ファイルのパス（%USERPROFILE% などの環境変数を展開する）

.EXAMPLE
    $recent = Get-RecentProject -HistoryPath "%USERPROFILE%\.ai-startup\recent-projects.json"
#>
function Get-RecentProject {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HistoryPath
    )

    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($HistoryPath)

    if (-not (Test-Path $expandedPath)) {
        return @()
    }

    try {
        $content = Get-Content -Path $expandedPath -Raw -Encoding UTF8
        $data = $content | ConvertFrom-Json

        if ($null -eq $data -or $null -eq $data.projects) {
            return @()
        }

        $normalized = @()
        foreach ($entry in @($data.projects)) {
            if ($entry -is [string]) {
                $normalized += [pscustomobject]@{
                    project   = $entry
                    tool      = $null
                    mode      = $null
                    timestamp = $null
                    result    = $null
                    elapsedMs = $null
                }
                continue
            }

            if ($entry.PSObject.Properties.Name -contains 'project') {
                $tool      = if ($entry.PSObject.Properties.Name -contains 'tool') { "$($entry.tool)" } else { $null }
                $mode      = if ($entry.PSObject.Properties.Name -contains 'mode') { "$($entry.mode)" } else { $null }
                $timestamp = if ($entry.PSObject.Properties.Name -contains 'timestamp') { "$($entry.timestamp)" } else { $null }
                $normalized += [pscustomobject]@{
                    project   = "$($entry.project)"
                    tool      = if ([string]::IsNullOrWhiteSpace($tool)) { $null } else { $tool }
                    mode      = if ([string]::IsNullOrWhiteSpace($mode)) { $null } else { $mode }
                    timestamp = if ([string]::IsNullOrWhiteSpace($timestamp)) { $null } else { $timestamp }
                    result    = if ($entry.PSObject.Properties.Name -contains 'result' -and -not [string]::IsNullOrWhiteSpace("$($entry.result)")) { "$($entry.result)" } else { $null }
                    elapsedMs = if ($entry.PSObject.Properties.Name -contains 'elapsedMs' -and $null -ne $entry.elapsedMs) { [int]$entry.elapsedMs } else { $null }
                }
            }
        }

        return @($normalized)
    }
    catch {
        Write-Warning "最近使用プロジェクト履歴の読み込みに失敗しました: $_"
        return @()
    }
}

<#
.SYNOPSIS
    最近使用プロジェクト履歴を更新

.PARAMETER ProjectName
    追加するプロジェクト名

.PARAMETER HistoryPath
    履歴ファイルのパス

.PARAMETER MaxHistory
    保持する最大履歴数（デフォルト: 10）

.EXAMPLE
    Update-RecentProject -ProjectName "MyProject" -HistoryPath "%USERPROFILE%\.ai-startup\recent-projects.json"
#>
function Update-RecentProject {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal autonomous CLI function; ShouldProcess disrupts unattended operation')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectName,

        [Parameter(Mandatory=$false)]
        [ValidateSet('claude', 'codex', 'copilot', '')]
        [string]$Tool = '',

        [Parameter(Mandatory=$false)]
        [ValidateSet('local', 'ssh', '')]
        [string]$Mode = '',

        [Parameter(Mandatory=$false)]
        [ValidateSet('success', 'failure', 'cancelled', 'unknown', '')]
        [string]$Result = '',

        [Parameter(Mandatory=$false)]
        [Nullable[int]]$ElapsedMs = $null,

        [Parameter(Mandatory=$true)]
        [string]$HistoryPath,

        [Parameter(Mandatory=$false)]
        [int]$MaxHistory = 10
    )

    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($HistoryPath)

    $dir = Split-Path $expandedPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $projects = [System.Collections.Generic.List[object]]::new()
    $existing = Get-RecentProject -HistoryPath $HistoryPath
    foreach ($p in $existing) {
        $sameProject = ($p.project -eq $ProjectName)
        $sameTool    = (([string]::IsNullOrWhiteSpace($Tool) -and [string]::IsNullOrWhiteSpace($p.tool)) -or ($p.tool -eq $Tool))
        $sameMode    = (([string]::IsNullOrWhiteSpace($Mode) -and [string]::IsNullOrWhiteSpace($p.mode)) -or ($p.mode -eq $Mode))
        if (-not ($sameProject -and $sameTool -and $sameMode)) {
            $projects.Add($p)
        }
    }

    $projects.Insert(0, [pscustomobject]@{
        project   = $ProjectName
        tool      = if ([string]::IsNullOrWhiteSpace($Tool)) { $null } else { $Tool }
        mode      = if ([string]::IsNullOrWhiteSpace($Mode)) { $null } else { $Mode }
        timestamp = (Get-Date).ToString('o')
        result    = if ([string]::IsNullOrWhiteSpace($Result)) { $null } else { $Result }
        elapsedMs = if ($PSBoundParameters.ContainsKey('ElapsedMs') -and $null -ne $ElapsedMs) { [int]$ElapsedMs } else { $null }
    })

    if ($projects.Count -gt $MaxHistory) {
        $projects = [System.Collections.Generic.List[object]]($projects | Select-Object -First $MaxHistory)
    }

    try {
        $data = @{ projects = @($projects) }
        $json = $data | ConvertTo-Json -Depth 3
        Set-Content -Path $expandedPath -Value $json -Encoding UTF8
        Write-Host "[INFO]  最近使用プロジェクト更新: $ProjectName" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "最近使用プロジェクト履歴の保存に失敗しました: $_"
    }
}

<#
.SYNOPSIS
    Returns true if the recentProjects feature is enabled and configured in the given Config object.
#>
function Test-RecentProjectsEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Config
    )

    return ($null -ne $Config.recentProjects -and $Config.recentProjects.enabled -and -not [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile))
}
