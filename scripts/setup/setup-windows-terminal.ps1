param(
    [string]$StartingDirectory = '%USERPROFILE%',
    [string]$ProfileName = 'AI CLI Startup',
    [string[]]$AdditionalProfileNames = @(),
    [switch]$SetAsDefault,
    [switch]$NonInteractive,
    [string]$SettingsPath = '',
    [ValidateSet('One Half Light', 'Campbell', 'One Half Dark')]
    [string]$Theme = 'One Half Light',
    [ValidateRange(8, 32)]
    [int]$FontSize = 18,
    [ValidateRange(50, 100)]
    [int]$Opacity = 95,
    [string]$FontFace = 'Cascadia Code',
    [string]$BackgroundImage = '',
    [bool]$UseAcrylic = $true,
    [string]$ThemeJsonPath = '',
    [string]$ProfileOverridesJsonPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WindowsTerminalSettingsPath {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return $ExplicitPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:AI_STARTUP_WINDOWS_TERMINAL_SETTINGS_PATH)) {
        return $env:AI_STARTUP_WINDOWS_TERMINAL_SETTINGS_PATH
    }

    foreach ($candidate in @(
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-ExternalScheme {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $content = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($content -is [System.Array]) {
        return $content[0]
    }

    return $content
}

function Get-ProfileOverrides {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return @()
    }

    $content = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($content -is [System.Array]) {
        return @($content)
    }
    if ($content.PSObject.Properties.Name -contains 'profiles' -and $content.profiles) {
        return @($content.profiles)
    }

    return @($content)
}

function Ensure-JsonRootMembers {
    param([object]$Settings)

    if (-not ($Settings.PSObject.Properties.Name -contains 'profiles') -or $null -eq $Settings.profiles) {
        $Settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{ list = @() }) -Force
    }
    if (-not ($Settings.profiles.PSObject.Properties.Name -contains 'list') -or $null -eq $Settings.profiles.list) {
        $Settings.profiles | Add-Member -NotePropertyName list -NotePropertyValue @() -Force
    }
    if (-not ($Settings.PSObject.Properties.Name -contains 'schemes') -or $null -eq $Settings.schemes) {
        $Settings | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force
    }
}

function New-TerminalProfileObject {
    param(
        [string]$Name,
        [string]$Guid,
        [string]$SchemeName,
        [string]$ProfileStartingDirectory = $StartingDirectory,
        [string]$ProfileIcon = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',
        [string]$ProfileBackgroundImage = $BackgroundImage,
        [string]$ProfileFontFace = $FontFace,
        [int]$ProfileFontSize = $FontSize,
        [int]$ProfileOpacity = $Opacity,
        [string]$ProfileColorScheme = $SchemeName
    )

    $terminalProfile = [pscustomobject]@{
        name = $Name
        guid = $Guid
        commandline = 'powershell.exe -NoExit'
        startingDirectory = $ProfileStartingDirectory
        icon = $ProfileIcon
        font = [pscustomobject]@{
            face = $ProfileFontFace
            size = $ProfileFontSize
            weight = 'normal'
        }
        colorScheme = $ProfileColorScheme
        opacity = $ProfileOpacity
        useAcrylic = $UseAcrylic
        cursorShape = 'bar'
        cursorColor = '#FFFFFF'
        padding = '8'
        antialiasingMode = 'cleartype'
        closeOnExit = 'graceful'
        historySize = 9001
        snapOnInput = $true
        altGrAliasing = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($ProfileBackgroundImage)) {
        $terminalProfile | Add-Member -NotePropertyName backgroundImage -NotePropertyValue $ProfileBackgroundImage -Force
        $terminalProfile | Add-Member -NotePropertyName backgroundImageOpacity -NotePropertyValue 0.15 -Force
        $terminalProfile | Add-Member -NotePropertyName backgroundImageStretchMode -NotePropertyValue 'uniformToFill' -Force
    }

    return $terminalProfile
}

