#Requires -Version 7.0

<#
.SYNOPSIS
    Gets user confirmation to proceed with update.

.DESCRIPTION
    Displays summary of changes and prompts user for confirmation using
    VSCode Quick Pick or console input depending on execution context.

.PARAMETER FileStates
    Array of FileState objects containing update information.

.PARAMETER CurrentVersion
    Current SpecKit version (e.g., "v0.0.45")

.PARAMETER TargetVersion
    Target SpecKit version (e.g., "v0.0.72")

.OUTPUTS
    Boolean: $true if user confirmed, $false if user cancelled.
#>

function Get-UpdateConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$FileStates,

        [Parameter(Mandatory=$false)]
        [string]$CurrentVersion = "unknown",

        [Parameter(Mandatory=$false)]
        [string]$TargetVersion = "latest"
    )

    # Count different types of changes
    $toUpdate = @($FileStates | Where-Object { $_.action -eq 'update' })
    $toPreserve = @($FileStates | Where-Object { $_.action -eq 'preserve' })
    $conflicts = @($FileStates | Where-Object { $_.action -eq 'merge' })
    $toAdd = @($FileStates | Where-Object { $_.action -eq 'add' })
    $toRemove = @($FileStates | Where-Object { $_.action -eq 'remove' })

    # Display update summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "SpecKit Update Preview" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current Version: $CurrentVersion" -ForegroundColor Yellow
    Write-Host "Target Version:  $TargetVersion" -ForegroundColor Green
    Write-Host ""

    # Show what will happen
    if ($toUpdate.Count -gt 0) {
        Write-Host "Files to update: $($toUpdate.Count)" -ForegroundColor Green
        if ($toUpdate.Count -le 10) {
            foreach ($file in $toUpdate) {
                Write-Host "  + $($file.path)" -ForegroundColor Green
            }
        }
        else {
            # Show first 5 and last 5
            for ($i = 0; $i -lt 5; $i++) {
                Write-Host "  + $($toUpdate[$i].path)" -ForegroundColor Green
            }
            Write-Host "  ... and $($toUpdate.Count - 10) more files ..." -ForegroundColor DarkGray
            for ($i = $toUpdate.Count - 5; $i -lt $toUpdate.Count; $i++) {
                Write-Host "  + $($toUpdate[$i].path)" -ForegroundColor Green
            }
        }
        Write-Host ""
    }

    if ($toPreserve.Count -gt 0) {
        Write-Host "Files to preserve (customized): $($toPreserve.Count)" -ForegroundColor Yellow
        if ($toPreserve.Count -le 5) {
            foreach ($file in $toPreserve) {
                Write-Host "  -> $($file.path)" -ForegroundColor Yellow
            }
        }
        Write-Host ""
    }

    if ($conflicts.Count -gt 0) {
        Write-Host "Conflicts requiring manual merge: $($conflicts.Count)" -ForegroundColor Red
        foreach ($file in $conflicts) {
            Write-Host "  ! $($file.path)" -ForegroundColor Red
        }
        Write-Host ""
    }

    if ($toAdd.Count -gt 0) {
        Write-Host "New files to add: $($toAdd.Count)" -ForegroundColor Cyan
        foreach ($file in $toAdd) {
            Write-Host "  + $($file.path)" -ForegroundColor Cyan
        }
        Write-Host ""
    }

    if ($toRemove.Count -gt 0) {
        Write-Host "Obsolete files to remove: $($toRemove.Count)" -ForegroundColor DarkGray
        foreach ($file in $toRemove) {
            Write-Host "  - $($file.path)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Get confirmation from user
    $modulePath = Join-Path $PSScriptRoot "..\modules\VSCodeIntegration.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        $context = Get-ExecutionContext

        if ($context -eq 'vscode-extension') {
            # Use VSCode Quick Pick
            $totalChanges = $toUpdate.Count + $conflicts.Count + $toAdd.Count + $toRemove.Count
            $prompt = "Update $totalChanges file(s) from $CurrentVersion to $TargetVersion?"
            $choice = Show-QuickPick -Prompt $prompt -Options @("Yes, proceed with update", "No, cancel")

            return ($choice -eq "Yes, proceed with update")
        }
    }

    # Fallback: console prompt
    Write-Host "Proceed with update? (Y/n): " -NoNewline -ForegroundColor Cyan
    $response = Read-Host

    return ($response -ne 'n' -and $response -ne 'N')
}
