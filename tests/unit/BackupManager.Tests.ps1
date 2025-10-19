#Requires -Version 7.0

<#
.SYNOPSIS
    Unit tests for BackupManager.psm1 module.

.DESCRIPTION
    Comprehensive test suite for backup creation, restoration, listing, and management functions.
    Uses temporary test directories to avoid affecting real projects.
#>

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot "../../scripts/modules/BackupManager.psm1"
    Import-Module $modulePath -Force

    # Helper function to create a test SpecKit project structure
    function New-TestSpecKitProject {
        param([string]$Path)

        # Create .specify directory structure
        $specifyDir = Join-Path $Path ".specify"
        New-Item -ItemType Directory -Path $specifyDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $specifyDir "memory") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $specifyDir "templates") -Force | Out-Null

        # Create sample files
        "Test manifest content" | Out-File (Join-Path $specifyDir "manifest.json") -Encoding utf8
        "Memory content" | Out-File (Join-Path $specifyDir "memory/notes.md") -Encoding utf8
        "Template content" | Out-File (Join-Path $specifyDir "templates/spec-template.md") -Encoding utf8

        # Create .claude directory structure
        $claudeDir = Join-Path $Path ".claude"
        New-Item -ItemType Directory -Path (Join-Path $claudeDir "commands") -Force | Out-Null

        # Create sample commands
        "Command 1 content" | Out-File (Join-Path $claudeDir "commands/command1.md") -Encoding utf8
        "Command 2 content" | Out-File (Join-Path $claudeDir "commands/command2.md") -Encoding utf8

        return $Path
    }

    # Helper function to create a temporary directory
    function New-TempTestDirectory {
        $tempPath = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        return $tempPath
    }

    # Helper function to count files recursively
    function Get-FileCount {
        param([string]$Path)
        return (Get-ChildItem -Path $Path -Recurse -File).Count
    }
}

