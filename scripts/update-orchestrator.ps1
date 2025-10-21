#Requires -Version 7.0

<#
.SYNOPSIS
    SpecKit Safe Update Orchestrator - Main entry point for safe SpecKit updates.

.DESCRIPTION
    Coordinates the complete update workflow:
    1. Validates prerequisites
    2. Handles rollback if requested
    3. Loads or creates manifest
    4. Fetches target version
    5. Analyzes file states
    6. Check-only mode (show report and exit)
    7. Gets user confirmation
    8. Creates backup
    9. Downloads templates
    10. Applies updates (fail-fast)
    11. Handles conflicts (Flow A)
    12. Updates constitution (notify to run /speckit.constitution)
    13. Updates manifest
    14. Cleans up old backups
    15. Shows success summary

.PARAMETER CheckOnly
    Show what would change without applying updates

.PARAMETER Version
    Update to specific release tag (e.g., "v0.0.72" or "0.0.72")

.PARAMETER Force
    Overwrite SpecKit files even if customized (preserves custom commands)

.PARAMETER Rollback
    Restore from previous backup

.PARAMETER NoBackup
    Skip backup creation (dangerous, not recommended)

.EXAMPLE
    .\update-orchestrator.ps1 -CheckOnly
    Check for updates without applying changes

.EXAMPLE
    .\update-orchestrator.ps1
    Interactive update with confirmation

.EXAMPLE
    .\update-orchestrator.ps1 -Version v0.0.72
    Update to specific version

