Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Normalizes the tool filter string to a validated value or empty string for use in recent-menu queries.
#>
function ConvertTo-MenuRecentToolFilter {
    param([string]$ToolFilter = '')

    if ([string]::IsNullOrWhiteSpace($ToolFilter) -or $ToolFilter -eq 'all') {
        return ''
    }

    if ($ToolFilter -in @('claude', 'codex', 'copilot')) {
        return $ToolFilter
    }

    return ''
}

<#
.SYNOPSIS
    Normalizes the sort mode string to a validated value, defaulting to 'success'.
#>
function ConvertTo-MenuRecentSortMode {
    param([string]$SortMode = 'success')

    if ($SortMode -in @('success', 'timestamp', 'elapsed')) {
        return $SortMode
    }

    return 'success'
}

<#
.SYNOPSIS
    Returns a summary object of the active recent-menu filter, search, and sort settings.
#>
function Get-MenuRecentFilterSummary {
    param(
        [string]$ToolFilter = '',
        [string]$SearchQuery = '',
        [string]$SortMode = 'success'
    )

    return [pscustomobject]@{
        tool = if ([string]::IsNullOrWhiteSpace($ToolFilter)) { 'all' } else { $ToolFilter }
        search = if ([string]::IsNullOrWhiteSpace($SearchQuery)) { 'none' } else { $SearchQuery }
        sort = ConvertTo-MenuRecentSortMode -SortMode $SortMode
    }
}

Export-ModuleMember -Function ConvertTo-MenuRecentToolFilter
Export-ModuleMember -Function ConvertTo-MenuRecentSortMode
Export-ModuleMember -Function Get-MenuRecentFilterSummary
