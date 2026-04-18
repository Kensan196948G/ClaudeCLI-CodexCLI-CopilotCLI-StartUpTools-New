# ============================================================
# TemplateSyncManager.Tests.ps1 - TemplateSyncManager.ps1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibPath  = Join-Path $script:RepoRoot 'scripts\lib'
    . (Join-Path $script:LibPath 'TemplateSyncManager.ps1')
}

Describe 'Sync-ProjectTemplate' {

    Context 'テンプレートファイルが存在しない場合' {

        It '何もせずターゲットを作成しないこと' {
            $target = Join-Path $TestDrive 'output_missing.txt'
            Sync-ProjectTemplate -TemplatePath 'C:\nonexistent\file_xyz.txt' -TargetPath $target -Label 'test'
            Test-Path $target | Should -BeFalse
        }
    }

    Context 'ターゲットが存在しない場合' {

        BeforeAll {
            $script:TplNew = Join-Path $TestDrive 'tpl_new.txt'
            Set-Content -Path $script:TplNew -Value 'hello' -Encoding UTF8
        }

        It 'ファイルをコピーすること' {
            $target = Join-Path $TestDrive 'output_new.txt'
            Sync-ProjectTemplate -TemplatePath $script:TplNew -TargetPath $target -Label 'test'
            Test-Path $target | Should -BeTrue
            Get-Content $target -Raw | Should -Match 'hello'
        }
    }

    Context 'ターゲットが存在して内容が同じ場合' {

        BeforeAll {
            $script:TplSame = Join-Path $TestDrive 'tpl_same.txt'
            $script:TgtSame = Join-Path $TestDrive 'tgt_same.txt'
            Set-Content -Path $script:TplSame -Value 'same content' -Encoding UTF8
            Set-Content -Path $script:TgtSame -Value 'same content' -Encoding UTF8
        }

        It 'ターゲット内容が変わらないこと (コピースキップ)' {
            Sync-ProjectTemplate -TemplatePath $script:TplSame -TargetPath $script:TgtSame -Label 'test'
            Get-Content $script:TgtSame -Raw | Should -Match 'same content'
        }
    }

    Context 'ターゲットが存在して内容が異なる場合' {

        BeforeAll {
            $script:TplDiff = Join-Path $TestDrive 'tpl_diff.txt'
            $script:TgtDiff = Join-Path $TestDrive 'tgt_diff.txt'
            Set-Content -Path $script:TplDiff -Value 'new content' -Encoding UTF8
            Set-Content -Path $script:TgtDiff -Value 'old content' -Encoding UTF8
        }

        It 'ターゲットを新しい内容に更新すること' {
            Sync-ProjectTemplate -TemplatePath $script:TplDiff -TargetPath $script:TgtDiff -Label 'test'
            Get-Content $script:TgtDiff -Raw | Should -Match 'new content'
        }
    }

    Context 'EnsureParentDirectory スイッチが有効な場合' {

        BeforeAll {
            $script:TplParent = Join-Path $TestDrive 'tpl_parent.txt'
            Set-Content -Path $script:TplParent -Value 'content' -Encoding UTF8
        }

        It '存在しない親ディレクトリを作成してコピーすること' {
            $target = Join-Path $TestDrive 'newdir_abc\subdir_xyz\output.txt'
            Sync-ProjectTemplate -TemplatePath $script:TplParent -TargetPath $target -Label 'test' -EnsureParentDirectory
            Test-Path $target | Should -BeTrue
        }
    }
}

