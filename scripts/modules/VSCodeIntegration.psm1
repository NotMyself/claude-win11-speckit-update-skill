#Requires -Version 7.0

<#
.SYNOPSIS
    VSCode integration module for SpecKit Safe Update Skill.

.DESCRIPTION
    Provides functions to detect execution context (VSCode vs terminal) and
    integrate with VSCode tools (diff viewer, merge editor, Quick Pick).

.NOTES
    Module: VSCodeIntegration.psm1
    Author: SpecKit Safe Update Skill
    Version: 1.0
#>

function Get-ExecutionContext {
    <#
    .SYNOPSIS
        Detects the current execution context.

    .DESCRIPTION
        Determines whether the script is running in:
        - 'vscode-extension': VSCode extension context
        - 'vscode-terminal': VSCode integrated terminal
        - 'standalone-terminal': Standalone PowerShell terminal

    .OUTPUTS
        String. Returns 'vscode-extension', 'vscode-terminal', or 'standalone-terminal'

    .EXAMPLE
        $context = Get-ExecutionContext
        if ($context -eq 'vscode-extension') {
            # Use VSCode-specific features
        }
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:VSCODE_PID) {
        # Running inside VSCode
        if ($env:TERM_PROGRAM -eq 'vscode') {
            return 'vscode-terminal'
        }
        else {
            return 'vscode-extension'
        }
    }
    else {
        return 'standalone-terminal'
    }
}

function Show-Notification {
    <#
    .SYNOPSIS
        Shows a notification message.

    .DESCRIPTION
        Displays a message with appropriate color coding based on level.
        In VSCode context, could potentially integrate with extension notifications.
        In terminal, uses Write-Host with color coding.

    .PARAMETER Message
        The message to display.

    .PARAMETER Level
        The severity level: 'info', 'warning', or 'error'.

    .EXAMPLE
        Show-Notification -Message "Update completed successfully" -Level info

    .EXAMPLE
        Show-Notification -Message "Conflict detected" -Level warning

    .EXAMPLE
        Show-Notification -Message "Update failed" -Level error
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('info', 'warning', 'error')]
        [string]$Level = 'info'
    )

    switch ($Level) {
        'info' {
            Write-Host $Message -ForegroundColor Cyan
        }
        'warning' {
            Write-Host $Message -ForegroundColor Yellow
        }
        'error' {
            Write-Host $Message -ForegroundColor Red
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Get-ExecutionContext',
    'Show-Notification'
)
