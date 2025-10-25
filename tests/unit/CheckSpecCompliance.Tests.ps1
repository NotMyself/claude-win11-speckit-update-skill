BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "../../.github/scripts/check-spec-compliance.ps1"
    $fixturesPath = Join-Path $PSScriptRoot "../fixtures/spec-structures"
}

Describe "check-spec-compliance" {
    Context "When branch is not a feature branch" {
        It "Should skip validation for non-feature branches" {
            # Arrange
            $testRoot = Join-Path $TestDrive "spec-test"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "bugfix/some-fix" | ConvertFrom-Json

            # Assert
            $result.status | Should -Be 'pass'
            $result.findings.Count | Should -Be 0
            $result.metadata.reason | Should -Match "Not a feature branch"
        }
    }

    Context "When validating spec directory" {
        It "Should detect missing spec directory" {
            # Arrange
            $testRoot = Join-Path $TestDrive "spec-test2"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            $specsDir = Join-Path $testRoot "specs"
            New-Item -ItemType Directory -Path $specsDir -Force | Out-Null

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "014-test-feature" | ConvertFrom-Json

            # Assert
            $result.status | Should -Be 'failed'
            $result.findings.Count | Should -BeGreaterThan 0
            $result.findings[0].rule | Should -Be 'missing-spec-directory'
        }

        It "Should detect missing spec artifacts" {
            # Arrange
            $testRoot = $fixturesPath
            $branchName = "001-test"

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName $branchName | ConvertFrom-Json

            # Assert
            # The fixture doesn't have a 001- directory, so should error
            $result.status | Should -BeIn @('failed', 'warning')
        }

        It "Should validate spec.md sections" {
            # Arrange - use incomplete spec fixture
            $testRoot = Join-Path $TestDrive "spec-test-incomplete"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            $specsDir = Join-Path $testRoot "specs"
            New-Item -ItemType Directory -Path $specsDir -Force | Out-Null
            $specDir = Join-Path $specsDir "015-test-feature"
            New-Item -ItemType Directory -Path $specDir -Force | Out-Null

            # Create incomplete spec.md (missing Success Criteria)
            $specFile = Join-Path $specDir "spec.md"
            @"
# Feature

## User Scenarios

Test

## Requirements

Test
"@ | Set-Content -Path $specFile

            $planFile = Join-Path $specDir "plan.md"
            "# Plan" | Set-Content -Path $planFile

            $tasksFile = Join-Path $specDir "tasks.md"
            "# Tasks" | Set-Content -Path $tasksFile

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "015-test-feature" | ConvertFrom-Json

            # Assert
            $result.findings | Where-Object { $_.rule -eq 'incomplete-spec-artifact' } | Should -Not -BeNullOrEmpty
        }
    }

    Context "When validating CHANGELOG" {
        It "Should warn if CHANGELOG is missing" {
            # Arrange
            $testRoot = Join-Path $TestDrive "spec-test3"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "main" | ConvertFrom-Json

            # Assert
            $changelogFinding = $result.findings | Where-Object { $_.category -eq 'changelog' }
            $changelogFinding | Should -Not -BeNullOrEmpty
        }

        It "Should warn if CHANGELOG missing Unreleased section" {
            # Arrange
            $testRoot = Join-Path $TestDrive "spec-test4"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

            $changelogPath = Join-Path $testRoot "CHANGELOG.md"
            "# Changelog`n`n## [1.0.0]`nInitial release" | Set-Content -Path $changelogPath

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "main" | ConvertFrom-Json

            # Assert
            $unreleasedFinding = $result.findings | Where-Object { $_.rule -eq 'missing-changelog-entry' }
            $unreleasedFinding | Should -Not -BeNullOrEmpty
        }
    }

    Context "When validating constitution compliance" {
        It "Should detect missing Export-ModuleMember" {
            # Arrange
            $testRoot = Join-Path $TestDrive "spec-test5"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            $modulesDir = Join-Path $testRoot "scripts/modules"
            New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null

            $moduleFile = Join-Path $modulesDir "TestModule.psm1"
            @"
function Get-Test {
    Write-Host "Test"
}
"@ | Set-Content -Path $moduleFile

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "main" | ConvertFrom-Json

            # Assert
            $result.findings | Where-Object { $_.rule -eq 'missing-export-modulemember' } | Should -Not -BeNullOrEmpty
        }

        It "Should detect nested Import-Module" {
            # Arrange
            $testRoot = Join-Path $TestDrive "spec-test6"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            $modulesDir = Join-Path $testRoot "scripts/modules"
            New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null

            $moduleFile = Join-Path $modulesDir "BadModule.psm1"
            @"
Import-Module SomeOtherModule

function Get-Test {
    Write-Host "Test"
}

Export-ModuleMember -Function Get-Test
"@ | Set-Content -Path $moduleFile

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "main" | ConvertFrom-Json

            # Assert
            $result.findings | Where-Object { $_.rule -eq 'nested-import-module' } | Should -Not -BeNullOrEmpty
        }
    }

    Context "When validating result structure" {
        It "Should return valid JSON structure" {
            # Arrange
            $testRoot = Join-Path $TestDrive "spec-test7"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

            # Act
            $result = & $scriptPath -RepoRoot $testRoot -BranchName "main" | ConvertFrom-Json

            # Assert
            $result.step | Should -Be 'spec-compliance'
            $result.status | Should -Not -BeNullOrEmpty
            $result.timestamp | Should -Not -BeNullOrEmpty
            $result.findings | Should -Not -BeNull
            $result.summary | Should -Not -BeNull
            $result.metadata | Should -Not -BeNull
        }
    }
}