Describe 'Sync-ProjectDirectory' {

    Context 'ソースディレクトリが存在しない場合' {

        It '何もせずターゲットを作成しないこと' {
            $target = Join-Path $TestDrive 'output_dir_missing'
            Sync-ProjectDirectory -SourceDirectory 'C:\nonexistent\src_xyz' -TargetDirectory $target -Label 'test'
            Test-Path $target | Should -BeFalse
        }
    }

    Context 'ソースにファイルがある場合' {

        BeforeAll {
            $script:SrcDir = Join-Path $TestDrive 'src_dir'
            New-Item -ItemType Directory -Path $script:SrcDir -Force | Out-Null
            Set-Content -Path (Join-Path $script:SrcDir 'file1.txt') -Value 'c1' -Encoding UTF8
            Set-Content -Path (Join-Path $script:SrcDir 'file2.txt') -Value 'c2' -Encoding UTF8
        }

        It 'ターゲットにファイルをコピーすること' {
            $target = Join-Path $TestDrive 'tgt_dir_copy'
            Sync-ProjectDirectory -SourceDirectory $script:SrcDir -TargetDirectory $target -Label 'test'
            Test-Path (Join-Path $target 'file1.txt') | Should -BeTrue
            Test-Path (Join-Path $target 'file2.txt') | Should -BeTrue
        }

        It 'ターゲットディレクトリがなければ作成すること' {
            $target = Join-Path $TestDrive 'new_target_dir_xyz'
            Sync-ProjectDirectory -SourceDirectory $script:SrcDir -TargetDirectory $target -Label 'test'
            Test-Path $target | Should -BeTrue
        }
    }
}

Describe 'Initialize-ProjectTemplate' {

    Context 'テンプレートが存在しない場合' {

        It '何もしないこと' {
            $target = Join-Path $TestDrive 'tgt_init_missing.txt'
            Initialize-ProjectTemplate -TemplatePath 'C:\missing_tpl.txt' -TargetPath $target -Label 'test'
            Test-Path $target | Should -BeFalse
        }
    }

    Context 'ターゲットが既存の場合' {

        BeforeAll {
            $script:TplInit = Join-Path $TestDrive 'tpl_init.txt'
            $script:TgtInit = Join-Path $TestDrive 'tgt_init.txt'
            Set-Content -Path $script:TplInit -Value 'new' -Encoding UTF8
            Set-Content -Path $script:TgtInit -Value 'existing' -Encoding UTF8
        }

        It '既存ターゲットを上書きしないこと' {
            Initialize-ProjectTemplate -TemplatePath $script:TplInit -TargetPath $script:TgtInit -Label 'test'
            Get-Content $script:TgtInit -Raw | Should -Match 'existing'
        }
    }

    Context 'ターゲットが存在しない場合' {

        BeforeAll {
            $script:TplNew2 = Join-Path $TestDrive 'tpl_new2.txt'
            Set-Content -Path $script:TplNew2 -Value 'initial' -Encoding UTF8
        }

        It 'ファイルを初期配置すること' {
            $target = Join-Path $TestDrive 'tgt_new2.txt'
            Initialize-ProjectTemplate -TemplatePath $script:TplNew2 -TargetPath $target -Label 'test'
            Get-Content $target -Raw | Should -Match 'initial'
        }
    }
}

Describe 'Sync-ProjectTemplateDirectory' {

    Context 'テンプレートディレクトリが存在しない場合' {

        It '何もしないこと' {
            $target = Join-Path $TestDrive 'tpldirout_missing'
            Sync-ProjectTemplateDirectory -TemplateDir 'C:\nonexistent\tpldir_xyz' -TargetDir $target
            Test-Path $target | Should -BeFalse
        }
    }

    Context 'テンプレートディレクトリにファイルがある場合' {

        BeforeAll {
            $script:TplDir = Join-Path $TestDrive 'tpldir_src'
            New-Item -ItemType Directory -Path $script:TplDir -Force | Out-Null
            Set-Content -Path (Join-Path $script:TplDir 'a.txt') -Value 'alpha' -Encoding UTF8
            Set-Content -Path (Join-Path $script:TplDir 'b.txt') -Value 'beta'  -Encoding UTF8
        }

        It '各ファイルをターゲットに同期すること' {
            $target = Join-Path $TestDrive 'tpldir_dst'
            Sync-ProjectTemplateDirectory -TemplateDir $script:TplDir -TargetDir $target -Label 'test'
            Test-Path (Join-Path $target 'a.txt') | Should -BeTrue
            Test-Path (Join-Path $target 'b.txt') | Should -BeTrue
        }

        It 'ターゲットディレクトリがなければ作成すること' {
            $target = Join-Path $TestDrive 'tpldir_auto_create'
            Sync-ProjectTemplateDirectory -TemplateDir $script:TplDir -TargetDir $target -Label 'test'
            Test-Path $target | Should -BeTrue
        }
    }
}