function Upsert-TerminalProfile {
    param(
        [object]$Settings,
        [string]$Name,
        [string]$SchemeName,
        [string]$ProfileStartingDirectory = $StartingDirectory,
        [string]$ProfileIcon = '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',
        [string]$ProfileBackgroundImage = $BackgroundImage,
        [string]$ProfileFontFace = $FontFace,
        [int]$ProfileFontSize = $FontSize,
        [int]$ProfileOpacity = $Opacity,
        [string]$ProfileColorScheme = $SchemeName
    )

    $existing = @($Settings.profiles.list | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
    $current = if ($existing.Count -gt 0) { $existing[0] } else { $null }
    $guid = if ($null -ne $current -and $current.guid) { "$($current.guid)" } else { "{0}" -f ('{' + [guid]::NewGuid().ToString() + '}') }
    $terminalProfile = New-TerminalProfileObject -Name $Name -Guid $guid -SchemeName $SchemeName -ProfileStartingDirectory $ProfileStartingDirectory -ProfileIcon $ProfileIcon -ProfileBackgroundImage $ProfileBackgroundImage -ProfileFontFace $ProfileFontFace -ProfileFontSize $ProfileFontSize -ProfileOpacity $ProfileOpacity -ProfileColorScheme $ProfileColorScheme

    if ($null -ne $current) {
        $index = [array]::IndexOf($Settings.profiles.list, $current)
        if ($index -ge 0) {
            $Settings.profiles.list[$index] = $terminalProfile
        }
    }
    else {
        $Settings.profiles.list += $terminalProfile
    }

    return $terminalProfile
}

if ($StartingDirectory -and
    $StartingDirectory -notmatch '^(%[^%]+%|[A-Za-z]:\\|\\\\|\\.|/)' -and
    $StartingDirectory -notmatch '^[A-Za-z]:$') {
    $AdditionalProfileNames = @($AdditionalProfileNames) + @($StartingDirectory)
    $StartingDirectory = '%USERPROFILE%'
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  Windows Terminal setup for AI CLI' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

$resolvedSettingsPath = Get-WindowsTerminalSettingsPath -ExplicitPath $SettingsPath
if ([string]::IsNullOrWhiteSpace($resolvedSettingsPath)) {
    Write-Host 'ERROR: Windows Terminal settings.json was not found.' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $resolvedSettingsPath)) {
    $settingsDir = Split-Path -Parent $resolvedSettingsPath
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }
    Set-Content -Path $resolvedSettingsPath -Value '{"profiles":{"list":[]},"schemes":[]}' -Encoding UTF8
}

try {
    $settings = Get-Content -Path $resolvedSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Write-Host "ERROR: Failed to read settings.json: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Ensure-JsonRootMembers -Settings $settings

$externalScheme = Get-ExternalScheme -Path $ThemeJsonPath
$profileOverrides = Get-ProfileOverrides -Path $ProfileOverridesJsonPath
$effectiveTheme = if ($null -ne $externalScheme -and $externalScheme.PSObject.Properties.Name -contains 'name' -and $externalScheme.name) { "$($externalScheme.name)" } else { $Theme }

$builtInScheme = $settings.schemes | Where-Object { $_.name -eq 'One Half Light' } | Select-Object -First 1
if ($null -eq $builtInScheme) {
    $settings.schemes += [pscustomobject]@{
        name = 'One Half Light'
        background = '#FAFAFA'
        foreground = '#383A42'
        cursorColor = '#528BFF'
        selectionBackground = '#4F525D'
        black = '#383A42'
        red = '#E45649'
        green = '#50A14F'
        yellow = '#C18401'
        blue = '#0184BC'
        purple = '#A626A4'
        cyan = '#0997B3'
        white = '#FAFAFA'
        brightBlack = '#4F525D'
        brightRed = '#E45649'
        brightGreen = '#50A14F'
        brightYellow = '#C18401'
        brightBlue = '#0184BC'
        brightPurple = '#A626A4'
        brightCyan = '#0997B3'
        brightWhite = '#FFFFFF'
    }
}

if ($null -ne $externalScheme) {
    $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $externalScheme.name })
    $settings.schemes += $externalScheme
}

