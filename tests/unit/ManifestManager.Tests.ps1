#Requires -Version 7.0

<#
.SYNOPSIS
    Unit tests for ManifestManager module.

.DESCRIPTION
    Comprehensive tests for all ManifestManager functions including:
    - Get-SpecKitManifest
    - New-SpecKitManifest
    - Get-OfficialSpecKitCommands
    - Update-ManifestVersion
    - Add-TrackedFile
    - Remove-TrackedFile
    - Update-FileHashes
#>

BeforeAll {
    # Import required modules
    $modulesPath = Join-Path $PSScriptRoot "..\..\scripts\modules"
    Import-Module (Join-Path $modulesPath "HashUtils.psm1") -Force
    Import-Module (Join-Path $modulesPath "GitHubApiClient.psm1") -Force
    Import-Module (Join-Path $modulesPath "ManifestManager.psm1") -Force

    # Helper function to create a temporary test project
    function New-TestProject {
        param(
            [switch]$WithManifest,
            [switch]$WithCommands,
            [switch]$WithSpecifyFiles
        )

        $testDir = Join-Path $env:TEMP "speckit-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        # Create .specify directory
        $specifyDir = Join-Path $testDir ".specify"
        New-Item -ItemType Directory -Path $specifyDir -Force | Out-Null

        if ($WithManifest) {
            # Create a valid manifest
            $manifest = @{
                version = "1.0"
                speckit_version = "v0.0.45"
                initialized_at = "2025-01-01T10:00:00Z"
                last_updated = "2025-01-01T10:00:00Z"
                agent = "claude-code"
                speckit_commands = @(
                    "speckit.constitution.md",
                    "speckit.specify.md",
                    "speckit.plan.md"
                )
                tracked_files = @(
                    @{
                        path = ".claude/commands/speckit.specify.md"
                        original_hash = "sha256:ABC123"
                        customized = $false
                        is_official = $true
                    }
                )
                custom_files = @()
                backup_history = @()
            }

            $manifestPath = Join-Path $specifyDir "manifest.json"
            $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding utf8
        }

        if ($WithCommands) {
            # Create .claude/commands directory with some files
            $commandsDir = Join-Path $testDir ".claude\commands"
            New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null

            "# SpecKit Specify Command" | Set-Content (Join-Path $commandsDir "speckit.specify.md") -Encoding utf8
            "# SpecKit Plan Command" | Set-Content (Join-Path $commandsDir "speckit.plan.md") -Encoding utf8
            "# Custom Deploy Command" | Set-Content (Join-Path $commandsDir "custom-deploy.md") -Encoding utf8
        }

        if ($WithSpecifyFiles) {
            # Create some files in .specify directory
            $memoryDir = Join-Path $specifyDir "memory"
            New-Item -ItemType Directory -Path $memoryDir -Force | Out-Null
            "# Constitution" | Set-Content (Join-Path $memoryDir "constitution.md") -Encoding utf8

            $templatesDir = Join-Path $specifyDir "templates"
            New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
            "# Spec Template" | Set-Content (Join-Path $templatesDir "spec-template.md") -Encoding utf8
        }

        return $testDir
    }
}

