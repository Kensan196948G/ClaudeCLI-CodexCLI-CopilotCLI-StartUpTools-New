# ============================================================
# LauncherCommon.Tests.ps1 - LauncherCommon.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\LauncherCommon.psm1" -Force -DisableNameChecking
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
