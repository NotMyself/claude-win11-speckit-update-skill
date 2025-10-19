#Requires -Version 7.0

<#
.SYNOPSIS
    Performs 3-way merge using VSCode merge editor.

.DESCRIPTION
    Creates temporary merge files in .specify/.tmp-merge/:
    - base: Original version from manifest
    - current: User's current version
    - incoming: New upstream version
    - result: Merge result (starts as copy of current)

    Opens VSCode merge editor, waits for user to complete merge,
    then copies result back to original location and cleans up temp files.

.PARAMETER Conflict
    Conflict object with properties:
    - path: Relative file path
    - currentHash: Current file hash
    - upstreamHash: Upstream file hash
    - originalHash: Original file hash from manifest

.PARAMETER Templates
    Hashtable of template content (path -> content)

.PARAMETER ProjectRoot
    Path to project root directory

.OUTPUTS
    Boolean: $true if merge completed successfully, $false otherwise
#>

function Invoke-ThreeWayMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Conflict,

        [Parameter(Mandatory=$true)]
        [hashtable]$Templates,

        [Parameter(Mandatory=$false)]
        [string]$ProjectRoot = $PWD
    )

    # Create temporary merge directory
    $tmpDir = Join-Path $ProjectRoot ".specify\.tmp-merge"
    if (-not (Test-Path $tmpDir)) {
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    }

    try {
        # Get file name for temp files
        $fileName = [System.IO.Path]::GetFileName($Conflict.path)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)

        # Create merge file paths
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $baseFile = Join-Path $tmpDir "${baseName}-base-${timestamp}${extension}"
        $currentFile = Join-Path $tmpDir "${baseName}-current-${timestamp}${extension}"
        $incomingFile = Join-Path $tmpDir "${baseName}-incoming-${timestamp}${extension}"
        $resultFile = Join-Path $tmpDir "${baseName}-result-${timestamp}${extension}"

        Write-Host "  Creating merge files..." -ForegroundColor DarkGray

        # Get original content (base)
        # For now, we'll use the current file as base if we don't have original stored
        # In a full implementation, we'd retrieve the original from manifest history
        $originalPath = Join-Path $ProjectRoot $Conflict.path
        $currentContent = Get-Content $originalPath -Raw

        # Get upstream content (incoming)
        if (-not $Templates.ContainsKey($Conflict.path)) {
            Write-Error "Template not found for $($Conflict.path)"
            return $false
        }
        $incomingContent = $Templates[$Conflict.path]

        # For base, we'll try to get from Git history if available
        try {
            Push-Location $ProjectRoot
            $gitBaseContent = git show "HEAD:$($Conflict.path)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $gitBaseContent) {
                $baseContent = $gitBaseContent -join "`n"
            }
            else {
                # Fallback: use current content as base
                $baseContent = $currentContent
            }
        }
        catch {
            $baseContent = $currentContent
        }
        finally {
            Pop-Location
        }

        # Write merge files
        $baseContent | Out-File -FilePath $baseFile -Encoding utf8 -NoNewline
        $currentContent | Out-File -FilePath $currentFile -Encoding utf8 -NoNewline
        $incomingContent | Out-File -FilePath $incomingFile -Encoding utf8 -NoNewline
        Copy-Item $currentFile $resultFile  # Start with current version

        Write-Host "  Files created:" -ForegroundColor DarkGray
        Write-Host "    Base:     $baseFile" -ForegroundColor DarkGray
        Write-Host "    Current:  $currentFile" -ForegroundColor DarkGray
        Write-Host "    Incoming: $incomingFile" -ForegroundColor DarkGray
        Write-Host "    Result:   $resultFile" -ForegroundColor DarkGray
        Write-Host ""

        # Import VSCode integration
        $vscodeModulePath = Join-Path $PSScriptRoot "..\modules\VSCodeIntegration.psm1"
        if (Test-Path $vscodeModulePath) {
            Import-Module $vscodeModulePath -Force
        }

        # Open VSCode merge editor
        Write-Host "  Opening VSCode merge editor..." -ForegroundColor Cyan
        Write-Host "  Please resolve conflicts and save the result file." -ForegroundColor Cyan
        Write-Host ""

        if (Get-Command Open-MergeEditor -ErrorAction SilentlyContinue) {
            $mergeSuccess = Open-MergeEditor -BasePath $baseFile -CurrentPath $currentFile -IncomingPath $incomingFile -ResultPath $resultFile
        }
        else {
            # Fallback: use code CLI directly
            $codeInstalled = Get-Command code -ErrorAction SilentlyContinue
            if ($codeInstalled) {
                # VSCode merge editor syntax: code --merge <base> <current> <incoming> <result>
                & code --merge $baseFile $currentFile $incomingFile $resultFile --wait

                # Check if result file was modified
                $resultModified = (Get-Item $resultFile).LastWriteTime -gt (Get-Item $currentFile).LastWriteTime
                $mergeSuccess = $resultModified
            }
            else {
                Write-Error "VSCode not found. Cannot open merge editor."
                return $false
            }
        }

        if ($mergeSuccess) {
            # Copy result back to original location
            Write-Host "  Applying merge result..." -ForegroundColor Green

            Copy-Item $resultFile $originalPath -Force

            Write-Host "  Merge completed successfully for $($Conflict.path)" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "  Merge was not completed" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Error "Merge failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        # Cleanup temp files
        Write-Host "  Cleaning up temporary files..." -ForegroundColor DarkGray

        if (Test-Path $baseFile) { Remove-Item $baseFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $currentFile) { Remove-Item $currentFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $incomingFile) { Remove-Item $incomingFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $resultFile) { Remove-Item $resultFile -Force -ErrorAction SilentlyContinue }

        # Remove tmp directory if empty
        if (Test-Path $tmpDir) {
            $remainingFiles = Get-ChildItem $tmpDir -Recurse
            if ($remainingFiles.Count -eq 0) {
                Remove-Item $tmpDir -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
}

# Export function
Export-ModuleMember -Function Invoke-ThreeWayMerge
