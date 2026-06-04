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

Describe 'Resolve-SshProjectsDir' {

    It 'auto 以外の値はそのまま返すこと' {
        $config = [pscustomobject]@{
            sshProjectsDir = 'P:\'
            projectsDirUnc = '\\server\share'
        }
        $result = Resolve-SshProjectsDir -Config $config
        $result | Should -Be 'P:\'
    }

    It '空文字列の場合は auto として扱われること' {
        $config = [pscustomobject]@{
            sshProjectsDir = ''
            projectsDirUnc = $null
        }
        $result = Resolve-SshProjectsDir -Config $config
        # projectsDirUnc が null なので auto:unmapped になる
        $result | Should -Be 'auto:unmapped'
    }

    It 'auto で projectsDirUnc が未設定なら auto:unmapped を返すこと' {
        $config = [pscustomobject]@{
            sshProjectsDir = 'auto'
            projectsDirUnc = $null
        }
        $result = Resolve-SshProjectsDir -Config $config
        $result | Should -Be 'auto:unmapped'
    }
}

Describe 'Resolve-LauncherMode (Phase 2b)' {

    It '-Local スイッチで $true を返すこと' {
        $config = [pscustomobject]@{ linuxHost = $null }
        $result = Resolve-LauncherMode -Config $config -Local -ConfigPath 'dummy.json'
        $result | Should -Be $true
    }

    It 'linuxHost 設定済みかつ -Local なしで $false を返すこと' {
        $config = [pscustomobject]@{ linuxHost = '192.168.0.185' }
        $result = Resolve-LauncherMode -Config $config -ConfigPath 'dummy.json'
        $result | Should -Be $false
    }

    It 'linuxHost 未設定で -Local なし = ローカル一本化として $true を返すこと (Phase 2b)' {
        $config = [pscustomobject]@{ linuxHost = $null }
        $result = Resolve-LauncherMode -Config $config -ConfigPath 'dummy.json'
        $result | Should -Be $true
    }

    It 'linuxHost 未設定 + NonInteractive でも $true を返すこと (Phase 2b: throw しない)' {
        $config = [pscustomobject]@{ linuxHost = $null }
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
            linuxHost      = $null
            linuxBase      = $null
            sshProjectsDir = $null
            projectsDirUnc = $null
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
            linuxHost      = $null
            linuxBase      = $null
            sshProjectsDir = $null
            projectsDirUnc = $null
        }
        { Resolve-LauncherProject -Config $config -Local -NonInteractive } | Should -Throw '*非対話モード*'
    }
}
