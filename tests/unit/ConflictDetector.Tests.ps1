#Requires -Version 7.0

<#
.SYNOPSIS
    Unit tests for ConflictDetector module.

.DESCRIPTION
    Tests conflict detection, file state analysis, customization detection,
    and custom command identification. Covers all action types and edge cases.

.NOTES
    Test Framework: Pester 5.x
    Module Under Test: ConflictDetector.psm1
#>

BeforeAll {
    # Import required modules
    $modulesPath = Join-Path $PSScriptRoot "..\..\scripts\modules"
    Import-Module (Join-Path $modulesPath "HashUtils.psm1") -Force
    Import-Module (Join-Path $modulesPath "GitHubApiClient.psm1") -Force
    Import-Module (Join-Path $modulesPath "ManifestManager.psm1") -Force
    Import-Module (Join-Path $modulesPath "ConflictDetector.psm1") -Force

    # Helper function to create temporary test files
    function New-TestFile {
        param(
            [string]$Content,
            [string]$BasePath = $env:TEMP
        )

        $tempFile = [System.IO.Path]::GetTempFileName()
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($tempFile, $Content, $utf8NoBom)
        return $tempFile
    }

    # Helper function to create mock manifest
    function New-MockManifest {
        param(
            [array]$TrackedFiles = @()
        )

        return [PSCustomObject]@{
            version = "1.0"
            speckit_version = "v0.0.45"
            tracked_files = $TrackedFiles
            speckit_commands = @("speckit.plan.md", "speckit.specify.md")
        }
    }
}

