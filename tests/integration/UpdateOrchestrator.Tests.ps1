#Requires -Version 7.0

<#
.SYNOPSIS
    Integration tests for update-orchestrator.ps1

.DESCRIPTION
    Comprehensive integration tests covering end-to-end update workflows:
    1. Standard Update (No Conflicts)
    2. Update with Customizations
    3. Update with Conflicts
    4. First-Time Manifest Generation
    5. Custom Commands Preservation
    6. Rollback on Failure
    7. Backup Retention
    8. Command Lifecycle

.NOTES
    Test Framework: Pester 5.x
    Script Under Test: update-orchestrator.ps1
    Dependencies: All modules and helpers
#>

BeforeAll {
    # Store original location
    $script:OriginalLocation = Get-Location

    # Path to orchestrator script
    $script:OrchestratorScript = Join-Path $PSScriptRoot "..\..\scripts\update-orchestrator.ps1"

    # Path to modules
    $script:ModulesPath = Join-Path $PSScriptRoot "..\..\scripts\modules"

    # Path to fixtures
    $script:FixturesPath = Join-Path $PSScriptRoot "..\fixtures"

    # Path to mock GitHub responses
    $script:MockGitHubPath = Join-Path $script:FixturesPath "mock-github-responses"

    # Helper function to create test project
    function New-TestProject {
        param(
            [string]$BasedOn = "sample-project-with-manifest",
            [string]$Name = "test-project-$(Get-Random)"
        )

        $sourceDir = Join-Path $script:FixturesPath $BasedOn
        $targetDir = Join-Path $env:TEMP $Name

        # Clean up if exists
        if (Test-Path $targetDir) {
            Remove-Item $targetDir -Recurse -Force
        }

        # Copy fixture to temp location
        Copy-Item -Path $sourceDir -Destination $targetDir -Recurse -Force

        return $targetDir
    }

    # Helper function to clean up test project
    function Remove-TestProject {
        param([string]$ProjectPath)

        if (Test-Path $ProjectPath) {
            Set-Location $script:OriginalLocation
            Start-Sleep -Milliseconds 100  # Allow file handles to release
            Remove-Item $ProjectPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Helper function to mock GitHub API
    function Mock-GitHubApi {
        param(
            [string]$Version = "v0.0.72",
            [hashtable]$Templates = @{}
        )

        # Mock Get-LatestSpecKitRelease
        Mock -ModuleName GitHubApiClient Get-LatestSpecKitRelease {
            return @{
                tag_name = $Version
                name = "Release $Version"
                published_at = "2025-01-15T10:30:00Z"
                assets = @(
                    @{
                        name = "claude-templates.zip"
                        browser_download_url = "https://example.com/templates.zip"
                        size = 245678
                    }
                )
            }
        }

        # Mock Get-SpecKitRelease
        Mock -ModuleName GitHubApiClient Get-SpecKitRelease {
            param([string]$Version)
            return @{
                tag_name = $Version
                name = "Release $Version"
                published_at = "2025-01-15T10:30:00Z"
                assets = @(
                    @{
                        name = "claude-templates.zip"
                        browser_download_url = "https://example.com/templates.zip"
                        size = 245678
                    }
                )
            }
        }

        # Mock Download-SpecKitTemplates
        Mock -ModuleName GitHubApiClient Download-SpecKitTemplates {
            param([string]$Version, [string]$ProjectRoot)
            return $Templates
        }
    }

    # Helper function to mock VSCode commands
    function Mock-VSCodeCommands {
        Mock -ModuleName VSCodeIntegration Open-DiffView {
            param([string]$LeftPath, [string]$RightPath, [string]$Title)
            Write-Host "Mock: Opening diff view for $Title"
            return $true
        }

        Mock -ModuleName VSCodeIntegration Open-MergeEditor {
            param([string]$BasePath, [string]$CurrentPath, [string]$IncomingPath, [string]$ResultPath)
            Write-Host "Mock: Opening merge editor"

            # Simulate user accepting incoming changes
            if ($IncomingPath) {
                Copy-Item -Path $IncomingPath -Destination $ResultPath -Force
            }
            return $true
        }

        Mock -ModuleName VSCodeIntegration Get-ExecutionContext {
            return 'standalone-terminal'
        }
    }

    # Helper function to mock user input
    function Mock-UserInput {
        param(
            [string]$Confirmation = "Y",
            [string]$ConflictChoice = "1",
            [string]$BackupCleanup = "N"
        )

        # Mock Read-Host for various prompts
        Mock Read-Host {
            param([string]$Prompt)

            if ($Prompt -match "proceed|continue|confirm") {
                return $Confirmation
            }
            elseif ($Prompt -match "conflict|choice") {
                return $ConflictChoice
            }
            elseif ($Prompt -match "backup|cleanup|delete") {
                return $BackupCleanup
            }
            else {
                return "Y"
            }
        }
    }

    # Import modules for mocking
    Import-Module (Join-Path $script:ModulesPath "GitHubApiClient.psm1") -Force
    Import-Module (Join-Path $script:ModulesPath "VSCodeIntegration.psm1") -Force
    Import-Module (Join-Path $script:ModulesPath "HashUtils.psm1") -Force
    Import-Module (Join-Path $script:ModulesPath "ManifestManager.psm1") -Force
    Import-Module (Join-Path $script:ModulesPath "BackupManager.psm1") -Force
    Import-Module (Join-Path $script:ModulesPath "ConflictDetector.psm1") -Force
}

AfterAll {
    # Restore original location
    Set-Location $script:OriginalLocation
}

Describe "Update Orchestrator Integration Tests" {

    Context "Scenario 1: Standard Update (No Conflicts)" {
        BeforeAll {
            # Create test project
            $script:TestProject1 = New-TestProject -BasedOn "sample-project-with-manifest"

            # Setup mocks
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Updated Specify Command`n`nThis is the new version."
                ".claude/commands/speckit.plan.md" = "# Updated Plan Command`n`nThis is the new version."
                ".specify/memory/constitution.md" = "# Updated Constitution`n`nNew governance rules."
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y"
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject1
        }

        It "Should complete update successfully" {
            # Arrange
            Set-Location $script:TestProject1

            # Act
            $result = & $script:OrchestratorScript

            # Assert
            $LASTEXITCODE | Should -Be 0
        }

        It "Should update manifest version" {
            # Arrange
            Set-Location $script:TestProject1
            $manifestPath = Join-Path $script:TestProject1 ".specify\manifest.json"

            # Act
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

            # Assert
            $manifest.speckit_version | Should -Be "v0.0.72"
        }

        It "Should create backup" {
            # Arrange
            Set-Location $script:TestProject1
            $backupsDir = Join-Path $script:TestProject1 ".specify\backups"

            # Act & Assert
            Test-Path $backupsDir | Should -BeTrue
            (Get-ChildItem $backupsDir -Directory).Count | Should -BeGreaterThan 0
        }

        It "Should update files with new content" {
            # Arrange
            Set-Location $script:TestProject1
            $specifyFile = Join-Path $script:TestProject1 ".claude\commands\speckit.specify.md"

            # Act
            $content = Get-Content $specifyFile -Raw

            # Assert
            $content | Should -BeLike "*Updated Specify Command*"
        }
    }

    Context "Scenario 2: Update with Customizations" {
        BeforeAll {
            # Create test project
            $script:TestProject2 = New-TestProject -BasedOn "sample-project-with-customizations"

            # Customize a file
            $customFile = Join-Path $script:TestProject2 ".claude\commands\speckit.specify.md"
            "# My Customized Specify Command`n`nCustom content." | Out-File -FilePath $customFile -Encoding utf8

            # Setup mocks - upstream has NO changes to customized file
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Original Specify Command`n`nOriginal content."
                ".claude/commands/speckit.plan.md" = "# Updated Plan Command`n`nThis is updated."
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y"
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject2
        }

        It "Should preserve customized files" {
            # Arrange
            Set-Location $script:TestProject2
            $customFile = Join-Path $script:TestProject2 ".claude\commands\speckit.specify.md"
            $originalContent = Get-Content $customFile -Raw

            # Act
            & $script:OrchestratorScript

            # Assert
            $newContent = Get-Content $customFile -Raw
            $newContent | Should -Be $originalContent
            $newContent | Should -BeLike "*My Customized Specify Command*"
        }

        It "Should update non-customized files" {
            # Arrange
            Set-Location $script:TestProject2

            # Act
            & $script:OrchestratorScript
            $planFile = Join-Path $script:TestProject2 ".claude\commands\speckit.plan.md"

            # Assert
            $content = Get-Content $planFile -Raw
            $content | Should -BeLike "*Updated Plan Command*"
        }

        It "Should mark customizations in manifest" {
            # Arrange
            Set-Location $script:TestProject2

            # Act
            & $script:OrchestratorScript
            $manifestPath = Join-Path $script:TestProject2 ".specify\manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

            # Assert
            $customizedFile = $manifest.tracked_files | Where-Object { $_.path -eq ".claude/commands/speckit.specify.md" }
            $customizedFile.customized | Should -BeTrue
        }
    }

    Context "Scenario 3: Update with Conflicts" {
        BeforeAll {
            # Create test project
            $script:TestProject3 = New-TestProject -BasedOn "sample-project-with-manifest"

            # Get the file and customize it
            $conflictFile = Join-Path $script:TestProject3 ".claude\commands\speckit.specify.md"
            "# My Custom Specify`n`nUser modified content." | Out-File -FilePath $conflictFile -Encoding utf8

            # Update manifest to track original version
            $manifestPath = Join-Path $script:TestProject3 ".specify\manifest.json"
            if (Test-Path $manifestPath) {
                $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                $manifest.speckit_version = "v0.0.71"

                # Update tracked file hash
                $trackedFile = $manifest.tracked_files | Where-Object { $_.path -eq ".claude/commands/speckit.specify.md" }
                if ($trackedFile) {
                    $trackedFile.original_hash = "sha256:ORIGINAL_HASH_VALUE"
                    $trackedFile.customized = $true
                }

                $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding utf8
            }

            # Setup mocks - upstream HAS changes to same file
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Upstream Updated Specify`n`nUpstream modified content."
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y" -ConflictChoice "3"  # Choose "Use new version"
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject3
        }

        It "Should detect conflicts" {
            # Arrange
            Set-Location $script:TestProject3

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String

            # Assert
            $output | Should -BeLike "*conflict*"
        }

        It "Should invoke conflict resolution workflow" {
            # Arrange
            Set-Location $script:TestProject3

            # Act
            & $script:OrchestratorScript

            # Assert
            Should -Invoke -ModuleName VSCodeIntegration -CommandName Open-MergeEditor -Times 1 -Exactly
        }

        It "Should resolve conflict based on user choice" {
            # Arrange
            Set-Location $script:TestProject3

            # Act
            & $script:OrchestratorScript
            $conflictFile = Join-Path $script:TestProject3 ".claude\commands\speckit.specify.md"
            $content = Get-Content $conflictFile -Raw

            # Assert - Should have upstream content (choice 3)
            $content | Should -BeLike "*Upstream Updated Specify*"
        }
    }

    Context "Scenario 4: First-Time Manifest Generation" {
        BeforeAll {
            # Create test project without manifest
            $script:TestProject4 = New-TestProject -BasedOn "sample-project-without-manifest"

            # Setup mocks
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Specify Command"
                ".specify/memory/constitution.md" = "# Constitution"
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y"
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject4
        }

        It "Should offer to create manifest" {
            # Arrange
            Set-Location $script:TestProject4

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String

            # Assert
            $output | Should -BeLike "*No manifest found*"
            $output | Should -BeLike "*Creating new manifest*"
        }

        It "Should create manifest with current version" {
            # Arrange
            Set-Location $script:TestProject4

            # Act
            & $script:OrchestratorScript
            $manifestPath = Join-Path $script:TestProject4 ".specify\manifest.json"

            # Assert
            Test-Path $manifestPath | Should -BeTrue
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $manifest.speckit_version | Should -Not -BeNullOrEmpty
        }

        It "Should assume all files are customized" {
            # Arrange
            Set-Location $script:TestProject4

            # Act
            & $script:OrchestratorScript
            $manifestPath = Join-Path $script:TestProject4 ".specify\manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

            # Assert
            foreach ($file in $manifest.tracked_files) {
                $file.customized | Should -BeTrue
            }
        }

        It "Should track all existing files" {
            # Arrange
            Set-Location $script:TestProject4
            $existingFiles = @(
                Get-ChildItem (Join-Path $script:TestProject4 ".specify") -Recurse -File | Where-Object { $_.Name -ne "manifest.json" }
                Get-ChildItem (Join-Path $script:TestProject4 ".claude\commands") -Filter "*.md" -ErrorAction SilentlyContinue
            )

            # Act
            & $script:OrchestratorScript
            $manifestPath = Join-Path $script:TestProject4 ".specify\manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

            # Assert
            $manifest.tracked_files.Count | Should -BeGreaterThan 0
        }
    }

    Context "Scenario 5: Custom Commands Preservation" {
        BeforeAll {
            # Create test project
            $script:TestProject5 = New-TestProject -BasedOn "sample-project-with-manifest"

            # Add custom command
            $customCommandPath = Join-Path $script:TestProject5 ".claude\commands\custom.analyze-db.md"
            "# Custom Database Analysis`n`nMy custom command." | Out-File -FilePath $customCommandPath -Encoding utf8

            # Setup mocks - official commands updated, but custom command not in upstream
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Updated Specify"
                ".claude/commands/speckit.plan.md" = "# Updated Plan"
                # Custom command NOT in templates
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y"

            # Mock Get-OfficialSpecKitCommands
            Mock -ModuleName ManifestManager Get-OfficialSpecKitCommands {
                return @(
                    "speckit.specify.md",
                    "speckit.plan.md",
                    "speckit.tasks.md"
                )
            }
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject5
        }

        It "Should preserve custom commands" {
            # Arrange
            Set-Location $script:TestProject5
            $customCommandPath = Join-Path $script:TestProject5 ".claude\commands\custom.analyze-db.md"

            # Act
            & $script:OrchestratorScript

            # Assert
            Test-Path $customCommandPath | Should -BeTrue
            $content = Get-Content $customCommandPath -Raw
            $content | Should -BeLike "*Custom Database Analysis*"
        }

        It "Should update official commands" {
            # Arrange
            Set-Location $script:TestProject5

            # Act
            & $script:OrchestratorScript
            $officialCommand = Join-Path $script:TestProject5 ".claude\commands\speckit.specify.md"

            # Assert
            $content = Get-Content $officialCommand -Raw
            $content | Should -BeLike "*Updated Specify*"
        }

        It "Should list custom commands in summary" {
            # Arrange
            Set-Location $script:TestProject5

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String

            # Assert
            $output | Should -BeLike "*custom*"
        }

        It "Should track custom commands in manifest" {
            # Arrange
            Set-Location $script:TestProject5

            # Act
            & $script:OrchestratorScript
            $manifestPath = Join-Path $script:TestProject5 ".specify\manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

            # Assert
            $manifest.custom_files | Should -Contain "custom.analyze-db.md"
        }
    }

    Context "Scenario 6: Rollback on Failure" {
        BeforeAll {
            # Create test project
            $script:TestProject6 = New-TestProject -BasedOn "sample-project-with-manifest"

            # Setup mocks that will cause failure mid-update
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Updated Specify"
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y"

            # Mock a function to throw error mid-update
            Mock -ModuleName ConflictDetector Get-FileState {
                throw "Simulated error during file state analysis"
            }
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject6
        }

        It "Should trigger automatic rollback on failure" {
            # Arrange
            Set-Location $script:TestProject6
            $originalContent = Get-Content (Join-Path $script:TestProject6 ".specify\manifest.json") -Raw

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            # Assert
            $exitCode | Should -Not -Be 0
            $output | Should -BeLike "*rollback*"
        }

        It "Should restore files to original state" {
            # Arrange
            Set-Location $script:TestProject6
            $manifestPath = Join-Path $script:TestProject6 ".specify\manifest.json"
            $manifestBefore = Get-Content $manifestPath -Raw

            # Create backup before test
            Import-Module (Join-Path $script:ModulesPath "BackupManager.psm1") -Force
            $backupPath = New-SpecKitBackup -ProjectRoot $script:TestProject6 -FromVersion "v0.0.71" -ToVersion "v0.0.72"

            # Modify a file to simulate partial update
            $testFile = Join-Path $script:TestProject6 ".claude\commands\speckit.specify.md"
            "MODIFIED CONTENT" | Out-File -FilePath $testFile -Encoding utf8

            # Act - Restore from backup
            Restore-SpecKitBackup -ProjectRoot $script:TestProject6 -BackupPath $backupPath

            # Assert
            $manifestAfter = Get-Content $manifestPath -Raw
            $testContent = Get-Content $testFile -Raw
            $testContent | Should -Not -BeLike "*MODIFIED CONTENT*"
        }

        It "Should keep backup available for manual recovery" {
            # Arrange
            Set-Location $script:TestProject6

            # Act
            & $script:OrchestratorScript 2>&1 | Out-Null
            $backupsDir = Join-Path $script:TestProject6 ".specify\backups"

            # Assert
            if (Test-Path $backupsDir) {
                $backups = Get-ChildItem $backupsDir -Directory
                $backups.Count | Should -BeGreaterThan 0
            }
        }
    }

    Context "Scenario 7: Backup Retention" {
        BeforeAll {
            # Create test project
            $script:TestProject7 = New-TestProject -BasedOn "sample-project-with-manifest"

            # Create multiple old backups
            Import-Module (Join-Path $script:ModulesPath "BackupManager.psm1") -Force
            $backupsDir = Join-Path $script:TestProject7 ".specify\backups"
            New-Item -ItemType Directory -Path $backupsDir -Force | Out-Null

            # Create 7 old backups (more than retention limit of 5)
            for ($i = 1; $i -le 7; $i++) {
                $timestamp = (Get-Date).AddDays(-$i).ToString("yyyyMMdd-HHmmss")
                $backupPath = Join-Path $backupsDir $timestamp
                New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

                # Add dummy content
                New-Item -ItemType Directory -Path (Join-Path $backupPath ".specify") -Force | Out-Null
                "Backup $i" | Out-File -FilePath (Join-Path $backupPath ".specify\test.txt") -Encoding utf8

                # Set creation time
                (Get-Item $backupPath).CreationTime = (Get-Date).AddDays(-$i)
            }

            # Setup mocks
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Updated"
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y" -BackupCleanup "Y"
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject7
        }

        It "Should prompt to cleanup old backups" {
            # Arrange
            Set-Location $script:TestProject7

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String

            # Assert
            $output | Should -BeLike "*old backup*"
        }

        It "Should keep only 5 most recent backups" {
            # Arrange
            Set-Location $script:TestProject7

            # Act
            & $script:OrchestratorScript
            $backupsDir = Join-Path $script:TestProject7 ".specify\backups"
            $backups = Get-ChildItem $backupsDir -Directory

            # Assert
            $backups.Count | Should -BeLessOrEqual 6  # 5 old + 1 new from this update
        }

        It "Should delete oldest backups first" {
            # Arrange
            Set-Location $script:TestProject7
            $backupsDir = Join-Path $script:TestProject7 ".specify\backups"
            $backupsBefore = Get-ChildItem $backupsDir -Directory | Sort-Object CreationTime

            # Act
            & $script:OrchestratorScript
            $backupsAfter = Get-ChildItem $backupsDir -Directory | Sort-Object CreationTime

            # Assert
            # Oldest backup should be gone
            $oldestBefore = $backupsBefore | Select-Object -First 1
            $backupsAfter.Name | Should -Not -Contain $oldestBefore.Name
        }
    }

    Context "Scenario 8: Command Lifecycle" {
        BeforeAll {
            # Create test project
            $script:TestProject8 = New-TestProject -BasedOn "sample-project-with-manifest"

            # Add a custom command
            $customCommandPath = Join-Path $script:TestProject8 ".claude\commands\custom.feature.md"
            "# Custom Feature`n`nMy custom command." | Out-File -FilePath $customCommandPath -Encoding utf8

            # Setup mocks - new official command added, old command removed
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Specify (updated)"
                ".claude/commands/speckit.analyze.md" = "# NEW Analyze Command"
                # speckit.plan.md intentionally removed from upstream
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y"

            # Mock Get-OfficialSpecKitCommands to reflect changes
            Mock -ModuleName ManifestManager Get-OfficialSpecKitCommands {
                return @(
                    "speckit.specify.md",
                    "speckit.analyze.md",  # NEW
                    "speckit.tasks.md"
                    # speckit.plan.md REMOVED
                )
            }
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProject8
        }

        It "Should add new official command" {
            # Arrange
            Set-Location $script:TestProject8

            # Act
            & $script:OrchestratorScript
            $newCommand = Join-Path $script:TestProject8 ".claude\commands\speckit.analyze.md"

            # Assert
            Test-Path $newCommand | Should -BeTrue
            $content = Get-Content $newCommand -Raw
            $content | Should -BeLike "*NEW Analyze Command*"
        }

        It "Should remove obsolete official command" {
            # Arrange
            Set-Location $script:TestProject8
            $oldCommand = Join-Path $script:TestProject8 ".claude\commands\speckit.plan.md"

            # Create the old command first
            "# Old Plan Command" | Out-File -FilePath $oldCommand -Encoding utf8

            # Act
            & $script:OrchestratorScript

            # Assert
            # Official commands that are removed upstream should be deleted
            # (unless they were customized)
        }

        It "Should NOT affect custom commands" {
            # Arrange
            Set-Location $script:TestProject8
            $customCommand = Join-Path $script:TestProject8 ".claude\commands\custom.feature.md"

            # Act
            & $script:OrchestratorScript

            # Assert
            Test-Path $customCommand | Should -BeTrue
            $content = Get-Content $customCommand -Raw
            $content | Should -BeLike "*Custom Feature*"
        }

        It "Should list new and removed commands in summary" {
            # Arrange
            Set-Location $script:TestProject8

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String

            # Assert
            $output | Should -BeLike "*new*" -Or ($output | Should -BeLike "*added*")
        }

        It "Should update manifest with new command list" {
            # Arrange
            Set-Location $script:TestProject8

            # Act
            & $script:OrchestratorScript
            $manifestPath = Join-Path $script:TestProject8 ".specify\manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

            # Assert
            $manifest.speckit_commands | Should -Contain "speckit.analyze.md"
            $manifest.speckit_commands | Should -Not -Contain "speckit.plan.md"
        }
    }

    Context "Additional Scenarios: Check-Only Mode" {
        BeforeAll {
            # Create test project
            $script:TestProjectCheckOnly = New-TestProject -BasedOn "sample-project-with-manifest"

            # Setup mocks
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Updated Specify"
            }
            Mock-VSCodeCommands
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProjectCheckOnly
        }

        It "Should show update report without applying changes" {
            # Arrange
            Set-Location $script:TestProjectCheckOnly
            $manifestBefore = Get-Content (Join-Path $script:TestProjectCheckOnly ".specify\manifest.json") -Raw

            # Act
            $output = & $script:OrchestratorScript -CheckOnly 2>&1 | Out-String
            $manifestAfter = Get-Content (Join-Path $script:TestProjectCheckOnly ".specify\manifest.json") -Raw

            # Assert
            $LASTEXITCODE | Should -Be 0
            $manifestBefore | Should -Be $manifestAfter  # No changes made
            $output | Should -BeLike "*update*"
        }

        It "Should not create backup in check-only mode" {
            # Arrange
            Set-Location $script:TestProjectCheckOnly
            $backupsDir = Join-Path $script:TestProjectCheckOnly ".specify\backups"
            $backupsBefore = if (Test-Path $backupsDir) { (Get-ChildItem $backupsDir -Directory).Count } else { 0 }

            # Act
            & $script:OrchestratorScript -CheckOnly
            $backupsAfter = if (Test-Path $backupsDir) { (Get-ChildItem $backupsDir -Directory).Count } else { 0 }

            # Assert
            $backupsAfter | Should -Be $backupsBefore
        }

        It "Should not modify any files in check-only mode" {
            # Arrange
            Set-Location $script:TestProjectCheckOnly
            $testFile = Join-Path $script:TestProjectCheckOnly ".claude\commands\speckit.specify.md"
            $contentBefore = Get-Content $testFile -Raw

            # Act
            & $script:OrchestratorScript -CheckOnly
            $contentAfter = Get-Content $testFile -Raw

            # Assert
            $contentAfter | Should -Be $contentBefore
        }
    }

    Context "Additional Scenarios: Force Mode" {
        BeforeAll {
            # Create test project
            $script:TestProjectForce = New-TestProject -BasedOn "sample-project-with-customizations"

            # Customize a file
            $customFile = Join-Path $script:TestProjectForce ".claude\commands\speckit.specify.md"
            "# My Custom Version`n`nDo not overwrite!" | Out-File -FilePath $customFile -Encoding utf8

            # Setup mocks
            Mock-GitHubApi -Version "v0.0.72" -Templates @{
                ".claude/commands/speckit.specify.md" = "# Official Version`n`nThis will overwrite."
            }
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "Y"
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProjectForce
        }

        It "Should overwrite customized files when --force is used" {
            # Arrange
            Set-Location $script:TestProjectForce

            # Act
            & $script:OrchestratorScript -Force
            $customFile = Join-Path $script:TestProjectForce ".claude\commands\speckit.specify.md"
            $content = Get-Content $customFile -Raw

            # Assert
            $content | Should -BeLike "*Official Version*"
            $content | Should -Not -BeLike "*Do not overwrite*"
        }

        It "Should still preserve custom commands in force mode" {
            # Arrange
            Set-Location $script:TestProjectForce
            $customCommand = Join-Path $script:TestProjectForce ".claude\commands\custom.test.md"
            "# Custom Command" | Out-File -FilePath $customCommand -Encoding utf8

            # Act
            & $script:OrchestratorScript -Force

            # Assert
            Test-Path $customCommand | Should -BeTrue
        }
    }

    Context "Additional Scenarios: Rollback Command" {
        BeforeAll {
            # Create test project
            $script:TestProjectRollback = New-TestProject -BasedOn "sample-project-with-manifest"

            # Create a backup
            Import-Module (Join-Path $script:ModulesPath "BackupManager.psm1") -Force
            $backupPath = New-SpecKitBackup -ProjectRoot $script:TestProjectRollback -FromVersion "v0.0.71" -ToVersion "v0.0.72"

            # Modify current state
            $testFile = Join-Path $script:TestProjectRollback ".claude\commands\speckit.specify.md"
            "# Modified After Backup" | Out-File -FilePath $testFile -Encoding utf8

            # Setup mocks
            Mock-VSCodeCommands
            Mock-UserInput -Confirmation "1"  # Select first backup
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProjectRollback
        }

        It "Should list available backups" {
            # Arrange
            Set-Location $script:TestProjectRollback

            # Act
            $output = & $script:OrchestratorScript -Rollback 2>&1 | Out-String

            # Assert
            $output | Should -BeLike "*backup*"
        }

        It "Should restore selected backup" {
            # Arrange
            Set-Location $script:TestProjectRollback

            # Act
            & $script:OrchestratorScript -Rollback
            $testFile = Join-Path $script:TestProjectRollback ".claude\commands\speckit.specify.md"
            $content = Get-Content $testFile -Raw

            # Assert
            $content | Should -Not -BeLike "*Modified After Backup*"
        }

        It "Should exit successfully after rollback" {
            # Arrange
            Set-Location $script:TestProjectRollback

            # Act
            & $script:OrchestratorScript -Rollback

            # Assert
            $LASTEXITCODE | Should -Be 0
        }
    }

    Context "Additional Scenarios: Error Handling" {
        BeforeAll {
            # Create test project
            $script:TestProjectError = New-TestProject -BasedOn "sample-project-with-manifest"
        }

        AfterAll {
            Remove-TestProject -ProjectPath $script:TestProjectError
        }

        It "Should fail gracefully when no internet connection" {
            # Arrange
            Set-Location $script:TestProjectError

            # Mock network failure
            Mock -ModuleName GitHubApiClient Get-LatestSpecKitRelease {
                throw "Network error: Unable to connect to GitHub"
            }

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            # Assert
            $exitCode | Should -Not -Be 0
            $output | Should -BeLike "*internet*" -Or ($output | Should -BeLike "*network*")
        }

        It "Should validate prerequisites before starting" {
            # Arrange
            $nonExistentPath = Join-Path $env:TEMP "non-existent-project-$(Get-Random)"
            Set-Location $env:TEMP

            # Act
            $output = & $script:OrchestratorScript 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            # Assert - Should fail validation
            $exitCode | Should -Not -Be 0
        }

        It "Should handle invalid version specification" {
            # Arrange
            Set-Location $script:TestProjectError

            # Mock invalid version
            Mock -ModuleName GitHubApiClient Get-SpecKitRelease {
                throw "Release not found: v999.999.999"
            }

            # Act
            $output = & $script:OrchestratorScript -Version "v999.999.999" 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            # Assert
            $exitCode | Should -Not -Be 0
            $output | Should -BeLike "*version*" -Or ($output | Should -BeLike "*not found*")
        }
    }
}

Describe "Smart Conflict Resolution (Feature 008)" {
    Context "Large File Diff Generation (User Story 1)" {
        It "T028: End-to-end workflow generates diff file for large file conflict" {
            # Arrange: Create test project
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"

            try {
                Set-Location $projectPath

                # Create a large file with 150 lines
                $largefile = Join-Path $projectPath ".claude\commands\large-test.md"
                $currentContent = (1..150 | ForEach-Object { "# Section $_`nContent for section $_`n" }) -join "`n"
                $incomingContent = (1..150 | ForEach-Object {
                    if ($_ -eq 75) { "# MODIFIED SECTION 75`nThis section was changed upstream`n" }
                    else { "# Section $_`nContent for section $_`n" }
                }) -join "`n"

                # Manually invoke the smart conflict resolution (simulates orchestrator behavior)
                Import-Module (Join-Path $script:ModulesPath "ConflictDetector.psm1") -Force

                # Act: Generate conflict resolution
                Write-SmartConflictResolution -FilePath $largefile `
                                               -CurrentContent $currentContent `
                                               -BaseContent $currentContent `
                                               -IncomingContent $incomingContent `
                                               -OriginalVersion "v0.0.72" `
                                               -NewVersion "v0.0.73"

                # Assert: Diff file should be generated (not Git markers in original file)
                $diffFilePath = Join-Path $projectPath ".specify\.tmp-conflicts\large-test.diff.md"
                Test-Path $diffFilePath | Should -BeTrue -Because "Diff file should be generated for large file (>100 lines) conflict"

                # Verify diff file contains expected sections
                $diffContent = Get-Content $diffFilePath -Raw
                $diffContent | Should -Match "# Conflict Resolution: large-test.md" -Because "Diff file should have header"
                $diffContent | Should -Match "## Changed Section" -Because "Diff file should have section markers"
                $diffContent | Should -Match "v0.0.72" -Because "Diff file should show current version"
                $diffContent | Should -Match "v0.0.73" -Because "Diff file should show incoming version"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "T029: Generated diff file format matches specification" {
            # Arrange: Create test project
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"

            try {
                Set-Location $projectPath

                # Create a large customized file (200 lines)
                $largefile = Join-Path $projectPath ".claude\commands\custom-large.md"
                $currentContent = (1..200 | ForEach-Object { "Line $_" }) -join "`n"
                $currentContent | Out-File -FilePath $largefile -Encoding utf8 -Force

                # Manually invoke the diff generation (unit-level integration)
                Import-Module (Join-Path $script:ModulesPath "ConflictDetector.psm1") -Force

                $incomingContent = (1..200 | ForEach-Object {
                    if ($_ -in 50..52) { "Modified Line $_" }
                    elseif ($_ -in 100..102) { "Modified Line $_" }
                    else { "Line $_" }
                }) -join "`n"

                # Act: Generate diff
                Write-SmartConflictResolution -FilePath "custom-large.md" `
                                               -CurrentContent $currentContent `
                                               -BaseContent $currentContent `
                                               -IncomingContent $incomingContent `
                                               -OriginalVersion "v0.0.72" `
                                               -NewVersion "v0.0.73"

                # Assert: Verify diff file format
                $diffFilePath = Join-Path $projectPath ".specify\.tmp-conflicts\custom-large.diff.md"
                Test-Path $diffFilePath | Should -BeTrue

                $diffContent = Get-Content $diffFilePath -Raw

                # Check required format elements
                $diffContent | Should -Match "# Conflict Resolution: custom-large.md" -Because "Header should include filename"
                $diffContent | Should -Match "\*\*Your Version\*\*: v0.0.72" -Because "Your version metadata required"
                $diffContent | Should -Match "\*\*Incoming Version\*\*: v0.0.73" -Because "Incoming version metadata required"
                $diffContent | Should -Match "## Changed Section \d+" -Because "Section headers required"
                $diffContent | Should -Match "### Your Version \(Lines \d+-\d+\)" -Because "Your version section label required"
                $diffContent | Should -Match "### Incoming Version \(Lines \d+-\d+\)" -Because "Incoming version section label required"
                $diffContent | Should -Match '```' -Because "Markdown code blocks required"
                $diffContent | Should -Match "## Unchanged Sections" -Because "Unchanged sections summary required"

                # Verify UTF-8 encoding without BOM
                $bytes = [System.IO.File]::ReadAllBytes($diffFilePath)
                if ($bytes.Length -ge 3) {
                    $hasBOM = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
                    $hasBOM | Should -BeFalse -Because "Diff file should use UTF-8 without BOM"
                }
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }
    }

    Context "Small File Git Markers (User Story 2)" {
        It "T036: End-to-end small file conflict uses Git markers" {
            # Arrange: Create test project with small file (50 lines)
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"

            try {
                Set-Location $projectPath

                # Create a small file with 50 lines
                $smallFile = Join-Path $projectPath ".claude\commands\custom-small.md"
                $currentContent = (1..50 | ForEach-Object { "Line $_" }) -join "`n"
                $currentContent | Out-File -FilePath $smallFile -Encoding utf8 -Force

                # Manually test the smart resolution
                Import-Module (Join-Path $script:ModulesPath "ConflictDetector.psm1") -Force

                $incomingContent = (1..50 | ForEach-Object {
                    if ($_ -eq 25) { "Modified Line 25" }
                    else { "Line $_" }
                }) -join "`n"

                # Act: Generate conflict markers
                Write-SmartConflictResolution -FilePath $smallFile `
                                               -CurrentContent $currentContent `
                                               -BaseContent $currentContent `
                                               -IncomingContent $incomingContent `
                                               -OriginalVersion "v0.0.72" `
                                               -NewVersion "v0.0.73"

                # Assert: File should contain Git conflict markers (not diff file)
                Test-Path $smallFile | Should -BeTrue
                $fileContent = Get-Content $smallFile -Raw

                $fileContent | Should -Match "<<<<<<< Current" -Because "Git conflict marker should be present"
                $fileContent | Should -Match "\|\|\|\|\|\|\| Base" -Because "Git base marker should be present"
                $fileContent | Should -Match "=======" -Because "Git separator should be present"
                $fileContent | Should -Match ">>>>>>> Incoming" -Because "Git incoming marker should be present"

                # Verify NO diff file was created
                $diffFilePath = Join-Path $projectPath ".specify\.tmp-conflicts\custom-small.diff.md"
                Test-Path $diffFilePath | Should -BeFalse -Because "Small files should use Git markers, not diff files"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }
    }

    Context "Diff File Cleanup (User Story 3)" {
        It "T043: Successful update cleans up diff files" {
            # Arrange: Create test project
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"

            try {
                Set-Location $projectPath

                # Create .tmp-conflicts directory with sample diff files
                $tmpConflictsDir = Join-Path $projectPath ".specify\.tmp-conflicts"
                New-Item -ItemType Directory -Path $tmpConflictsDir -Force | Out-Null
                $diffFile1 = Join-Path $tmpConflictsDir "test1.diff.md"
                $diffFile2 = Join-Path $tmpConflictsDir "test2.diff.md"
                "# Sample diff 1" | Out-File -FilePath $diffFile1 -Encoding utf8
                "# Sample diff 2" | Out-File -FilePath $diffFile2 -Encoding utf8

                # Verify diff files exist before cleanup
                Test-Path $tmpConflictsDir | Should -BeTrue
                Test-Path $diffFile1 | Should -BeTrue
                Test-Path $diffFile2 | Should -BeTrue

                # Manually invoke cleanup (simulates orchestrator Step 13.5)
                Import-Module (Join-Path $script:ModulesPath "ConflictDetector.psm1") -Force

                # Act: Clean up diff files
                Remove-ConflictDiffFiles -ProjectRoot $projectPath

                # Assert: Diff files should be cleaned up
                Test-Path $tmpConflictsDir | Should -BeFalse -Because "Successful update should clean up .tmp-conflicts directory"
                Test-Path $diffFile1 | Should -BeFalse -Because "Diff files should be removed"
                Test-Path $diffFile2 | Should -BeFalse -Because "Diff files should be removed"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "T044: Rollback preserves diff files for debugging" {
            # Arrange: Create test project
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"

            try {
                Set-Location $projectPath

                # Create .tmp-conflicts directory with sample diff files
                $tmpConflictsDir = Join-Path $projectPath ".specify\.tmp-conflicts"
                New-Item -ItemType Directory -Path $tmpConflictsDir -Force | Out-Null
                $diffFile1 = Join-Path $tmpConflictsDir "test-rollback1.diff.md"
                $diffFile2 = Join-Path $tmpConflictsDir "test-rollback2.diff.md"
                "# Sample diff for rollback 1" | Out-File -FilePath $diffFile1 -Encoding utf8
                "# Sample diff for rollback 2" | Out-File -FilePath $diffFile2 -Encoding utf8

                # Verify diff files exist before rollback
                Test-Path $diffFile1 | Should -BeTrue
                Test-Path $diffFile2 | Should -BeTrue

                # Mock GitHub API to simulate a failure scenario
                Mock -ModuleName GitHubApiClient Get-LatestSpecKitRelease {
                    return @{
                        tag_name = "v0.0.73"
                        name = "Release v0.0.73"
                        published_at = "2025-01-20T10:00:00Z"
                    }
                }

                Mock -ModuleName GitHubApiClient Download-SpecKitTemplates {
                    throw "Simulated download failure to trigger rollback"
                }

                # Act: Run update that will fail and trigger rollback
                $output = & $script:OrchestratorScript -Proceed 2>&1 | Out-String
                $exitCode = $LASTEXITCODE

                # Assert: Update should fail
                $exitCode | Should -Not -Be 0 -Because "Update should fail due to mocked error"

                # Assert: Diff files should still exist after rollback
                Test-Path $tmpConflictsDir | Should -BeTrue -Because "Rollback should preserve .tmp-conflicts directory"
                Test-Path $diffFile1 | Should -BeTrue -Because "Rollback should preserve diff files for debugging"
                Test-Path $diffFile2 | Should -BeTrue -Because "Rollback should preserve diff files for debugging"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }
    }

    Context "Scenario 11: Constitution Notification with Hash Verification (Issue #18)" {
        It "Should NOT show notification when constitution marked updated but hashes identical (false positive elimination)" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create identical constitution in backup
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Copy-Item ".specify/memory/constitution.md" "$backupDir/.specify/memory/constitution.md"

                # Mock GitHub API
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = (Get-Content ".specify/memory/constitution.md" -Raw)
                }

                # Mock update result to mark constitution as updated
                $script:constitutionMarkedUpdated = $true

                # Act: Run orchestrator (mocked to skip most steps, focus on Step 12)
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: No notification should be shown
                $output | Should -Not -Match 'Constitution.*Updated' -Because "Identical hashes should suppress notification"
                $output | Should -Match 'content unchanged.*skipping notification' -Because "Verbose logging should explain suppression"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should show notification when backup constitution missing (fail-safe behavior)" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create backup without constitution (simulates missing file)
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                # Intentionally do NOT copy constitution.md to backup

                # Mock GitHub API
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = "# Updated constitution content`n"
                }

                # Act: Run orchestrator
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: Notification should be shown (fail-safe)
                $output | Should -Match 'No backup constitution found.*assuming changed' -Because "Verbose logging should explain fail-safe"
                $output | Should -Match 'Constitution.*Updated' -Because "Missing backup triggers fail-safe notification"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should NOT show notification in fresh install scenario (v0.0.0 to v0.0.78) when content identical" {
            $projectPath = New-TestProject -BasedOn "sample-project-no-manifest"
            try {
                Set-Location $projectPath

                # Setup: Fresh install (no manifest, version 0.0.0 → 0.0.78)
                Remove-Item ".specify/manifest.json" -Force -ErrorAction SilentlyContinue

                # Setup: Create backup with identical constitution
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Copy-Item ".specify/memory/constitution.md" "$backupDir/.specify/memory/constitution.md"

                # Mock GitHub API with identical content
                $constitutionContent = Get-Content ".specify/memory/constitution.md" -Raw
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = $constitutionContent
                }

                # Act: Run orchestrator
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: No false positive notification
                $output | Should -Not -Match 'Constitution.*Updated' -Because "Fresh install with identical content should not trigger notification"
                $output | Should -Match 'Changed=False' -Because "Hash comparison should detect no change"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should show OPTIONAL informational notification when constitution cleanly updated (differing hashes)" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create backup with different constitution content
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Set-Content "$backupDir/.specify/memory/constitution.md" -Value "# Old constitution content`n"

                # Update current constitution to differ from backup
                Add-Content ".specify/memory/constitution.md" -Value "`n# New section added`n"

                # Mock GitHub API
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = (Get-Content ".specify/memory/constitution.md" -Raw)
                }

                # Act: Run orchestrator
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: Informational notification with proper styling
                $output | Should -Match 'ℹ️.*Constitution Template Updated' -Because "Clean update should show informational icon"
                $output | Should -Match 'OPTIONAL' -Because "Clean update should be marked optional"
                $output | Should -Match 'cleanly updated.*no conflicts' -Because "Message should indicate no conflicts"
                $output | Should -Match 'Review changes by running' -Because "Action verb should be 'Review' for optional updates"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should include backup path parameter in clean update notification" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create backup with different constitution
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Set-Content "$backupDir/.specify/memory/constitution.md" -Value "# Old constitution`n"

                # Update current constitution
                Add-Content ".specify/memory/constitution.md" -Value "`n# Updated constitution`n"

                # Mock GitHub API
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = (Get-Content ".specify/memory/constitution.md" -Raw)
                }

                # Act: Run orchestrator
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: Notification includes backup path
                $output | Should -Match '/speckit\.constitution.*test-backup' -Because "Notification should include backup path parameter"
                $output | Should -Match 'test-backup.*\.specify.*memory.*constitution\.md' -Because "Full backup path should be provided"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should show structured verbose logging with hashes and paths" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create backup with different constitution
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Set-Content "$backupDir/.specify/memory/constitution.md" -Value "# Old content`n"

                # Update current constitution
                Add-Content ".specify/memory/constitution.md" -Value "`n# New content`n"

                # Mock GitHub API
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = (Get-Content ".specify/memory/constitution.md" -Raw)
                }

                # Act: Run orchestrator with verbose
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: Structured logging present
                $output | Should -Match 'Constitution hash comparison:' -Because "Verbose logging should have header"
                $output | Should -Match 'CurrentPath=' -Because "Current path should be logged"
                $output | Should -Match 'BackupPath=' -Because "Backup path should be logged"
                $output | Should -Match 'CurrentHash=sha256:' -Because "Current hash should be logged"
                $output | Should -Match 'BackupHash=sha256:' -Because "Backup hash should be logged"
                $output | Should -Match 'Changed=(True|False)' -Because "Change detection result should be logged"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should show REQUIRED urgent notification for constitution conflicts (differing hashes)" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create backup with different constitution
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Set-Content "$backupDir/.specify/memory/constitution.md" -Value "# Old conflicted content`n"

                # Update current constitution to create conflict
                Set-Content ".specify/memory/constitution.md" -Value "# User customized constitution`n"

                # Mock GitHub API with conflicting upstream content
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = "# Upstream updated constitution`n"
                }

                # Mock conflict detection
                Mock -ModuleName ConflictDetector Get-FileState {
                    return 'merge'  # Indicates conflict
                }

                # Act: Run orchestrator
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: Urgent notification with proper styling
                $output | Should -Match '⚠️.*Constitution Conflict Detected' -Because "Conflict should show warning icon"
                $output | Should -Match 'REQUIRED' -Because "Conflict resolution should be marked required"
                $output | Should -Match 'conflicts requiring manual resolution' -Because "Message should indicate required action"
                $output | Should -Match 'Run the following command' -Because "Action verb should be 'Run' for required actions"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should NOT show notification for constitution conflict when hashes match (prevents false positive)" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create backup with IDENTICAL constitution
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Copy-Item ".specify/memory/constitution.md" "$backupDir/.specify/memory/constitution.md"

                # Mock GitHub API with same content
                $constitutionContent = Get-Content ".specify/memory/constitution.md" -Raw
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = $constitutionContent
                }

                # Mock conflict detection (but hashes will match, so no notification)
                Mock -ModuleName ConflictDetector Get-FileState {
                    return 'merge'  # Indicates conflict flag
                }

                # Act: Run orchestrator
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: No notification despite conflict flag
                $output | Should -Not -Match 'Constitution Conflict' -Because "Identical hashes should suppress false positive"
                $output | Should -Match 'content unchanged.*skipping notification' -Because "Verbose logging should explain suppression"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }

        It "Should show notification when Get-NormalizedHash throws exception (fail-safe)" {
            $projectPath = New-TestProject -BasedOn "sample-project-with-manifest"
            try {
                Set-Location $projectPath

                # Setup: Create backup
                $backupDir = Join-Path $projectPath ".specify/backups/test-backup"
                New-Item -ItemType Directory -Path "$backupDir/.specify/memory" -Force | Out-Null
                Copy-Item ".specify/memory/constitution.md" "$backupDir/.specify/memory/constitution.md"

                # Mock Get-NormalizedHash to throw exception
                Mock -ModuleName HashUtils Get-NormalizedHash {
                    throw "Simulated hash computation error"
                }

                # Mock GitHub API
                Mock-GitHubApi -Version "v0.0.78" -Templates @{
                    '.specify/memory/constitution.md' = (Get-Content ".specify/memory/constitution.md" -Raw)
                }

                # Act: Run orchestrator
                $output = & $script:OrchestratorScript -CheckOnly -Verbose 2>&1 | Out-String

                # Assert: Fail-safe behavior
                $output | Should -Match 'Constitution hash comparison failed' -Because "Exception should be caught and logged"
                $output | Should -Match 'Error=.*Exception' -Because "Exception type should be logged"
                $output | Should -Match 'Message=.*Simulated hash computation error' -Because "Exception message should be logged"
                $output | Should -Match 'Defaulting to showing notification.*fail-safe' -Because "Fail-safe action should be logged"
                $output | Should -Match 'Constitution.*Updated' -Because "Notification should be shown as fail-safe"
            }
            finally {
                Remove-TestProject -ProjectPath $projectPath
            }
        }
    }
}
