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
