# ============================================================
# SelfEvolution.Tests.ps1 - Pester tests for SelfEvolution module
# ============================================================

BeforeAll {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\scripts\lib\SelfEvolution.psm1'
    Import-Module $ModulePath -Force -DisableNameChecking

    $TempEvolutionDir = Join-Path $env:TEMP "evolution-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $TempEvolutionDir -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TempEvolutionDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'SelfEvolution Module' {

    Describe 'Get-EvolutionStorePath' {
        It '存在しないディレクトリを自動作成する' {
            $newDir = Join-Path $env:TEMP "evo-store-$(Get-Random)"
            try {
                $path = Get-EvolutionStorePath -BasePath $newDir
                Test-Path $path | Should -BeTrue
            } finally {
                Remove-Item -Path $newDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It '既存ディレクトリをそのまま返す' {
            $path = Get-EvolutionStorePath -BasePath $TempEvolutionDir
            $path | Should -Be $TempEvolutionDir
        }
    }

    Describe 'Save-EvolutionRecord' {
        It 'レコードをJSONファイルとして保存する' {
            $result = Save-EvolutionRecord `
                -Phase 'Verify' `
                -LoopNumber 1 `
                -Successes @('Test passed') `
                -Failures @() `
                -Lessons @('Keep tests green') `
                -StorePath $TempEvolutionDir

            $result | Should -Not -BeNullOrEmpty
            $result.SessionId | Should -Not -BeNullOrEmpty
            Test-Path $result.FilePath | Should -BeTrue
        }

        It '保存したファイルに正しいデータが含まれる' {
            $result = Save-EvolutionRecord `
                -Phase 'Development' `
                -LoopNumber 2 `
                -Successes @('Feature implemented') `
                -Failures @('CI failed') `
                -Improvements @('Add retry logic') `
                -Lessons @('Test before commit') `
                -KpiSnapshot @{ test_passed = 10; test_failed = 1 } `
                -NextActions @('Fix CI first') `
                -StorePath $TempEvolutionDir

            $data = Get-Content $result.FilePath | ConvertFrom-Json
            $data.phase | Should -Be 'Development'
            $data.loop_number | Should -Be 2
            $data.successes | Should -Contain 'Feature implemented'
            $data.failures | Should -Contain 'CI failed'
            $data.lessons | Should -Contain 'Test before commit'
        }

        It 'Timestamp が正しいフォーマットで保存される' {
            $result = Save-EvolutionRecord -Phase 'Monitor' -StorePath $TempEvolutionDir
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'
        }

        It 'SessionId がユニークである' {
            $result1 = Save-EvolutionRecord -Phase 'Monitor' -StorePath $TempEvolutionDir
            $result2 = Save-EvolutionRecord -Phase 'Monitor' -StorePath $TempEvolutionDir
            $result1.SessionId | Should -Not -Be $result2.SessionId
        }
    }

    Describe 'Get-EvolutionHistory' {
        It '保存済みレコードを取得できる' {
            Save-EvolutionRecord -Phase 'Verify' -LoopNumber 1 -StorePath $TempEvolutionDir
            Save-EvolutionRecord -Phase 'Verify' -LoopNumber 2 -StorePath $TempEvolutionDir

            $history = Get-EvolutionHistory -StorePath $TempEvolutionDir -Last 10
            $history.Count | Should -BeGreaterThan 0
        }

        It 'Last パラメータで取得件数を制限する' {
            1..5 | ForEach-Object {
                Save-EvolutionRecord -Phase 'Monitor' -LoopNumber $_ -StorePath $TempEvolutionDir
            }

            $history = Get-EvolutionHistory -StorePath $TempEvolutionDir -Last 3
            $history.Count | Should -BeLessOrEqual 3
        }

        It 'Phase フィルタが機能する' {
            Save-EvolutionRecord -Phase 'Development' -StorePath $TempEvolutionDir
            Save-EvolutionRecord -Phase 'Improvement' -StorePath $TempEvolutionDir

            $devHistory = Get-EvolutionHistory -StorePath $TempEvolutionDir -Phase 'Development' -Last 20
            foreach ($record in $devHistory) {
                $record.phase | Should -Be 'Development'
            }
        }

        It '存在しないディレクトリでは空配列を返す' {
            $history = Get-EvolutionHistory -StorePath 'C:\nonexistent\evolution\path'
            $history | Should -BeNullOrEmpty
        }
    }

    Describe 'Get-FrequentLesson' {
        It '同じ教訓が複数回出現する場合に上位を返す' {
            $lesson = 'Always run tests before commit'
            1..3 | ForEach-Object {
                Save-EvolutionRecord -Phase 'Verify' -Lessons @($lesson) -StorePath $TempEvolutionDir
            }

            $lessons = Get-FrequentLesson -StorePath $TempEvolutionDir -TopN 5
            $found = $lessons | Where-Object { $_.Lesson -eq $lesson }
            $found | Should -Not -BeNullOrEmpty
            $found.Count | Should -BeGreaterOrEqual 3
        }

        It 'TopN で件数を制限する' {
            $lessons = Get-FrequentLesson -StorePath $TempEvolutionDir -TopN 2
            $lessons.Count | Should -BeLessOrEqual 2
        }
    }

    Describe 'Invoke-SelfEvolutionCycle' {
        It 'Evolution Cycle を実行して結果を返す' {
            $result = Invoke-SelfEvolutionCycle `
                -Phase 'Verify' `
                -LoopNumber 1 `
                -CompletedTasks @('Implement feature', 'Write tests') `
                -BlockedTasks @() `
                -TestResults @{ Passed = 10; Failed = 0 } `
                -CiResults @{ Status = 'SUCCESS' } `
                -StorePath $TempEvolutionDir

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Successes'
            $result.PSObject.Properties.Name | Should -Contain 'Failures'
            $result.PSObject.Properties.Name | Should -Contain 'NextActions'
            $result.PSObject.Properties.Name | Should -Contain 'Passed'
        }

        It 'テスト全成功時はPassedがTrueになる' {
            $result = Invoke-SelfEvolutionCycle `
                -Phase 'Development' `
                -CompletedTasks @('Task done') `
                -BlockedTasks @() `
                -TestResults @{ Passed = 5; Failed = 0 } `
                -CiResults @{ Status = 'SUCCESS' } `
                -StorePath $TempEvolutionDir

            $result.Passed | Should -BeTrue
        }

        It 'ブロックタスクがある場合はFailuresにエントリが追加される' {
            $result = Invoke-SelfEvolutionCycle `
                -Phase 'Development' `
                -BlockedTasks @('Blocked feature X') `
                -StorePath $TempEvolutionDir

            $result.Failures.Count | Should -BeGreaterThan 0
        }

        It 'CI失敗時はFailuresにCI失敗エントリが追加される' {
            $result = Invoke-SelfEvolutionCycle `
                -Phase 'Verify' `
                -CiResults @{ Status = 'FAILURE' } `
                -StorePath $TempEvolutionDir

            $ciFailure = $result.Failures | Where-Object { $_ -match 'CI' }
            $ciFailure | Should -Not -BeNullOrEmpty
        }

        It 'NextActions が空でない' {
            $result = Invoke-SelfEvolutionCycle `
                -Phase 'Monitor' `
                -StorePath $TempEvolutionDir

            $result.NextActions.Count | Should -BeGreaterThan 0
        }

        It 'KpiSnapshot にloop_number が含まれる' {
            $result = Invoke-SelfEvolutionCycle `
                -Phase 'Improvement' `
                -LoopNumber 3 `
                -StorePath $TempEvolutionDir

            $result.KpiSnapshot['loop_number'] | Should -Be 3
        }
    }

    Describe 'Show-EvolutionSummary' {
        It '履歴がある場合にサマリーを表示する' {
            Save-EvolutionRecord -Phase 'Monitor' -StorePath $TempEvolutionDir
            { Show-EvolutionSummary -StorePath $TempEvolutionDir -Last 5 } | Should -Not -Throw
        }

        It '空の履歴でも例外を投げない' {
            $emptyDir = Join-Path $env:TEMP "evo-empty-$(Get-Random)"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
            try {
                { Show-EvolutionSummary -StorePath $emptyDir } | Should -Not -Throw
            } finally {
                Remove-Item -Path $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