$mainOverride = @($profileOverrides | Where-Object { $_.name -eq $ProfileName } | Select-Object -First 1)
$mainTheme = if ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'colorScheme') -and $mainOverride[0].colorScheme) { "$($mainOverride[0].colorScheme)" } elseif ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'theme') -and $mainOverride[0].theme) { "$($mainOverride[0].theme)" } else { $effectiveTheme }
$mainDir = if ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'startingDirectory') -and $mainOverride[0].startingDirectory) { "$($mainOverride[0].startingDirectory)" } else { $StartingDirectory }
$mainIcon = if ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'icon') -and $mainOverride[0].icon) { "$($mainOverride[0].icon)" } else { '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' }
$mainBackgroundImage = if ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'backgroundImage') -and $mainOverride[0].backgroundImage) { "$($mainOverride[0].backgroundImage)" } else { $BackgroundImage }
$mainFontFace = if ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'fontFace') -and $mainOverride[0].fontFace) { "$($mainOverride[0].fontFace)" } else { $FontFace }
$mainFontSize = if ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'fontSize') -and $mainOverride[0].fontSize) { [int]$mainOverride[0].fontSize } else { $FontSize }
$mainOpacity = if ($mainOverride.Count -gt 0 -and ($mainOverride[0].PSObject.Properties.Name -contains 'opacity') -and $mainOverride[0].opacity) { [int]$mainOverride[0].opacity } else { $Opacity }
$mainProfile = Upsert-TerminalProfile -Settings $settings -Name $ProfileName -SchemeName $mainTheme -ProfileStartingDirectory $mainDir -ProfileIcon $mainIcon -ProfileBackgroundImage $mainBackgroundImage -ProfileFontFace $mainFontFace -ProfileFontSize $mainFontSize -ProfileOpacity $mainOpacity -ProfileColorScheme $mainTheme
foreach ($name in @($AdditionalProfileNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $override = @($profileOverrides | Where-Object { $_.name -eq $name } | Select-Object -First 1)
    $profileTheme = if ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'colorScheme') -and $override[0].colorScheme) { "$($override[0].colorScheme)" } elseif ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'theme') -and $override[0].theme) { "$($override[0].theme)" } else { $effectiveTheme }
    $profileDir = if ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'startingDirectory') -and $override[0].startingDirectory) { "$($override[0].startingDirectory)" } else { $StartingDirectory }
    $profileIcon = if ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'icon') -and $override[0].icon) { "$($override[0].icon)" } else { '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' }
    $profileBackgroundImage = if ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'backgroundImage') -and $override[0].backgroundImage) { "$($override[0].backgroundImage)" } else { $BackgroundImage }
    $profileFontFace = if ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'fontFace') -and $override[0].fontFace) { "$($override[0].fontFace)" } else { $FontFace }
    $profileFontSize = if ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'fontSize') -and $override[0].fontSize) { [int]$override[0].fontSize } else { $FontSize }
    $profileOpacity = if ($override.Count -gt 0 -and ($override[0].PSObject.Properties.Name -contains 'opacity') -and $override[0].opacity) { [int]$override[0].opacity } else { $Opacity }
    [void](Upsert-TerminalProfile -Settings $settings -Name $name -SchemeName $profileTheme -ProfileStartingDirectory $profileDir -ProfileIcon $profileIcon -ProfileBackgroundImage $profileBackgroundImage -ProfileFontFace $profileFontFace -ProfileFontSize $profileFontSize -ProfileOpacity $profileOpacity -ProfileColorScheme $profileTheme)
}

if ($SetAsDefault) {
    if (-not ($settings.PSObject.Properties.Name -contains 'defaultProfile')) {
        $settings | Add-Member -NotePropertyName defaultProfile -NotePropertyValue $mainProfile.guid -Force
    }
    else {
        $settings.defaultProfile = $mainProfile.guid
    }
}

$json = $settings | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($resolvedSettingsPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "OK: settings saved: $resolvedSettingsPath" -ForegroundColor Green
Write-Host "OK: primary profile: $ProfileName" -ForegroundColor Green
if (@($AdditionalProfileNames).Count -gt 0) {
    Write-Host "OK: additional profiles: $($AdditionalProfileNames -join ', ')" -ForegroundColor Green
}
Write-Host "OK: theme: $effectiveTheme" -ForegroundColor Green
Write-Host "OK: font: $FontFace ($FontSize)" -ForegroundColor Green
Write-Host "OK: opacity: $Opacity" -ForegroundColor Green
Write-Host ''

if (-not $NonInteractive) {
    Read-Host 'Press Enter to exit' | Out-Null
}
