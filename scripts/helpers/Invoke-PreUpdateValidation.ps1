#Requires -Version 7.0

<#
.SYNOPSIS
    Validates prerequisites before running SpecKit update.

.DESCRIPTION
    Performs critical and non-critical checks:
    - Critical: Git installed, .specify/ exists, write permissions, clean Git state
    - Warnings: VSCode installed, internet connectivity, disk space

    Critical checks must pass. Warnings allow user to continue with confirmation.

.PARAMETER ProjectRoot
    Path to the project root directory.

.OUTPUTS
    Throws exception if critical checks fail or user cancels.
    Returns successfully if all checks pass or user confirms to continue despite warnings.
#>

function Invoke-PreUpdateValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ProjectRoot = $PWD
    )

    $errors = @()
    $warnings = @()

    Write-Host "Validating prerequisites..." -ForegroundColor Cyan

    # ========================================
    # CRITICAL CHECKS (must pass)
    # ========================================

    # 1. Check if Git is installed
    $gitInstalled = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitInstalled) {
        $errors += "Git not found in PATH. Install: winget install Git.Git"
    }

    # 2. Check if .specify/ directory exists
    $specifyDir = Join-Path $ProjectRoot ".specify"
    if (-not (Test-Path $specifyDir)) {
        $errors += "Not a SpecKit project (.specify/ directory not found)"
    }

    # 3. Check write permissions
    if (Test-Path $specifyDir -PathType Container) {
        $testFile = Join-Path $specifyDir ".write-test-$(Get-Random)"
        try {
            "test" | Out-File $testFile -ErrorAction Stop
            Remove-Item $testFile -ErrorAction SilentlyContinue
        }
        catch {
            $errors += "No write permission to .specify/ directory: $($_.Exception.Message)"
        }
    }

    # 4. Check Git working directory state (only if Git is installed)
    if ($gitInstalled) {
        try {
            Push-Location $ProjectRoot
            $gitStatus = git status --porcelain 2>&1

            # Check if we're in a Git repository
            if ($LASTEXITCODE -ne 0) {
                $warnings += "Not a Git repository. Changes will not be tracked in version control."
            }
            else {
                # Check for unstaged changes in .specify/ or .claude/ directories
                $relevantChanges = $gitStatus | Where-Object {
                    $_ -match '^\s*[MADRCU\?].*\.(specify|claude)/'
                }

                if ($relevantChanges) {
                    $errors += "Git working directory has unstaged changes in .specify/ or .claude/. Please commit or stash changes first."
                }
            }
        }
        catch {
            $warnings += "Could not check Git status: $($_.Exception.Message)"
        }
        finally {
            Pop-Location
        }
    }

    # ========================================
    # NON-CRITICAL CHECKS (warnings only)
    # ========================================

    # 5. Check if VSCode is installed (for diff/merge)
    $codeInstalled = Get-Command code -ErrorAction SilentlyContinue
    if (-not $codeInstalled) {
        $warnings += "VSCode not found in PATH. Diff and merge views may not work. Install: winget install Microsoft.VisualStudioCode"
    }

    # 6. Check internet connectivity
    try {
        $null = Invoke-RestMethod -Uri "https://api.github.com" -Method Head -TimeoutSec 5 -ErrorAction Stop
    }
    catch {
        $warnings += "Cannot reach GitHub API. Check internet connection. Update will fail without network access."
    }

    # 7. Check disk space
    try {
        $drive = (Get-Item $ProjectRoot).PSDrive
        if ($drive) {
            $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
            if ($freeSpaceGB -lt 1) {
                $warnings += "Low disk space: ${freeSpaceGB}GB free. Backups may fail."
            }
        }
    }
    catch {
        # Silently ignore disk space check failures
    }

    # ========================================
    # DISPLAY RESULTS
    # ========================================

    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Prerequisites not met:" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "  X $error" -ForegroundColor Red
        }
        Write-Host ""
        throw "Prerequisites validation failed. Please fix the issues above and try again."
    }

    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Non-critical issues detected:" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "  ! $warning" -ForegroundColor Yellow
        }
        Write-Host ""

        # Use console prompt for confirmation
        $response = Read-Host "Continue anyway? (Y/n)"
        if ($response -eq 'n' -or $response -eq 'N') {
            throw "Update cancelled by user due to warnings."
        }
    }

    Write-Host "Prerequisites validated successfully" -ForegroundColor Green
    Write-Host ""
}
