# ============================================================
# LauncherCommon.Tests.ps1 - LauncherCommon.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\scripts\lib\LauncherCommon.psm1" -Force -DisableNameChecking
}

Describe 'Find-AvailableDriveLetter' {

    It '使用中のドライブレターを返さないこと' {
        $usedLetters = @((Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Name)
        $result = Find-AvailableDriveLetter
        if ($result) {
            $result | Should -Not -BeIn $usedLetters
        }
    }

    It 'PreferredLetters の優先順で返すこと' {
        $usedLetters = @((Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Name)
        $preferred = @('P', 'Q', 'R')
        $result = Find-AvailableDriveLetter -PreferredLetters $preferred

        if ($result) {
            # The result should be the first preferred letter that is not used
            $expectedFirst = $preferred | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
            $result | Should -Be $expectedFirst
        }
    }

    It 'ExcludeLetters で除外できること' {
        $result = Find-AvailableDriveLetter -PreferredLetters @('P', 'Q') -ExcludeLetters @('P')
        if ($result) {
            $result | Should -Not -Be 'P'
        }
    }

    It '単一文字の文字列を返すこと' {
        $result = Find-AvailableDriveLetter
        if ($result) {
            $result.Length | Should -Be 1
            $result | Should -Match '^[A-Z]$'
        }
    }
}


Describe 'Resolve-LauncherMode (Phase 2b)' {

    It '-Local スイッチで $true を返すこと' {
        $config = [pscustomobject]@{}
        $result = Resolve-LauncherMode -Config $config -Local -ConfigPath 'dummy.json'
        $result | Should -Be $true
    }

    It 'SSH 設定なしでも常にローカルとして $true を返すこと' {
        $config = [pscustomobject]@{}
        $result = Resolve-LauncherMode -Config $config -ConfigPath 'dummy.json'
        $result | Should -Be $true
    }

    It '-Local なし = ローカル一本化として $true を返すこと (Phase 2b)' {
        $config = [pscustomobject]@{}
        $result = Resolve-LauncherMode -Config $config -ConfigPath 'dummy.json'
        $result | Should -Be $true
    }

    It 'NonInteractive でも $true を返すこと (Phase 2b: throw しない)' {
        $config = [pscustomobject]@{}
        { $result = Resolve-LauncherMode -Config $config -NonInteractive -ConfigPath 'dummy.json' } |
            Should -Not -Throw
        $result = Resolve-LauncherMode -Config $config -NonInteractive -ConfigPath 'dummy.json'
        $result | Should -Be $true
    }
}

Describe 'Resolve-LauncherProject (Phase 2b)' {

    It '-Project 引数が指定されたらそのまま返すこと' {
        $config = [pscustomobject]@{ projectsDir = $null; localExcludes = $null }
        $result = Resolve-LauncherProject -Config $config -Project 'MyApp'
        $result | Should -Be 'MyApp'
    }

    It 'projectsDir が存在すれば -Local なしでもローカル優先でプロジェクト一覧を使うこと (Phase 2b)' {
        $projRoot = Join-Path $TestDrive 'projects-phase2b'
        New-Item -ItemType Directory -Path (Join-Path $projRoot 'AppA') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $projRoot 'AppB') -Force | Out-Null
        $config = [pscustomobject]@{
            projectsDir    = $projRoot
            localExcludes  = $null
        }
        # -NonInteractive なので、プロジェクトが見つかっても選択不要でエラーになる（正常動作確認）
        { Resolve-LauncherProject -Config $config -NonInteractive } | Should -Throw '*非対話モード*'
    }

    It 'projectsDir が存在し localExcludes を使えること' {
        $projRoot = Join-Path $TestDrive 'projects-excludes'
        New-Item -ItemType Directory -Path (Join-Path $projRoot 'Keep') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $projRoot 'Skip') -Force | Out-Null
        $config = [pscustomobject]@{
            projectsDir    = $projRoot
            localExcludes  = @('Skip')
        }
        { Resolve-LauncherProject -Config $config -Local -NonInteractive } | Should -Throw '*非対話モード*'
    }
}