AfterAll {
    # Cleanup any remaining test directories
    Get-ChildItem $env:TEMP -Filter "speckit-test-*" -Directory | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "ManifestManager" {
    Context "Get-SpecKitManifest" {
        It "Returns null when manifest doesn't exist" {
            $testDir = New-TestProject
            try {
                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $manifest | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Returns manifest when it exists" {
            $testDir = New-TestProject -WithManifest
            try {
                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $manifest | Should -Not -BeNullOrEmpty
                $manifest.speckit_version | Should -Be "v0.0.45"
                $manifest.version | Should -Be "1.0"
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Throws when manifest is corrupted" {
            $testDir = New-TestProject
            try {
                # Create a corrupted manifest (invalid JSON)
                $manifestPath = Join-Path $testDir ".specify\manifest.json"
                "{ invalid json" | Set-Content $manifestPath

                { Get-SpecKitManifest -ProjectRoot $testDir } | Should -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Throws when manifest has missing version field" {
            $testDir = New-TestProject
            try {
                # Create manifest without version field
                $manifestPath = Join-Path $testDir ".specify\manifest.json"
                @{ speckit_version = "v0.0.45" } | ConvertTo-Json | Set-Content $manifestPath

                { Get-SpecKitManifest -ProjectRoot $testDir } | Should -Throw "*version*"
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Throws when manifest has unsupported schema version" {
            $testDir = New-TestProject
            try {
                # Create manifest with unsupported version
                $manifestPath = Join-Path $testDir ".specify\manifest.json"
                @{ version = "2.0"; speckit_version = "v0.0.45" } | ConvertTo-Json | Set-Content $manifestPath

                { Get-SpecKitManifest -ProjectRoot $testDir } | Should -Throw "*Unsupported*"
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Uses current directory when ProjectRoot not specified" {
            $testDir = New-TestProject -WithManifest
            try {
                Push-Location $testDir
                $manifest = Get-SpecKitManifest
                $manifest | Should -Not -BeNullOrEmpty
                Pop-Location
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }
    }

    Context "New-SpecKitManifest" {
        It "Creates manifest with valid structure" {
            $testDir = New-TestProject -WithCommands -WithSpecifyFiles
            try {
                # Mock Get-OfficialSpecKitCommands
                Mock Get-OfficialSpecKitCommands {
                    return @("speckit.specify.md", "speckit.plan.md")
                }

                $manifest = New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72"

                $manifest | Should -Not -BeNullOrEmpty
                $manifest.version | Should -Be "1.0"
                $manifest.speckit_version | Should -Be "v0.0.72"
                $manifest.agent | Should -Be "claude-code"
                $manifest.tracked_files | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Marks all files as customized when AssumeAllCustomized is set" {
            $testDir = New-TestProject -WithCommands -WithSpecifyFiles
            try {
                Mock Get-OfficialSpecKitCommands {
                    return @("speckit.specify.md", "speckit.plan.md")
                }

                $manifest = New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72" -AssumeAllCustomized

                $manifest.tracked_files | ForEach-Object {
                    $_.customized | Should -Be $true
                }
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Distinguishes between official and custom commands" {
            $testDir = New-TestProject -WithCommands
            try {
                Mock Get-OfficialSpecKitCommands {
                    return @("speckit.specify.md", "speckit.plan.md")
                }

                $manifest = New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72"

                # Should have custom-deploy.md in custom_files
                $manifest.custom_files | Should -Contain ".claude/commands/custom-deploy.md"

                # Should have official commands in tracked_files
                $officialFiles = $manifest.tracked_files | Where-Object { $_.is_official }
                $officialFiles.path | Should -Contain ".claude/commands/speckit.specify.md"
                $officialFiles.path | Should -Contain ".claude/commands/speckit.plan.md"
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Computes normalized hashes for all tracked files" {
            $testDir = New-TestProject -WithCommands
            try {
                Mock Get-OfficialSpecKitCommands {
                    return @("speckit.specify.md")
                }

                $manifest = New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72"

                $manifest.tracked_files | ForEach-Object {
                    $_.original_hash | Should -Match "^sha256:[A-F0-9]+$"
                }
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Excludes backups and manifest.json from tracked files" {
            $testDir = New-TestProject -WithManifest -WithSpecifyFiles
            try {
                # Create a backup directory
                $backupDir = Join-Path $testDir ".specify\backups\20250101-120000"
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                "backup content" | Set-Content (Join-Path $backupDir "test.md")

                Mock Get-OfficialSpecKitCommands {
                    return @()
                }

                $manifest = New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72"

                # Should not include manifest.json or backup files
                $manifest.tracked_files.path | Should -Not -Contain ".specify/manifest.json"
                $manifest.tracked_files.path | Should -Not -Match "backups"
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Sets initialized_at and last_updated timestamps" {
            $testDir = New-TestProject -WithCommands
            try {
                Mock Get-OfficialSpecKitCommands {
                    return @()
                }

                $manifest = New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72"

                $manifest.initialized_at | Should -Not -BeNullOrEmpty
                $manifest.last_updated | Should -Not -BeNullOrEmpty

                # Should be valid ISO 8601 format
                { [DateTime]::Parse($manifest.initialized_at) } | Should -Not -Throw
                { [DateTime]::Parse($manifest.last_updated) } | Should -Not -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Creates manifest file on disk" {
            $testDir = New-TestProject -WithCommands
            try {
                Mock Get-OfficialSpecKitCommands {
                    return @()
                }

                New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72"

                $manifestPath = Join-Path $testDir ".specify\manifest.json"
                Test-Path $manifestPath | Should -Be $true

                # Should be valid JSON
                $content = Get-Content $manifestPath -Raw
                { $content | ConvertFrom-Json } | Should -Not -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }
    }

    Context "Get-OfficialSpecKitCommands" {
        It "Returns list of official commands from GitHub" {
            Mock Download-SpecKitTemplates -ModuleName ManifestManager {
                return @{
                    '.claude/commands/speckit.constitution.md' = "content"
                    '.claude/commands/speckit.specify.md' = "content"
                    '.claude/commands/speckit.plan.md' = "content"
                }
            }

            $commands = Get-OfficialSpecKitCommands -SpecKitVersion "v0.0.99"

            $commands | Should -Not -BeNullOrEmpty
            $commands | Should -Contain "speckit.constitution.md"
            $commands | Should -Contain "speckit.specify.md"
            $commands | Should -Contain "speckit.plan.md"
        }

        It "Caches results for performance" {
            Mock Download-SpecKitTemplates -ModuleName ManifestManager {
                return @{
                    '.claude/commands/speckit.specify.md' = "content"
                }
            }

            # First call
            $commands1 = Get-OfficialSpecKitCommands -SpecKitVersion "v0.0.98"

            # Second call should use cache (Download-SpecKitTemplates called only once)
            $commands2 = Get-OfficialSpecKitCommands -SpecKitVersion "v0.0.98"

            Should -Invoke Download-SpecKitTemplates -ModuleName ManifestManager -Times 1 -Exactly
            $commands1 | Should -Be $commands2
        }

        It "Returns fallback list when GitHub API fails" {
            Mock Download-SpecKitTemplates -ModuleName ManifestManager {
                throw "Network error"
            }

            $commands = Get-OfficialSpecKitCommands -SpecKitVersion "v0.0.97"

            # Should still return a list (fallback)
            $commands | Should -Not -BeNullOrEmpty
            $commands | Should -Contain "speckit.constitution.md"
            $commands | Should -Contain "speckit.specify.md"
        }

        It "Handles templates with different path formats" {
            Mock Download-SpecKitTemplates -ModuleName ManifestManager {
                return @{
                    'claude/commands/speckit.specify.md' = "content"  # Without leading dot
                    '.claude/commands/speckit.plan.md' = "content"     # With leading dot
                }
            }

            $commands = Get-OfficialSpecKitCommands -SpecKitVersion "v0.0.96"

            $commands | Should -Contain "speckit.specify.md"
            $commands | Should -Contain "speckit.plan.md"
        }
    }

    Context "Update-ManifestVersion" {
        It "Updates speckit_version field" {
            $testDir = New-TestProject -WithManifest
            try {
                Update-ManifestVersion -ProjectRoot $testDir -NewVersion "v0.0.72"

                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $manifest.speckit_version | Should -Be "v0.0.72"
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Updates last_updated timestamp" {
            $testDir = New-TestProject -WithManifest
            try {
                $before = Get-Date
                Start-Sleep -Milliseconds 100

                Update-ManifestVersion -ProjectRoot $testDir -NewVersion "v0.0.72"

                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $updated = [DateTime]::Parse($manifest.last_updated)
                $updated | Should -BeGreaterThan $before
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Preserves other manifest fields" {
            $testDir = New-TestProject -WithManifest
            try {
                $originalManifest = Get-SpecKitManifest -ProjectRoot $testDir

                Update-ManifestVersion -ProjectRoot $testDir -NewVersion "v0.0.72"

                $updatedManifest = Get-SpecKitManifest -ProjectRoot $testDir
                $updatedManifest.version | Should -Be $originalManifest.version
                $updatedManifest.initialized_at | Should -Be $originalManifest.initialized_at
                $updatedManifest.tracked_files.Count | Should -Be $originalManifest.tracked_files.Count
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Throws when manifest doesn't exist" {
            $testDir = New-TestProject
            try {
                { Update-ManifestVersion -ProjectRoot $testDir -NewVersion "v0.0.72" } | Should -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }
    }

    Context "Add-TrackedFile" {
        It "Adds file to tracked_files array" {
            $testDir = New-TestProject -WithManifest
            try {
                $hash = "sha256:DEF456"
                Add-TrackedFile -ProjectRoot $testDir -FilePath ".claude/commands/new.md" -Hash $hash -IsOfficial $true

                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $newFile = $manifest.tracked_files | Where-Object { $_.path -eq ".claude/commands/new.md" }

                $newFile | Should -Not -BeNullOrEmpty
                $newFile.original_hash | Should -Be $hash
                $newFile.is_official | Should -Be $true
                $newFile.customized | Should -Be $false
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Preserves existing tracked files" {
            $testDir = New-TestProject -WithManifest
            try {
                $originalManifest = Get-SpecKitManifest -ProjectRoot $testDir
                $originalCount = $originalManifest.tracked_files.Count

                Add-TrackedFile -ProjectRoot $testDir -FilePath ".claude/commands/new.md" -Hash "sha256:DEF456" -IsOfficial $true

                $updatedManifest = Get-SpecKitManifest -ProjectRoot $testDir
                $updatedManifest.tracked_files.Count | Should -Be ($originalCount + 1)
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Throws when manifest doesn't exist" {
            $testDir = New-TestProject
            try {
                { Add-TrackedFile -ProjectRoot $testDir -FilePath "test.md" -Hash "sha256:ABC" -IsOfficial $true } | Should -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }
    }

    Context "Remove-TrackedFile" {
        It "Removes file from tracked_files array" {
            $testDir = New-TestProject -WithManifest
            try {
                Remove-TrackedFile -ProjectRoot $testDir -FilePath ".claude/commands/speckit.specify.md"

                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $removedFile = $manifest.tracked_files | Where-Object { $_.path -eq ".claude/commands/speckit.specify.md" }

                $removedFile | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Doesn't error when file not in manifest" {
            $testDir = New-TestProject -WithManifest
            try {
                { Remove-TrackedFile -ProjectRoot $testDir -FilePath "nonexistent.md" } | Should -Not -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Throws when manifest doesn't exist" {
            $testDir = New-TestProject
            try {
                { Remove-TrackedFile -ProjectRoot $testDir -FilePath "test.md" } | Should -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }
    }

    Context "Update-FileHashes" {
        It "Recomputes hashes for all tracked files" {
            $testDir = New-TestProject -WithManifest -WithCommands
            try {
                # Modify the file content
                "# Modified content" | Set-Content (Join-Path $testDir ".claude\commands\speckit.specify.md") -Encoding utf8

                Update-FileHashes -ProjectRoot $testDir

                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $file = $manifest.tracked_files | Where-Object { $_.path -eq ".claude/commands/speckit.specify.md" }

                # Hash should be different from original
                $file.customized | Should -Be $true
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Sets customized flag to false when file matches original" {
            $testDir = New-TestProject -WithCommands
            try {
                # Create manifest with a file
                Mock Get-OfficialSpecKitCommands {
                    return @("speckit.specify.md")
                }

                $manifest = New-SpecKitManifest -ProjectRoot $testDir -SpecKitVersion "v0.0.72"

                # File should not be customized initially
                $file = $manifest.tracked_files | Where-Object { $_.path -eq ".claude/commands/speckit.specify.md" }
                $file.customized | Should -Be $false

                # Modify and update
                "# Modified" | Set-Content (Join-Path $testDir ".claude\commands\speckit.specify.md") -Encoding utf8
                Update-FileHashes -ProjectRoot $testDir

                # Should now be customized
                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $file = $manifest.tracked_files | Where-Object { $_.path -eq ".claude/commands/speckit.specify.md" }
                $file.customized | Should -Be $true
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Updates last_updated timestamp" {
            $testDir = New-TestProject -WithManifest
            try {
                $before = Get-Date
                Start-Sleep -Milliseconds 100

                Update-FileHashes -ProjectRoot $testDir

                $manifest = Get-SpecKitManifest -ProjectRoot $testDir
                $updated = [DateTime]::Parse($manifest.last_updated)
                $updated | Should -BeGreaterThan $before
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Warns about tracked files that don't exist" {
            $testDir = New-TestProject -WithManifest
            try {
                # The manifest references a file that doesn't exist
                Update-FileHashes -ProjectRoot $testDir -WarningVariable warnings

                $warnings | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }

        It "Throws when manifest doesn't exist" {
            $testDir = New-TestProject
            try {
                { Update-FileHashes -ProjectRoot $testDir } | Should -Throw
            }
            finally {
                Remove-Item $testDir -Recurse -Force
            }
        }
    }
}