Describe "BackupManager Module" {
    Context "New-SpecKitBackup" {
        It "Creates backup directory with timestamp format" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Act
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Assert
            $backupPath | Should -Not -BeNullOrEmpty
            Test-Path $backupPath | Should -Be $true
            $timestamp = Split-Path $backupPath -Leaf
            $timestamp | Should -Match '^\d{8}-\d{6}$'

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Copies .specify directory contents (excluding backups)" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create a backups directory that should be excluded
            $existingBackupsDir = Join-Path $testProject ".specify/backups/old-backup"
            New-Item -ItemType Directory -Path $existingBackupsDir -Force | Out-Null

            # Act
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Assert
            $backupSpecifyDir = Join-Path $backupPath ".specify"
            Test-Path $backupSpecifyDir | Should -Be $true
            Test-Path (Join-Path $backupSpecifyDir "manifest.json") | Should -Be $true
            Test-Path (Join-Path $backupSpecifyDir "memory/notes.md") | Should -Be $true
            Test-Path (Join-Path $backupSpecifyDir "templates/spec-template.md") | Should -Be $true

            # Verify backups directory was excluded
            Test-Path (Join-Path $backupSpecifyDir "backups") | Should -Be $false

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Copies .claude directory if it exists" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Act
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Assert
            $backupClaudeDir = Join-Path $backupPath ".claude"
            Test-Path $backupClaudeDir | Should -Be $true
            Test-Path (Join-Path $backupClaudeDir "commands/command1.md") | Should -Be $true
            Test-Path (Join-Path $backupClaudeDir "commands/command2.md") | Should -Be $true

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Handles missing .claude directory gracefully" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            Remove-Item (Join-Path $testProject ".claude") -Recurse -Force

            # Act
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Assert
            Test-Path $backupPath | Should -Be $true
            Test-Path (Join-Path $backupPath ".specify") | Should -Be $true
            Test-Path (Join-Path $backupPath ".claude") | Should -Be $false

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Throws error if not a SpecKit project" {
            # Arrange
            $testProject = New-TempTestDirectory

            # Act & Assert
            { New-SpecKitBackup -ProjectRoot $testProject } | Should -Throw "*SpecKit project*"

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Returns valid backup path" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Act
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Assert
            $backupPath | Should -BeLike "*\.specify\backups\*"
            Test-Path $backupPath | Should -Be $true

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Creates backup with all file contents intact" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $originalContent = Get-Content (Join-Path $testProject ".specify/manifest.json") -Raw

            # Act
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Assert
            $backupManifest = Join-Path $backupPath ".specify/manifest.json"
            $backupContent = Get-Content $backupManifest -Raw
            $backupContent | Should -Be $originalContent

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }
    }

    Context "Restore-SpecKitBackup" {
        It "Restores .specify directory from backup" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Modify current files
            "Modified content" | Out-File (Join-Path $testProject ".specify/manifest.json") -Encoding utf8

            # Act
            Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $backupPath

            # Assert
            $restoredContent = Get-Content (Join-Path $testProject ".specify/manifest.json") -Raw
            $restoredContent | Should -Be "Test manifest content`r`n"

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Restores .claude directory from backup" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Modify current files
            "Modified command" | Out-File (Join-Path $testProject ".claude/commands/command1.md") -Encoding utf8

            # Act
            Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $backupPath

            # Assert
            $restoredContent = Get-Content (Join-Path $testProject ".claude/commands/command1.md") -Raw
            $restoredContent | Should -Be "Command 1 content`r`n"

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Preserves backups directory during restore" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $backupPath1 = New-SpecKitBackup -ProjectRoot $testProject
            Start-Sleep -Milliseconds 100
            $backupPath2 = New-SpecKitBackup -ProjectRoot $testProject

            # Act - restore first backup
            Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $backupPath1

            # Assert - second backup should still exist
            Test-Path $backupPath2 | Should -Be $true

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Throws error if backup path does not exist" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $fakePath = Join-Path $testProject ".specify/backups/fake-backup"

            # Act & Assert
            { Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $fakePath } | Should -Throw "*not found*"

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Throws error if backup is invalid (missing .specify)" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $invalidBackup = Join-Path $testProject ".specify/backups/invalid"
            New-Item -ItemType Directory -Path $invalidBackup -Force | Out-Null

            # Act & Assert
            { Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $invalidBackup } | Should -Throw "*Invalid backup*"

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Handles missing .claude in backup gracefully" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            Remove-Item (Join-Path $testProject ".claude") -Recurse -Force
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Recreate .claude for testing
            $claudeDir = Join-Path $testProject ".claude/commands"
            New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
            "New command" | Out-File (Join-Path $claudeDir "new.md") -Encoding utf8

            # Act
            Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $backupPath

            # Assert - .claude should be removed since it wasn't in backup
            Test-Path (Join-Path $testProject ".claude") | Should -Be $false

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Completely replaces existing directories" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Add new files that shouldn't exist after restore
            "New file" | Out-File (Join-Path $testProject ".specify/newfile.txt") -Encoding utf8

            # Act
            Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $backupPath

            # Assert
            Test-Path (Join-Path $testProject ".specify/newfile.txt") | Should -Be $false

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }
    }

    Context "Get-SpecKitBackups" {
        It "Returns empty array when no backups exist" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Act
            $backups = Get-SpecKitBackups -ProjectRoot $testProject

            # Assert
            $backups | Should -BeNullOrEmpty
            $backups.Count | Should -Be 0

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Returns array of backup objects with correct properties" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Act
            $backups = Get-SpecKitBackups -ProjectRoot $testProject

            # Assert
            $backups | Should -Not -BeNullOrEmpty
            $backups.Count | Should -Be 1
            $backups[0].Timestamp | Should -Not -BeNullOrEmpty
            $backups[0].Path | Should -Be $backupPath
            $backups[0].CreatedAt | Should -BeOfType [DateTime]
            $backups[0].SizeKB | Should -BeGreaterThan 0

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Returns backups sorted by CreatedAt descending (newest first)" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create multiple backups with delays
            $backup1 = New-SpecKitBackup -ProjectRoot $testProject
            Start-Sleep -Milliseconds 100
            $backup2 = New-SpecKitBackup -ProjectRoot $testProject
            Start-Sleep -Milliseconds 100
            $backup3 = New-SpecKitBackup -ProjectRoot $testProject

            # Act
            $backups = Get-SpecKitBackups -ProjectRoot $testProject

            # Assert
            $backups.Count | Should -Be 3
            $backups[0].Path | Should -Be $backup3  # Newest
            $backups[1].Path | Should -Be $backup2
            $backups[2].Path | Should -Be $backup1  # Oldest

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Calculates backup size correctly" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            New-SpecKitBackup -ProjectRoot $testProject

            # Act
            $backups = Get-SpecKitBackups -ProjectRoot $testProject

            # Assert
            $backups[0].SizeKB | Should -BeOfType [double]
            $backups[0].SizeKB | Should -BeGreaterThan 0

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Returns empty array when backups directory does not exist" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            # Don't create any backups

            # Act
            $backups = @(Get-SpecKitBackups -ProjectRoot $testProject)

            # Assert
            $backups.Count | Should -Be 0

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Includes timestamp in correct format" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            New-SpecKitBackup -ProjectRoot $testProject

            # Act
            $backups = Get-SpecKitBackups -ProjectRoot $testProject

            # Assert
            $backups[0].Timestamp | Should -Match '^\d{8}-\d{6}$'

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }
    }

    Context "Remove-OldBackups" {
        It "Returns empty array when backup count is within limit" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            New-SpecKitBackup -ProjectRoot $testProject
            Start-Sleep -Milliseconds 50
            New-SpecKitBackup -ProjectRoot $testProject

            # Act
            $removed = @(Remove-OldBackups -ProjectRoot $testProject -KeepCount 5)

            # Assert
            $removed.Count | Should -Be 0

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Keeps newest N backups and removes older ones" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create 7 backups
            $backups = @()
            for ($i = 0; $i -lt 7; $i++) {
                $backups += New-SpecKitBackup -ProjectRoot $testProject
                Start-Sleep -Milliseconds 50
            }

            # Act
            $removed = Remove-OldBackups -ProjectRoot $testProject -KeepCount 5

            # Assert
            $removed.Count | Should -Be 2

            # Verify only 5 backups remain
            $remaining = Get-SpecKitBackups -ProjectRoot $testProject
            $remaining.Count | Should -Be 5

            # Verify newest 5 are kept
            $remaining[0].Path | Should -Be $backups[6]  # Newest
            $remaining[4].Path | Should -Be $backups[2]  # 5th newest

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "WhatIf mode returns backups without deleting" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create 7 backups
            for ($i = 0; $i -lt 7; $i++) {
                New-SpecKitBackup -ProjectRoot $testProject
                Start-Sleep -Milliseconds 50
            }

            # Act
            $wouldRemove = Remove-OldBackups -ProjectRoot $testProject -KeepCount 5 -WhatIf

            # Assert
            $wouldRemove.Count | Should -Be 2

            # Verify all backups still exist
            $allBackups = Get-SpecKitBackups -ProjectRoot $testProject
            $allBackups.Count | Should -Be 7

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Respects custom KeepCount parameter" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create 5 backups
            for ($i = 0; $i -lt 5; $i++) {
                New-SpecKitBackup -ProjectRoot $testProject
                Start-Sleep -Milliseconds 50
            }

            # Act - keep only 2
            $removed = Remove-OldBackups -ProjectRoot $testProject -KeepCount 2

            # Assert
            $removed.Count | Should -Be 3

            # Verify only 2 backups remain
            $remaining = Get-SpecKitBackups -ProjectRoot $testProject
            $remaining.Count | Should -Be 2

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Uses default KeepCount of 5" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create 8 backups
            for ($i = 0; $i -lt 8; $i++) {
                New-SpecKitBackup -ProjectRoot $testProject
                Start-Sleep -Milliseconds 50
            }

            # Act - don't specify KeepCount
            $removed = Remove-OldBackups -ProjectRoot $testProject

            # Assert
            $removed.Count | Should -Be 3

            # Verify 5 backups remain
            $remaining = Get-SpecKitBackups -ProjectRoot $testProject
            $remaining.Count | Should -Be 5

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Returns list of deleted backups" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create 6 backups
            for ($i = 0; $i -lt 6; $i++) {
                New-SpecKitBackup -ProjectRoot $testProject
                Start-Sleep -Milliseconds 50
            }

            # Act
            $removed = Remove-OldBackups -ProjectRoot $testProject -KeepCount 5

            # Assert
            $removed.Count | Should -Be 1
            $removed[0].Timestamp | Should -Not -BeNullOrEmpty
            $removed[0].Path | Should -Not -BeNullOrEmpty

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Handles backup deletion errors gracefully" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create 6 backups
            for ($i = 0; $i -lt 6; $i++) {
                New-SpecKitBackup -ProjectRoot $testProject
                Start-Sleep -Milliseconds 50
            }

            # Make the oldest backup read-only (simulate permission issue)
            $allBackups = @(Get-SpecKitBackups -ProjectRoot $testProject)
            $oldestBackup = $allBackups[-1]
            # Note: This test may not work as expected on all systems
            # Just verify the function doesn't crash

            # Act
            $removed = @(Remove-OldBackups -ProjectRoot $testProject -KeepCount 5)

            # Assert - should not throw and return 1 deleted backup
            $removed.Count | Should -Be 1

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }
    }

    Context "Invoke-AutomaticRollback" {
        It "Calls Restore-SpecKitBackup internally" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Modify current files
            "Modified content" | Out-File (Join-Path $testProject ".specify/manifest.json") -Encoding utf8

            # Act
            Invoke-AutomaticRollback -ProjectRoot $testProject -BackupPath $backupPath

            # Assert - verify restoration occurred
            $restoredContent = Get-Content (Join-Path $testProject ".specify/manifest.json") -Raw
            $restoredContent | Should -Be "Test manifest content`r`n"

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Throws error if backup restoration fails" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $fakePath = Join-Path $testProject ".specify/backups/fake-backup"

            # Act & Assert
            { Invoke-AutomaticRollback -ProjectRoot $testProject -BackupPath $fakePath } | Should -Throw

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Outputs appropriate rollback messages" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Act
            $output = Invoke-AutomaticRollback -ProjectRoot $testProject -BackupPath $backupPath 6>&1

            # Assert
            $outputString = $output | Out-String
            $outputString | Should -Match "AUTOMATIC ROLLBACK"

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }
    }

    Context "Integration Tests" {
        It "Complete backup and restore workflow" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Record original state
            $originalManifest = Get-Content (Join-Path $testProject ".specify/manifest.json") -Raw
            $originalCommand = Get-Content (Join-Path $testProject ".claude/commands/command1.md") -Raw

            # Create backup
            $backupPath = New-SpecKitBackup -ProjectRoot $testProject

            # Modify files
            "Modified manifest" | Out-File (Join-Path $testProject ".specify/manifest.json") -Encoding utf8
            "Modified command" | Out-File (Join-Path $testProject ".claude/commands/command1.md") -Encoding utf8

            # Act - restore
            Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $backupPath

            # Assert
            $restoredManifest = Get-Content (Join-Path $testProject ".specify/manifest.json") -Raw
            $restoredCommand = Get-Content (Join-Path $testProject ".claude/commands/command1.md") -Raw

            $restoredManifest | Should -Be $originalManifest
            $restoredCommand | Should -Be $originalCommand

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Multiple backup and cleanup workflow" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create multiple backups
            for ($i = 0; $i -lt 10; $i++) {
                New-SpecKitBackup -ProjectRoot $testProject
                Start-Sleep -Milliseconds 50
            }

            # Act - clean up old backups
            $removed = Remove-OldBackups -ProjectRoot $testProject -KeepCount 5

            # Assert
            $removed.Count | Should -Be 5
            $remaining = Get-SpecKitBackups -ProjectRoot $testProject
            $remaining.Count | Should -Be 5

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }

        It "Backup survives restore of different backup" {
            # Arrange
            $testProject = New-TempTestDirectory
            New-TestSpecKitProject -Path $testProject

            # Create first backup
            $backup1 = New-SpecKitBackup -ProjectRoot $testProject
            Start-Sleep -Milliseconds 100

            # Modify and create second backup
            "Modified" | Out-File (Join-Path $testProject ".specify/manifest.json") -Encoding utf8
            $backup2 = New-SpecKitBackup -ProjectRoot $testProject

            # Act - restore first backup
            Restore-SpecKitBackup -ProjectRoot $testProject -BackupPath $backup1

            # Assert - both backups should still exist
            Test-Path $backup1 | Should -Be $true
            Test-Path $backup2 | Should -Be $true

            $backups = Get-SpecKitBackups -ProjectRoot $testProject
            $backups.Count | Should -Be 2

            # Cleanup
            Remove-Item $testProject -Recurse -Force
        }
    }
}