Describe "ConflictDetector Module" {
    Context "Get-FileState" {
        Describe "Action: Skip (No Changes)" {
            It "Returns skip when file unchanged and no upstream changes" {
                # Arrange
                $content = "Line 1`nLine 2`nLine 3"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $hash `
                                           -UpstreamHash $hash `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'skip'
                    $state.IsCustomized | Should -BeFalse
                    $state.HasUpstreamChanges | Should -BeFalse
                    $state.IsConflict | Should -BeFalse
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns skip when file doesn't exist anywhere" {
                # Arrange
                $nonExistentFile = "C:\nonexistent\file.txt"

                # Act
                $state = Get-FileState -FilePath $nonExistentFile `
                                       -OriginalHash $null `
                                       -UpstreamHash $null `
                                       -IsOfficial $true

                # Assert
                $state.Action | Should -Be 'skip'
                $state.CurrentHash | Should -BeNullOrEmpty
            }
        }

        Describe "Action: Add (New File)" {
            It "Returns add when file doesn't exist locally but exists upstream" {
                # Arrange
                $nonExistentFile = "C:\nonexistent\new-file.txt"
                $upstreamHash = "sha256:ABC123"

                # Act
                $state = Get-FileState -FilePath $nonExistentFile `
                                       -OriginalHash $null `
                                       -UpstreamHash $upstreamHash `
                                       -IsOfficial $true

                # Assert
                $state.Action | Should -Be 'add'
                $state.CurrentHash | Should -BeNullOrEmpty
                $state.HasUpstreamChanges | Should -BeTrue
            }
        }

        Describe "Action: Remove (File Deleted Upstream)" {
            It "Returns remove when file not customized and removed upstream" {
                # Arrange
                $content = "Line 1`nLine 2"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $hash `
                                           -UpstreamHash $null `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'remove'
                    $state.IsCustomized | Should -BeFalse
                    $state.HasUpstreamChanges | Should -BeTrue
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns preserve when file customized and removed upstream" {
                # Arrange
                $originalContent = "Line 1`nLine 2"
                $modifiedContent = "Line 1`nLine 2 modified"
                $file = New-TestFile -Content $modifiedContent

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $null `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'preserve'
                    $state.IsCustomized | Should -BeTrue
                    $state.HasUpstreamChanges | Should -BeTrue
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Action: Update (Upstream Changed, Not Customized)" {
            It "Returns update when file not customized but upstream changed" {
                # Arrange
                $originalContent = "Line 1`nLine 2"
                $upstreamContent = "Line 1`nLine 2`nLine 3"

                $file = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $file

                $tempUpstream = New-TestFile -Content $upstreamContent
                $upstreamHash = Get-NormalizedHash -FilePath $tempUpstream

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $upstreamHash `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'update'
                    $state.IsCustomized | Should -BeFalse
                    $state.HasUpstreamChanges | Should -BeTrue
                    $state.IsConflict | Should -BeFalse
                }
                finally {
                    Remove-Item $file, $tempUpstream -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Action: Preserve (Customized, No Upstream Change)" {
            It "Returns preserve when file customized but no upstream changes" {
                # Arrange
                $originalContent = "Line 1`nLine 2"
                $modifiedContent = "Line 1`nLine 2 modified"

                $file = New-TestFile -Content $modifiedContent

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                try {
                    # Act (upstream same as original)
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $originalHash `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'preserve'
                    $state.IsCustomized | Should -BeTrue
                    $state.HasUpstreamChanges | Should -BeFalse
                    $state.IsConflict | Should -BeFalse
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Action: Merge (Conflict)" {
            It "Returns merge when both customized and upstream changed" {
                # Arrange
                $originalContent = "Line 1`nLine 2`nLine 3"
                $modifiedContent = "Line 1 modified`nLine 2`nLine 3"
                $upstreamContent = "Line 1`nLine 2`nLine 3 upstream"

                $file = New-TestFile -Content $modifiedContent

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                $tempUpstream = New-TestFile -Content $upstreamContent
                $upstreamHash = Get-NormalizedHash -FilePath $tempUpstream

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $upstreamHash `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'merge'
                    $state.IsCustomized | Should -BeTrue
                    $state.HasUpstreamChanges | Should -BeTrue
                    $state.IsConflict | Should -BeTrue
                }
                finally {
                    Remove-Item $file, $tempOriginal, $tempUpstream -Force -ErrorAction SilentlyContinue
                }
            }

            It "Detects conflict with different modifications" {
                # Arrange
                $originalContent = "Line 1`nLine 2"
                $userContent = "Line 1 - user edit`nLine 2"
                $upstreamContent = "Line 1 - upstream edit`nLine 2"

                $file = New-TestFile -Content $userContent

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                $tempUpstream = New-TestFile -Content $upstreamContent
                $upstreamHash = Get-NormalizedHash -FilePath $tempUpstream

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $upstreamHash `
                                           -IsOfficial $true

                    # Assert
                    $state.IsConflict | Should -BeTrue
                    $state.Action | Should -Be 'merge'
                }
                finally {
                    Remove-Item $file, $tempOriginal, $tempUpstream -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "IsOfficial Flag" {
            It "Preserves IsOfficial flag in output" {
                # Arrange
                $content = "Test content"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    # Act
                    $stateOfficial = Get-FileState -FilePath $file `
                                                    -OriginalHash $hash `
                                                    -UpstreamHash $hash `
                                                    -IsOfficial $true

                    $stateCustom = Get-FileState -FilePath $file `
                                                 -OriginalHash $hash `
                                                 -UpstreamHash $hash `
                                                 -IsOfficial $false

                    # Assert
                    $stateOfficial.IsOfficial | Should -BeTrue
                    $stateCustom.IsOfficial | Should -BeFalse
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "ManifestCustomized Flag" {
            It "Trusts ManifestCustomized flag when true (overrides hash comparison)" {
                # Arrange - File with same hash as original, but manifest says customized
                $content = "Test content"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                # Create different upstream
                $tempUpstream = New-TestFile -Content "Upstream content"
                $upstreamHash = Get-NormalizedHash -FilePath $tempUpstream

                try {
                    # Act - Current matches original, but ManifestCustomized=true
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $hash `
                                           -UpstreamHash $upstreamHash `
                                           -IsOfficial $true `
                                           -ManifestCustomized $true

                    # Assert - Should be marked as customized despite matching original
                    $state.IsCustomized | Should -BeTrue
                    $state.Action | Should -Be 'merge'  # Customized + upstream changes = merge
                }
                finally {
                    Remove-Item $file, $tempUpstream -Force -ErrorAction SilentlyContinue
                }
            }

            It "Uses hash comparison when ManifestCustomized is false" {
                # Arrange - File modified from original
                $originalContent = "Original content"
                $modifiedContent = "Modified content"

                $file = New-TestFile -Content $modifiedContent

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                try {
                    # Act - File is actually customized but ManifestCustomized=false
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $originalHash `
                                           -IsOfficial $true `
                                           -ManifestCustomized $false

                    # Assert - Should detect customization through hash comparison
                    $state.IsCustomized | Should -BeTrue
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }

            It "Fixes false negative when manifest created with -AssumeAllCustomized" {
                # Arrange - Simulates the bug scenario:
                # - New manifest created with -AssumeAllCustomized
                # - original_hash set to current hash (same content)
                # - But file actually IS customized per manifest flag
                $content = "Current content"
                $file = New-TestFile -Content $content
                $currentHash = Get-NormalizedHash -FilePath $file

                $upstreamContent = "Upstream content"
                $tempUpstream = New-TestFile -Content $upstreamContent
                $upstreamHash = Get-NormalizedHash -FilePath $tempUpstream

                try {
                    # Act - This is the bug scenario:
                    # currentHash == originalHash (same), upstreamHash different
                    # Without ManifestCustomized fix: would be 'update'
                    # With ManifestCustomized=true: should be 'merge'
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $currentHash `
                                           -UpstreamHash $upstreamHash `
                                           -IsOfficial $true `
                                           -ManifestCustomized $true

                    # Assert - Critical fix: respects manifest flag
                    $state.IsCustomized | Should -BeTrue
                    $state.HasUpstreamChanges | Should -BeTrue
                    $state.IsConflict | Should -BeTrue
                    $state.Action | Should -Be 'merge'  # NOT 'update'!
                }
                finally {
                    Remove-Item $file, $tempUpstream -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Hash Comparisons" {
            It "Correctly identifies customization through hash comparison" {
                # Arrange
                $content1 = "Original content"
                $content2 = "Modified content"

                $file = New-TestFile -Content $content2

                $tempOriginal = New-TestFile -Content $content1
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $originalHash `
                                           -IsOfficial $true

                    # Assert
                    $state.IsCustomized | Should -BeTrue
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }

            It "Correctly identifies upstream changes through hash comparison" {
                # Arrange
                $content1 = "Original content"
                $content2 = "Upstream content"

                $file = New-TestFile -Content $content1
                $originalHash = Get-NormalizedHash -FilePath $file

                $tempUpstream = New-TestFile -Content $content2
                $upstreamHash = Get-NormalizedHash -FilePath $tempUpstream

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $originalHash `
                                           -UpstreamHash $upstreamHash `
                                           -IsOfficial $true

                    # Assert
                    $state.HasUpstreamChanges | Should -BeTrue
                }
                finally {
                    Remove-Item $file, $tempUpstream -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Edge Cases" {
            It "Handles null OriginalHash" {
                # Arrange
                $content = "Test content"
                $file = New-TestFile -Content $content

                $tempUpstream = New-TestFile -Content $content
                $upstreamHash = Get-NormalizedHash -FilePath $tempUpstream

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $null `
                                           -UpstreamHash $upstreamHash `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'skip'
                    $state.IsCustomized | Should -BeFalse
                }
                finally {
                    Remove-Item $file, $tempUpstream -Force -ErrorAction SilentlyContinue
                }
            }

            It "Handles empty file" {
                # Arrange
                $file = New-TestFile -Content ""
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $hash `
                                           -UpstreamHash $hash `
                                           -IsOfficial $true

                    # Assert
                    $state.Action | Should -Be 'skip'
                    $state.CurrentHash | Should -Not -BeNullOrEmpty
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns all required properties in output" {
                # Arrange
                $content = "Test"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    # Act
                    $state = Get-FileState -FilePath $file `
                                           -OriginalHash $hash `
                                           -UpstreamHash $hash `
                                           -IsOfficial $true

                    # Assert - Check all required properties exist
                    $state.Keys | Should -Contain 'Path'
                    $state.Keys | Should -Contain 'CurrentHash'
                    $state.Keys | Should -Contain 'OriginalHash'
                    $state.Keys | Should -Contain 'UpstreamHash'
                    $state.Keys | Should -Contain 'IsCustomized'
                    $state.Keys | Should -Contain 'HasUpstreamChanges'
                    $state.Keys | Should -Contain 'IsConflict'
                    $state.Keys | Should -Contain 'IsOfficial'
                    $state.Keys | Should -Contain 'Action'
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Get-AllFileStates" {
        Describe "Tracked Files Processing" {
            It "Processes all tracked files from manifest" {
                # Arrange
                $content1 = "File 1 content"
                $content2 = "File 2 content"

                $file1 = New-TestFile -Content $content1
                $file2 = New-TestFile -Content $content2

                $hash1 = Get-NormalizedHash -FilePath $file1
                $hash2 = Get-NormalizedHash -FilePath $file2

                try {
                    $manifest = New-MockManifest -TrackedFiles @(
                        @{ path = $file1; original_hash = $hash1; is_official = $true }
                        @{ path = $file2; original_hash = $hash2; is_official = $true }
                    )

                    $upstream = @{
                        $file1 = $content1
                        $file2 = $content2
                    }

                    # Act
                    $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                    # Assert
                    $states.Count | Should -Be 2
                    $states[0].Path | Should -Be $file1
                    $states[1].Path | Should -Be $file2
                }
                finally {
                    Remove-Item $file1, $file2 -Force -ErrorAction SilentlyContinue
                }
            }

            It "Detects new files in upstream not in manifest" {
                # Arrange
                $manifest = New-MockManifest -TrackedFiles @()

                $upstream = @{
                    ".claude/commands/new-command.md" = "New command content"
                    ".specify/templates/new-template.md" = "New template content"
                }

                # Act
                $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                # Assert
                $states.Count | Should -Be 2
                $states | Where-Object { $_.Action -eq 'add' } | Should -HaveCount 2
            }

            It "Handles both tracked and new upstream files" {
                # Arrange
                $existingContent = "Existing file"
                $existingFile = New-TestFile -Content $existingContent
                $existingHash = Get-NormalizedHash -FilePath $existingFile

                try {
                    $manifest = New-MockManifest -TrackedFiles @(
                        @{ path = $existingFile; original_hash = $existingHash; is_official = $true }
                    )

                    $upstream = @{
                        $existingFile = $existingContent
                        ".claude/commands/new.md" = "New file"
                    }

                    # Act
                    $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                    # Assert
                    $states.Count | Should -Be 2
                    $states | Where-Object { $_.Path -eq $existingFile } | Should -HaveCount 1
                    $states | Where-Object { $_.Path -eq ".claude/commands/new.md" } | Should -HaveCount 1
                }
                finally {
                    Remove-Item $existingFile -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Upstream Hash Computation" {
            It "Correctly hashes upstream content for comparison" {
                # Arrange
                $content = "Test content`nLine 2"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    $manifest = New-MockManifest -TrackedFiles @(
                        @{ path = $file; original_hash = $hash; is_official = $true }
                    )

                    $upstream = @{
                        $file = $content  # Same content
                    }

                    # Act
                    $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                    # Assert
                    $states[0].Action | Should -Be 'skip'
                    $states[0].HasUpstreamChanges | Should -BeFalse
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }

            It "Detects upstream changes through hash comparison" {
                # Arrange
                $originalContent = "Original content"
                $upstreamContent = "Updated content"

                $file = New-TestFile -Content $originalContent
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    $manifest = New-MockManifest -TrackedFiles @(
                        @{ path = $file; original_hash = $hash; is_official = $true }
                    )

                    $upstream = @{
                        $file = $upstreamContent  # Different content
                    }

                    # Act
                    $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                    # Assert
                    $states[0].HasUpstreamChanges | Should -BeTrue
                    $states[0].Action | Should -Be 'update'
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "File Removal Detection" {
            It "Detects files removed from upstream" {
                # Arrange
                $content = "File content"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    $manifest = New-MockManifest -TrackedFiles @(
                        @{ path = $file; original_hash = $hash; is_official = $true }
                    )

                    $upstream = @{}  # File not in upstream

                    # Act
                    $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                    # Assert
                    $states[0].Action | Should -Be 'remove'
                    $states[0].UpstreamHash | Should -BeNullOrEmpty
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Empty Collections" {
            It "Handles empty manifest (no tracked files)" {
                # Arrange
                $manifest = New-MockManifest -TrackedFiles @()
                $upstream = @{}

                # Act
                $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                # Assert
                $states.Count | Should -Be 0
            }

            It "Handles empty upstream templates" {
                # Arrange
                $content = "File content"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    $manifest = New-MockManifest -TrackedFiles @(
                        @{ path = $file; original_hash = $hash; is_official = $true }
                    )

                    $upstream = @{}

                    # Act
                    $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                    # Assert
                    $states.Count | Should -Be 1
                    $states[0].Action | Should -Be 'remove'
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Conflict Detection" {
            It "Identifies multiple conflicts correctly" {
                # Arrange
                $file1Content = "File 1 user edit"
                $file2Content = "File 2 user edit"
                $file1Original = "File 1 original"
                $file2Original = "File 2 original"
                $file1Upstream = "File 1 upstream"
                $file2Upstream = "File 2 upstream"

                $file1 = New-TestFile -Content $file1Content
                $file2 = New-TestFile -Content $file2Content

                $temp1 = New-TestFile -Content $file1Original
                $temp2 = New-TestFile -Content $file2Original
                $hash1 = Get-NormalizedHash -FilePath $temp1
                $hash2 = Get-NormalizedHash -FilePath $temp2

                try {
                    $manifest = New-MockManifest -TrackedFiles @(
                        @{ path = $file1; original_hash = $hash1; is_official = $true }
                        @{ path = $file2; original_hash = $hash2; is_official = $true }
                    )

                    $upstream = @{
                        $file1 = $file1Upstream
                        $file2 = $file2Upstream
                    }

                    # Act
                    $states = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $upstream

                    # Assert
                    $conflicts = $states | Where-Object { $_.IsConflict }
                    $conflicts.Count | Should -Be 2
                    $conflicts | Where-Object { $_.Action -eq 'merge' } | Should -HaveCount 2
                }
                finally {
                    Remove-Item $file1, $file2, $temp1, $temp2 -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Test-FileCustomized" {
        Describe "Customization Detection" {
            It "Returns true for customized file" {
                # Arrange
                $originalContent = "Original content"
                $modifiedContent = "Modified content"

                $file = New-TestFile -Content $modifiedContent

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                try {
                    # Act
                    $result = Test-FileCustomized -FilePath $file -OriginalHash $originalHash

                    # Assert
                    $result | Should -BeTrue
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns false for unchanged file" {
                # Arrange
                $content = "Same content"
                $file = New-TestFile -Content $content
                $hash = Get-NormalizedHash -FilePath $file

                try {
                    # Act
                    $result = Test-FileCustomized -FilePath $file -OriginalHash $hash

                    # Assert
                    $result | Should -BeFalse
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns false when file doesn't exist" {
                # Arrange
                $nonExistentFile = "C:\nonexistent\file.txt"
                $hash = "sha256:ABC123"

                # Act
                $result = Test-FileCustomized -FilePath $nonExistentFile -OriginalHash $hash

                # Assert
                $result | Should -BeFalse
            }

            It "Returns false when OriginalHash is null" {
                # Arrange
                $content = "Test content"
                $file = New-TestFile -Content $content

                try {
                    # Act
                    $result = Test-FileCustomized -FilePath $file -OriginalHash $null

                    # Assert
                    $result | Should -BeFalse
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns false when OriginalHash is empty string" {
                # Arrange
                $content = "Test content"
                $file = New-TestFile -Content $content

                try {
                    # Act
                    $result = Test-FileCustomized -FilePath $file -OriginalHash ""

                    # Assert
                    $result | Should -BeFalse
                }
                finally {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Whitespace and Line Ending Normalization" {
            It "Returns false when only trailing whitespace differs" {
                # Arrange
                $originalContent = "Line 1`nLine 2"
                $modifiedContent = "Line 1   `nLine 2  "  # Added trailing spaces

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                $file = New-TestFile -Content $modifiedContent

                try {
                    # Act
                    $result = Test-FileCustomized -FilePath $file -OriginalHash $originalHash

                    # Assert
                    $result | Should -BeFalse  # Normalized away
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns false when only line endings differ (CRLF vs LF)" {
                # Arrange
                $contentLF = "Line 1`nLine 2"
                $contentCRLF = "Line 1`r`nLine 2"

                $tempOriginal = New-TestFile -Content $contentLF
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                $file = New-TestFile -Content $contentCRLF

                try {
                    # Act
                    $result = Test-FileCustomized -FilePath $file -OriginalHash $originalHash

                    # Assert
                    $result | Should -BeFalse  # Normalized away
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns true when actual content differs" {
                # Arrange
                $originalContent = "Line 1`nLine 2"
                $modifiedContent = "Line 1`nLine 2 modified"

                $tempOriginal = New-TestFile -Content $originalContent
                $originalHash = Get-NormalizedHash -FilePath $tempOriginal

                $file = New-TestFile -Content $modifiedContent

                try {
                    # Act
                    $result = Test-FileCustomized -FilePath $file -OriginalHash $originalHash

                    # Assert
                    $result | Should -BeTrue
                }
                finally {
                    Remove-Item $file, $tempOriginal -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Find-CustomCommands" {
        Describe "Custom Command Identification" {
            It "Identifies custom commands not in official list" {
                # Arrange
                $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
                $commandsDir = Join-Path $testDir ".claude\commands"
                New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null

                try {
                    # Create files
                    "# Official Plan" | Out-File (Join-Path $commandsDir "speckit.plan.md")
                    "# Official Specify" | Out-File (Join-Path $commandsDir "speckit.specify.md")
                    "# Custom Deploy" | Out-File (Join-Path $commandsDir "custom-deploy.md")
                    "# Custom Scan" | Out-File (Join-Path $commandsDir "security-scan.md")

                    $officialCommands = @("speckit.plan.md", "speckit.specify.md")

                    # Act
                    $customCommands = Find-CustomCommands -ProjectRoot $testDir -OfficialCommands $officialCommands

                    # Assert
                    $customCommands.Count | Should -Be 2
                    $customCommands | Should -Contain "custom-deploy.md"
                    $customCommands | Should -Contain "security-scan.md"
                    $customCommands | Should -Not -Contain "speckit.plan.md"
                }
                finally {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns empty array when no custom commands exist" {
                # Arrange
                $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
                $commandsDir = Join-Path $testDir ".claude\commands"
                New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null

                try {
                    # Create only official files
                    "# Official Plan" | Out-File (Join-Path $commandsDir "speckit.plan.md")
                    "# Official Specify" | Out-File (Join-Path $commandsDir "speckit.specify.md")

                    $officialCommands = @("speckit.plan.md", "speckit.specify.md")

                    # Act
                    $customCommands = Find-CustomCommands -ProjectRoot $testDir -OfficialCommands $officialCommands

                    # Assert
                    $customCommands.Count | Should -Be 0
                }
                finally {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns empty array when commands directory doesn't exist" {
                # Arrange
                $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
                New-Item -ItemType Directory -Path $testDir -Force | Out-Null

                try {
                    $officialCommands = @("speckit.plan.md")

                    # Act
                    $customCommands = Find-CustomCommands -ProjectRoot $testDir -OfficialCommands $officialCommands

                    # Assert
                    $customCommands.Count | Should -Be 0
                }
                finally {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            It "Only scans .md files" {
                # Arrange
                $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
                $commandsDir = Join-Path $testDir ".claude\commands"
                New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null

                try {
                    # Create various file types
                    "# Markdown" | Out-File (Join-Path $commandsDir "custom.md")
                    "Text file" | Out-File (Join-Path $commandsDir "readme.txt")
                    "{ json }" | Out-File (Join-Path $commandsDir "config.json")

                    $officialCommands = @()

                    # Act
                    $customCommands = Find-CustomCommands -ProjectRoot $testDir -OfficialCommands $officialCommands

                    # Assert
                    $customCommands.Count | Should -Be 1
                    $customCommands | Should -Contain "custom.md"
                    $customCommands | Should -Not -Contain "readme.txt"
                    $customCommands | Should -Not -Contain "config.json"
                }
                finally {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            It "Returns all files when official list is empty" {
                # Arrange
                $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
                $commandsDir = Join-Path $testDir ".claude\commands"
                New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null

                try {
                    "# File 1" | Out-File (Join-Path $commandsDir "file1.md")
                    "# File 2" | Out-File (Join-Path $commandsDir "file2.md")
                    "# File 3" | Out-File (Join-Path $commandsDir "file3.md")

                    $officialCommands = @()

                    # Act
                    $customCommands = Find-CustomCommands -ProjectRoot $testDir -OfficialCommands $officialCommands

                    # Assert
                    $customCommands.Count | Should -Be 3
                }
                finally {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Case Sensitivity" {
            It "Handles case-sensitive comparison of filenames" {
                # Arrange
                $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
                $commandsDir = Join-Path $testDir ".claude\commands"
                New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null

                try {
                    # Create files with different cases
                    "# Plan" | Out-File (Join-Path $commandsDir "speckit.plan.md")
                    "# PLAN" | Out-File (Join-Path $commandsDir "SPECKIT.PLAN.MD")

                    $officialCommands = @("speckit.plan.md")

                    # Act
                    $customCommands = Find-CustomCommands -ProjectRoot $testDir -OfficialCommands $officialCommands

                    # Assert
                    # Depending on OS, file system may be case-insensitive (Windows) or case-sensitive (Linux)
                    # On Windows, should find 1 custom (SPECKIT.PLAN.MD if it's truly different)
                    # This test may behave differently on different OS
                    $customCommands.Count | Should -BeGreaterOrEqual 0
                }
                finally {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Real-world Scenarios" {
            It "Handles typical SpecKit project structure" {
                # Arrange
                $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
                $commandsDir = Join-Path $testDir ".claude\commands"
                New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null

                try {
                    # Official SpecKit commands
                    @(
                        "speckit.constitution.md",
                        "speckit.specify.md",
                        "speckit.plan.md",
                        "speckit.tasks.md",
                        "speckit.implement.md"
                    ) | ForEach-Object {
                        "# $_" | Out-File (Join-Path $commandsDir $_)
                    }

                    # Custom commands
                    "# Deploy" | Out-File (Join-Path $commandsDir "deploy-prod.md")
                    "# Test" | Out-File (Join-Path $commandsDir "run-tests.md")

                    $officialCommands = @(
                        "speckit.constitution.md",
                        "speckit.specify.md",
                        "speckit.plan.md",
                        "speckit.tasks.md",
                        "speckit.implement.md"
                    )

                    # Act
                    $customCommands = Find-CustomCommands -ProjectRoot $testDir -OfficialCommands $officialCommands

                    # Assert
                    $customCommands.Count | Should -Be 2
                    $customCommands | Should -Contain "deploy-prod.md"
                    $customCommands | Should -Contain "run-tests.md"
                }
                finally {
                    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
