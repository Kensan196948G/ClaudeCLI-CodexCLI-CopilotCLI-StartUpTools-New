# ============================================================
# SelfEvolution.Tests.ps1 - SelfEvolution.psm1 unit tests
# Pester 5.x  /  Phase 4 unit tests
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\lib\SelfEvolution.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-EvolutionStorePath' {

    It 'returns the same path when dir already exists' {
        $dir = Join-Path $TestDrive 'evo-existing'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $result = Get-EvolutionStorePath -BasePath $dir
        $result | Should -Be $dir
    }

    It 'creates directory when it does not exist' {
        $dir = Join-Path $TestDrive 'evo-new'
        $result = Get-EvolutionStorePath -BasePath $dir
        $result | Should -Be $dir
        Test-Path $dir | Should -Be $true
    }
}

Describe 'Save-EvolutionRecord' {

    It 'returns an object with SessionId' {
        $dir    = Join-Path $TestDrive 'evo-save1'
        $result = Save-EvolutionRecord -Phase 'Monitor' -StorePath $dir
        $result.SessionId | Should -Not -BeNullOrEmpty
    }

    It 'creates exactly one JSON file in StorePath' {
        $dir = Join-Path $TestDrive 'evo-save2'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Verify' -StorePath $dir
        $files = Get-ChildItem -Path $dir -Filter 'evolution_*.json'
        $files.Count | Should -Be 1
    }

    It 'saved JSON contains correct phase' {
        $dir = Join-Path $TestDrive 'evo-save3'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Build' -StorePath $dir
        $file = Get-ChildItem -Path $dir -Filter 'evolution_*.json' | Select-Object -First 1
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $data.phase | Should -Be 'Build'
    }

    It 'saved JSON contains version 1.0' {
        $dir = Join-Path $TestDrive 'evo-save4'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Monitor' -StorePath $dir
        $file = Get-ChildItem -Path $dir -Filter 'evolution_*.json' | Select-Object -First 1
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $data.version | Should -Be '1.0'
    }

    It 'saved JSON preserves Lessons array' {
        $dir = Join-Path $TestDrive 'evo-save5'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Improve' `
            -Lessons @('Always write tests first') -StorePath $dir
        $file = Get-ChildItem -Path $dir -Filter 'evolution_*.json' | Select-Object -First 1
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json
        $data.lessons | Should -Contain 'Always write tests first'
    }

    It 'FilePath in result points to the created file' {
        $dir    = Join-Path $TestDrive 'evo-save6'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $result = Save-EvolutionRecord -Phase 'Verify' -StorePath $dir
        Test-Path $result.FilePath | Should -Be $true
    }
}

Describe 'Get-EvolutionHistory' {

    It 'returns empty array when directory does not exist' {
        $result = Get-EvolutionHistory -StorePath (Join-Path $TestDrive 'evo-nodir')
        @($result).Count | Should -Be 0
    }

    It 'returns empty array when directory is empty' {
        $dir = Join-Path $TestDrive 'evo-empty'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $result = Get-EvolutionHistory -StorePath $dir
        @($result).Count | Should -Be 0
    }

    It 'returns one record after one Save' {
        $dir = Join-Path $TestDrive 'evo-hist1'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Monitor' -StorePath $dir
        $result = Get-EvolutionHistory -StorePath $dir
        @($result).Count | Should -Be 1
    }

    It 'filters by Phase correctly' {
        $dir = Join-Path $TestDrive 'evo-hist2'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Build'   -StorePath $dir
        $null = Save-EvolutionRecord -Phase 'Verify'  -StorePath $dir
        $result = Get-EvolutionHistory -StorePath $dir -Phase 'Build'
        @($result).Count | Should -Be 1
        $result[0].phase | Should -Be 'Build'
    }

    It 'respects the Last limit' {
        $dir = Join-Path $TestDrive 'evo-hist3'
        New-Item -ItemType Directory -Path $dir | Out-Null
        1..5 | ForEach-Object { $null = Save-EvolutionRecord -Phase 'Monitor' -StorePath $dir }
        $result = Get-EvolutionHistory -StorePath $dir -Last 3
        @($result).Count | Should -Be 3
    }
}

Describe 'Get-FrequentLesson' {

    It 'returns empty array when no history exists' {
        $result = Get-FrequentLesson -StorePath (Join-Path $TestDrive 'evo-fl-nodir')
        @($result).Count | Should -Be 0
    }

    It 'returns lesson with highest count first' {
        $dir = Join-Path $TestDrive 'evo-fl1'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Monitor' `
            -Lessons @('Write tests', 'Keep PR small') -StorePath $dir
        $null = Save-EvolutionRecord -Phase 'Verify' `
            -Lessons @('Write tests') -StorePath $dir
        $result = Get-FrequentLesson -StorePath $dir -TopN 5
        $result[0].Lesson | Should -Be 'Write tests'
        $result[0].Count  | Should -Be 2
    }

    It 'Lesson objects have Lesson and Count properties' {
        $dir = Join-Path $TestDrive 'evo-fl2'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = Save-EvolutionRecord -Phase 'Build' `
            -Lessons @('Keep it simple') -StorePath $dir
        $result = Get-FrequentLesson -StorePath $dir
        $result[0].PSObject.Properties.Name | Should -Contain 'Lesson'
        $result[0].PSObject.Properties.Name | Should -Contain 'Count'
    }

    It 'respects TopN limit' {
        $dir = Join-Path $TestDrive 'evo-fl3'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $lessons = 'A', 'B', 'C', 'D', 'E'
        $null = Save-EvolutionRecord -Phase 'Improve' -Lessons $lessons -StorePath $dir
        $result = Get-FrequentLesson -StorePath $dir -TopN 3
        @($result).Count | Should -BeLessOrEqual 3
    }
}