.EXAMPLE
    .\update-orchestrator.ps1 -Rollback
    Restore from previous backup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$CheckOnly,

    [Parameter(Mandatory=$false)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$Rollback,

    [Parameter(Mandatory=$false)]
    [switch]$NoBackup
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Store script start time
$startTime = Get-Date

# ========================================
# IMPORT MODULES
# ========================================

Write-Host ""
Write-Host "SpecKit Safe Update v1.0" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# ========================================
# MODULE IMPORTS
# ========================================
Write-Verbose "Importing PowerShell modules..."

try {
    $modulesPath = Join-Path $PSScriptRoot "modules"

    # Module Dependency Management (Tiered Import Structure)
    # IMPORTANT: Modules MUST NOT import other modules (creates scope isolation issues)
    # All imports are managed here in dependency order to ensure functions are available in orchestrator scope
    #
    # Dependency Graph:
    # - TIER 0 (no dependencies): HashUtils, GitHubApiClient, VSCodeIntegration
    # - TIER 1 (depends on Tier 0): ManifestManager (uses HashUtils, GitHubApiClient)
    # - TIER 2 (depends on Tier 1): BackupManager (uses ManifestManager), ConflictDetector (uses HashUtils, ManifestManager)

    # TIER 0: Foundation modules (no dependencies)
    # These must be imported first as other modules depend on them
    Import-Module (Join-Path $modulesPath "HashUtils.psm1") -Force -WarningAction SilentlyContinue
    Import-Module (Join-Path $modulesPath "GitHubApiClient.psm1") -Force -WarningAction SilentlyContinue
    Import-Module (Join-Path $modulesPath "VSCodeIntegration.psm1") -Force -WarningAction SilentlyContinue

    # TIER 1: Modules depending on Tier 0
    # ManifestManager uses HashUtils.Get-NormalizedHash and GitHubApiClient functions
    Import-Module (Join-Path $modulesPath "ManifestManager.psm1") -Force -WarningAction SilentlyContinue

    # TIER 2: Modules depending on Tier 1
    # BackupManager uses ManifestManager functions
    # ConflictDetector uses HashUtils and ManifestManager functions
    Import-Module (Join-Path $modulesPath "BackupManager.psm1") -Force -WarningAction SilentlyContinue
    Import-Module (Join-Path $modulesPath "ConflictDetector.psm1") -Force -WarningAction SilentlyContinue

    Write-Verbose "Modules imported successfully (6 modules in 3 tiers)"
}
catch {
    Write-Error "Failed to import modules: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}

# ========================================
# HELPER IMPORTS
# ========================================
Write-Verbose "Loading helper scripts..."

try {
    $helpersPath = Join-Path $PSScriptRoot "helpers"

    . (Join-Path $helpersPath "Invoke-PreUpdateValidation.ps1")
    . (Join-Path $helpersPath "Show-UpdateSummary.ps1")
    . (Join-Path $helpersPath "Show-UpdateReport.ps1")
    . (Join-Path $helpersPath "Get-UpdateConfirmation.ps1")
    . (Join-Path $helpersPath "Invoke-ConflictResolutionWorkflow.ps1")
    . (Join-Path $helpersPath "Invoke-ThreeWayMerge.ps1")
    . (Join-Path $helpersPath "Invoke-RollbackWorkflow.ps1")

    Write-Verbose "Helpers loaded successfully"
}
catch {
    Write-Error "Failed to load helper scripts: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Verbose "All modules and helpers loaded successfully"

# ========================================
# MAIN EXECUTION FLOW
# ========================================

# Variables to track for rollback
$backupPath = $null
$projectRoot = $PWD

try {
    # ========================================
    # STEP 1: Validate Prerequisites
    # ========================================
    Write-Verbose "Step 1: Validating prerequisites..."

    Invoke-PreUpdateValidation -ProjectRoot $projectRoot

    # ========================================
    # STEP 2: Handle Rollback if Requested
    # ========================================
    if ($Rollback) {
        Write-Verbose "Step 2: Rollback mode requested"
        Invoke-RollbackWorkflow -ProjectRoot $projectRoot
        exit 0
    }

    Write-Verbose "Step 2: No rollback requested, continuing with update"

    # ========================================
    # STEP 3: Load Manifest (or prepare to create one)
    # ========================================
    Write-Verbose "Step 3: Loading manifest..."
    Write-Host "Loading manifest..." -ForegroundColor Cyan

    $manifest = Get-SpecKitManifest -ProjectRoot $projectRoot
    $needsManifestCreation = $false

    if (-not $manifest) {
        Write-Host "No manifest found. Will create after fetching target version..." -ForegroundColor Yellow
        Write-Host ""
        $needsManifestCreation = $true
    }
    else {
        Write-Host "Manifest loaded: $($manifest.speckit_version)" -ForegroundColor Green
        Write-Host ""
    }

    # ========================================
    # STEP 4: Fetch Target Version
    # ========================================
    Write-Verbose "Step 4: Fetching target version..."
    Write-Host "Checking for updates..." -ForegroundColor Cyan

    try {
        if ($Version) {
            # Normalize version (add 'v' prefix if missing)
            $targetVersion = $Version
            if (-not $targetVersion.StartsWith('v')) {
                $targetVersion = "v$targetVersion"
            }

            Write-Verbose "Explicit version specified: $targetVersion"
            Write-Host "Target version: $targetVersion (specified)" -ForegroundColor Cyan
            $targetRelease = Get-SpecKitRelease -Version $targetVersion

            # Defensive null check for explicit version path
            if (-not $targetRelease) {
                throw "GitHub API returned empty response for version $targetVersion"
            }

            if (-not $targetRelease.tag_name) {
                throw "Release information missing version identifier (tag_name property)"
            }

            Write-Verbose "Explicit version validated: $($targetRelease.tag_name)"
        }
        else {
            Write-Verbose "No version specified, fetching latest from GitHub"
            $targetRelease = Get-LatestSpecKitRelease

            # Defensive null check after getting latest release
            if (-not $targetRelease) {
                throw "GitHub API returned empty response when fetching latest release"
            }

            if (-not $targetRelease.tag_name) {
                throw "Release information missing version identifier (tag_name property)"
            }

            Write-Verbose "Target version validated: $($targetRelease.tag_name)"
            Write-Host "Latest version: $($targetRelease.tag_name)" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Error "Failed to fetch release information: $($_.Exception.Message)"
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor Yellow
        Write-Host "  - No internet connection" -ForegroundColor Yellow
        Write-Host "  - GitHub API rate limit exceeded" -ForegroundColor Yellow
        Write-Host "  - Invalid version specified" -ForegroundColor Yellow
        Write-Host ""
        exit 3
    }

    # ========================================
    # STEP 3.5: Create Manifest if needed (with placeholder version)
    # ========================================
    if ($needsManifestCreation) {
        Write-Verbose "Creating new manifest with placeholder version v0.0.0"
        Write-Host ""
        Write-Host "Creating new manifest (version unknown - will update to $($targetRelease.tag_name))" -ForegroundColor Yellow
        Write-Host "This will scan your current .specify/ and .claude/ directories" -ForegroundColor Yellow
        Write-Host "and mark all files as customized (safe default)." -ForegroundColor Yellow
        Write-Host ""

        # Create manifest with placeholder version (unknown starting point), assuming all files are customized
        $manifest = New-SpecKitManifest -ProjectRoot $projectRoot -Version "v0.0.0" -AssumeAllCustomized

        Write-Host "Manifest created successfully" -ForegroundColor Green
        Write-Host "Current version marked as: $($manifest.speckit_version) (placeholder - will update to $($targetRelease.tag_name))" -ForegroundColor Green
        Write-Host ""
    }

    # Check if already up to date
    if ($manifest.speckit_version -eq $targetRelease.tag_name -and -not $Force) {
        Write-Host ""
        Write-Host "Already up to date ($($manifest.speckit_version))" -ForegroundColor Green
        Write-Host ""
        exit 0
    }

    Write-Host ""

    # ========================================
    # STEP 5: Analyze File States
    # ========================================
    Write-Verbose "Step 5: Analyzing file states..."
    Write-Host "Analyzing file changes..." -ForegroundColor Cyan

    # Download templates for comparison
    $templates = Download-SpecKitTemplates -Version $targetRelease.tag_name -DestinationPath $projectRoot

    # Get all file states
    $fileStates = Get-AllFileStates -Manifest $manifest -UpstreamTemplates $templates -ProjectRoot $projectRoot

    # Find custom commands
    $officialCommands = Get-OfficialSpecKitCommands -Version $targetRelease.tag_name
    $customFiles = Find-CustomCommands -ProjectRoot $projectRoot -OfficialCommands $officialCommands

    Write-Host "Analysis complete" -ForegroundColor Green
    Write-Host ""

    # ========================================
    # STEP 6: Check-Only Mode
    # ========================================
    if ($CheckOnly) {
        Write-Verbose "Step 6: Check-only mode - showing report and exiting"

        Show-UpdateReport -FileStates $fileStates -CurrentVersion $manifest.speckit_version -TargetVersion $targetRelease.tag_name -CustomFiles $customFiles

        # Clean up temporary manifest if we created one (don't leave repo in dirty state)
        if ($needsManifestCreation) {
            $manifestPath = Join-Path $projectRoot ".specify/manifest.json"
            if (Test-Path $manifestPath) {
                Write-Verbose "Removing temporary manifest created for check-only mode"
                Remove-Item $manifestPath -Force
            }
        }

        exit 0
    }

    Write-Verbose "Step 6: Not in check-only mode, continuing with update"

    # ========================================
    # STEP 7: Get User Confirmation
    # ========================================
    Write-Verbose "Step 7: Getting user confirmation..."

    $confirmed = Get-UpdateConfirmation -FileStates $fileStates -CurrentVersion $manifest.speckit_version -TargetVersion $targetRelease.tag_name

    if (-not $confirmed) {
        Write-Host "Update cancelled by user." -ForegroundColor Yellow
        Write-Host ""
        exit 5
    }

    Write-Host "Update confirmed. Proceeding..." -ForegroundColor Green
    Write-Host ""

    # ========================================
    # STEP 8: Create Backup
    # ========================================
    if (-not $NoBackup) {
        Write-Verbose "Step 8: Creating backup..."
        Write-Host "Creating backup..." -ForegroundColor Cyan

        try {
            $backupPath = New-SpecKitBackup -ProjectRoot $projectRoot -FromVersion $manifest.speckit_version -ToVersion $targetRelease.tag_name

            Write-Host "Backup created: $backupPath" -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Error "Failed to create backup: $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-Verbose "Step 8: Backup skipped (--no-backup flag)"
        Write-Host "WARNING: Skipping backup (--no-backup flag)" -ForegroundColor Red
        Write-Host ""
    }

    # ========================================
    # STEP 9: Templates Already Downloaded
    # ========================================
    Write-Verbose "Step 9: Templates already downloaded in step 5"

    # ========================================
    # STEP 10: Apply Updates (Fail-Fast)
    # ========================================
    Write-Verbose "Step 10: Applying updates..."
    Write-Host "Applying updates..." -ForegroundColor Cyan
    Write-Host ""

    $updateResult = [PSCustomObject]@{
        FilesUpdated = @()
        FilesPreserved = @()
        ConflictsResolved = @()
        ConflictsSkipped = @()
        CustomFiles = $customFiles
        CustomCommandsAdded = @()
        CommandsRemoved = @()
        ConstitutionUpdateNeeded = $false
        BackupPath = $backupPath
    }

    # Apply updates based on file states
    foreach ($fileState in $fileStates) {
        $filePath = Join-Path $projectRoot $fileState.path

        switch ($fileState.action) {
            'update' {
                # File is not customized or force flag is set - update it
                try {
                    Write-Host "  Updating: $($fileState.path)" -ForegroundColor Green

                    # Ensure directory exists
                    $directory = [System.IO.Path]::GetDirectoryName($filePath)
                    if (-not (Test-Path $directory)) {
                        New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    }

                    # Write new content
                    $templates[$fileState.path] | Out-File -FilePath $filePath -Encoding utf8 -Force

                    $updateResult.FilesUpdated += $fileState.path
                }
                catch {
                    Write-Error "Failed to update $($fileState.path): $($_.Exception.Message)"
                    throw
                }
            }

            'preserve' {
                # File is customized and has no upstream changes - preserve it
                Write-Host "  Preserving: $($fileState.path) (customized)" -ForegroundColor Yellow
                $updateResult.FilesPreserved += $fileState.path
            }

            'add' {
                # New file in upstream - add it
                try {
                    Write-Host "  Adding: $($fileState.path)" -ForegroundColor Cyan

                    $directory = [System.IO.Path]::GetDirectoryName($filePath)
                    if (-not (Test-Path $directory)) {
                        New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    }

                    $templates[$fileState.path] | Out-File -FilePath $filePath -Encoding utf8 -Force

                    $updateResult.CustomCommandsAdded += $fileState.path
                }
                catch {
                    Write-Error "Failed to add $($fileState.path): $($_.Exception.Message)"
                    throw
                }
            }

            'remove' {
                # File removed from upstream - remove it
                if (Test-Path $filePath) {
                    Write-Host "  Removing: $($fileState.path) (obsolete)" -ForegroundColor DarkGray
                    Remove-Item $filePath -Force
                    $updateResult.CommandsRemoved += $fileState.path
                }
            }

            'merge' {
                # Conflict - will handle in step 11
                Write-Verbose "  Conflict detected: $($fileState.path) (will handle in step 11)"
            }

            default {
                # Skip - no action needed
                Write-Verbose "  Skipping: $($fileState.path) (action: $($fileState.action))"
            }
        }
    }

    Write-Host ""
    Write-Host "Updates applied successfully" -ForegroundColor Green
    Write-Host ""

    # ========================================
    # STEP 11: Handle Conflicts (Flow A)
    # ========================================
    $conflicts = @($fileStates | Where-Object { $_.action -eq 'merge' })

    if ($conflicts.Count -gt 0) {
        Write-Verbose "Step 11: Handling $($conflicts.Count) conflict(s)..."

        $conflictResult = Invoke-ConflictResolutionWorkflow -Conflicts $conflicts -Templates $templates -ProjectRoot $projectRoot

        $updateResult.ConflictsResolved = $conflictResult.Resolved + $conflictResult.KeptMine + $conflictResult.UsedNew
        $updateResult.ConflictsSkipped = $conflictResult.Skipped
    }
    else {
        Write-Verbose "Step 11: No conflicts to resolve"
    }

    # ========================================
    # STEP 12: Update Constitution (Notify)
    # ========================================
    Write-Verbose "Step 12: Checking if constitution needs update..."

    # Check if constitution.md was updated or has conflicts
    $constitutionUpdated = $updateResult.FilesUpdated -contains '.specify/memory/constitution.md'
    $constitutionConflict = $updateResult.ConflictsResolved -contains '.specify/memory/constitution.md'

    if ($constitutionUpdated -or $constitutionConflict) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Constitution Update Required" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "The constitution template has been updated." -ForegroundColor Yellow
        Write-Host "Please run the following command to review changes:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  /speckit.constitution" -ForegroundColor Green
        Write-Host ""
        Write-Host "This will help you merge new sections while preserving" -ForegroundColor Yellow
        Write-Host "your project-specific governance rules." -ForegroundColor Yellow
        Write-Host ""

        $updateResult.ConstitutionUpdateNeeded = $true
    }

    # ========================================
    # STEP 13: Update Manifest
    # ========================================
    Write-Verbose "Step 13: Updating manifest..."
    Write-Host "Updating manifest..." -ForegroundColor Cyan

    try {
        Update-ManifestVersion -ProjectRoot $projectRoot -NewVersion $targetRelease.tag_name
        Update-FileHashes -ProjectRoot $projectRoot -FileStates $fileStates

        Write-Host "Manifest updated successfully" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Error "Failed to update manifest: $($_.Exception.Message)"
        throw
    }

    # ========================================
    # STEP 14: Cleanup Old Backups
    # ========================================
    Write-Verbose "Step 14: Cleaning up old backups..."

    try {
        $oldBackups = Remove-OldBackups -ProjectRoot $projectRoot -KeepCount 5 -WhatIf

        if ($oldBackups -and $oldBackups.Count -gt 0) {
            Write-Host "Old backups to clean up: $($oldBackups.Count)" -ForegroundColor Yellow

            # Ask user if they want to clean up
            $context = Get-ExecutionContext
            $cleanup = $false

            if ($context -eq 'vscode-extension') {
                $choice = Show-QuickPick -Prompt "Delete $($oldBackups.Count) old backup(s)?" -Options @("Yes", "No")
                $cleanup = ($choice -eq "Yes")
            }
            else {
                Write-Host "Delete old backups? (Y/n): " -NoNewline -ForegroundColor Cyan
                $response = Read-Host
                $cleanup = ($response -ne 'n' -and $response -ne 'N')
            }

            if ($cleanup) {
                Remove-OldBackups -ProjectRoot $projectRoot -KeepCount 5
                Write-Host "Old backups cleaned up" -ForegroundColor Green
            }
            else {
                Write-Host "Keeping old backups" -ForegroundColor Yellow
            }

            Write-Host ""
        }
    }
    catch {
        Write-Warning "Failed to cleanup old backups: $($_.Exception.Message)"
    }

    # ========================================
    # STEP 15: Show Success Summary
    # ========================================
    Write-Verbose "Step 15: Showing success summary..."

    Show-UpdateSummary -Result $updateResult -FromVersion $manifest.speckit_version -ToVersion $targetRelease.tag_name

    # Calculate elapsed time
    $elapsedTime = (Get-Date) - $startTime
    Write-Host "Update completed in $([math]::Round($elapsedTime.TotalSeconds, 2)) seconds" -ForegroundColor DarkGray
    Write-Host ""

    exit 0
}
catch {
    # ========================================
    # ERROR HANDLING: Automatic Rollback
    # ========================================
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Update Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""

    # Automatic rollback if backup exists
    if (-not $NoBackup -and $backupPath -and (Test-Path $backupPath)) {
        Write-Host "Attempting automatic rollback..." -ForegroundColor Yellow
        Write-Host ""

        try {
            Invoke-AutomaticRollback -ProjectRoot $projectRoot -BackupPath $backupPath

            Write-Host ""
            Write-Host "Rollback completed successfully" -ForegroundColor Green
            Write-Host "Your files have been restored to their previous state" -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Host ""
            Write-Host "Rollback failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Your backup is still available at: $backupPath" -ForegroundColor Yellow
            Write-Host "You can manually restore by running:" -ForegroundColor Yellow
            Write-Host "  /speckit-update --rollback" -ForegroundColor Yellow
            Write-Host ""
        }

        exit 6
    }
    else {
        Write-Host "No backup available for automatic rollback" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}
