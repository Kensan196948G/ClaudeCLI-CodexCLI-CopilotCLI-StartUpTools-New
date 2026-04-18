# ============================================================
# SSHHelper.Tests.ps1 - SSHHelper.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\scripts\lib\SSHHelper.psm1" -Force -DisableNameChecking
}

Describe 'ConvertTo-EscapedSSHArgument' {

    Context '通常の文字列の場合' {

        It 'シングルクォートで囲まれること' {
            $result = ConvertTo-EscapedSSHArgument -Value 'hello'
            $result | Should -Be "'hello'"
        }

        It '空文字列を渡すと例外をスローすること（Mandatory パラメータのため）' {
            { ConvertTo-EscapedSSHArgument -Value '' } | Should -Throw
        }

        It 'スペースを含む文字列を正しくエスケープすること' {
            $result = ConvertTo-EscapedSSHArgument -Value 'hello world'
            $result | Should -Be "'hello world'"
        }
    }

    Context 'シングルクォートを含む文字列の場合' {

        It "シングルクォートが '\''  にエスケープされること" {
            $result = ConvertTo-EscapedSSHArgument -Value "hello 'world'"
            # 期待値: 'hello '\''world'\'''
            $result | Should -Be "'hello '\''world'\'''"
        }

        It '先頭のシングルクォートが正しくエスケープされること' {
            $result = ConvertTo-EscapedSSHArgument -Value "'test"
            $result | Should -Be "''\''test'"
        }

        It '複数のシングルクォートがすべてエスケープされること' {
            $result = ConvertTo-EscapedSSHArgument -Value "it's a 'test'"
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Be "'it'\''s a '\''test'\'''"
        }
    }

    Context '特殊文字を含む文字列の場合' {

        It 'ダブルクォートはエスケープされないこと' {
            $result = ConvertTo-EscapedSSHArgument -Value 'say "hello"'
            $result | Should -Be "'say `"hello`"'"
        }

        It 'バックスラッシュはエスケープされないこと' {
            $result = ConvertTo-EscapedSSHArgument -Value 'C:\Users\test'
            $result | Should -Be "'C:\Users\test'"
        }

        It 'ドル記号はエスケープされないこと' {
            $result = ConvertTo-EscapedSSHArgument -Value '$HOME'
            $result | Should -Be "'`$HOME'"
        }
    }
}

Describe 'Test-SSHConnection' {

    Context 'SSH 接続が成功する場合' {

        It '$true を返すこと' {
            Mock -CommandName 'ssh' -MockWith {
                $global:LASTEXITCODE = 0
                return 'OK'
            } -ModuleName 'SSHHelper'

            $result = Test-SSHConnection -Host 'testhost'
            $result | Should -Be $true
        }
    }

    Context 'SSH 接続が失敗する場合' {

        It 'ssh が非ゼロ終了コードを返す場合に $false を返すこと' {
            Mock -CommandName 'ssh' -MockWith {
                $global:LASTEXITCODE = 255
                return 'Connection refused'
            } -ModuleName 'SSHHelper'

            $result = Test-SSHConnection -Host 'badhost'
            $result | Should -Be $false
        }

        It 'ssh が OK を返さない場合に $false を返すこと' {
            Mock -CommandName 'ssh' -MockWith {
                $global:LASTEXITCODE = 0
                return 'FAIL'
            } -ModuleName 'SSHHelper'

            $result = Test-SSHConnection -Host 'testhost'
            $result | Should -Be $false
        }
    }
}

Describe 'Invoke-SSHBatch' {

    Context 'SSH バッチ実行の場合' {

        It '正常終了コードを返すこと' {
            Mock -CommandName 'ssh' -MockWith {
                $global:LASTEXITCODE = 0
            } -ModuleName 'SSHHelper'

            $result = Invoke-SSHBatch -Host 'testhost' -Script "echo 'hello'"
            $result | Should -Be 0
        }
    }
}
