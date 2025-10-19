#Requires -Version 7.0

<#
.SYNOPSIS
    Runs all Pester tests for SpecKit Safe Update Skill

.DESCRIPTION
    Executes unit and integration tests with code coverage reporting
#>

[CmdletBinding()]
param(
    [switch]$Unit,
    [switch]$Integration,
    [switch]$Coverage
)

# Ensure Pester is available
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "Installing Pester..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}

Import-Module Pester -MinimumVersion 5.0

$config = New-PesterConfiguration

# Set paths
if ($Unit) {
    $config.Run.Path = "$PSScriptRoot/unit"
}
elseif ($Integration) {
    $config.Run.Path = "$PSScriptRoot/integration"
}
else {
    $config.Run.Path = "$PSScriptRoot"
}

# Output configuration
$config.Output.Verbosity = 'Detailed'

# Code coverage
if ($Coverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = "$PSScriptRoot/../scripts/**/*.ps1", "$PSScriptRoot/../scripts/**/*.psm1"
    $config.CodeCoverage.OutputPath = "$PSScriptRoot/coverage/coverage.xml"
}

# Run tests
Write-Host "`n=== Running Tests ===" -ForegroundColor Cyan
$result = Invoke-Pester -Configuration $config

# Exit with appropriate code
if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
