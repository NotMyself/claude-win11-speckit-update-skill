# PSScriptAnalyzer Settings for SpecKit Safe Update Skill
#
# This configuration defines the linting rules for PowerShell code quality.
# Uses default PSScriptAnalyzer rules with specific exclusions.
#
# See: https://github.com/PowerShell/PSScriptAnalyzer

@{
    # Severity levels to include (Error, Warning)
    # Only errors will block CI, warnings are informational
    Severity = @(
        'Error',
        'Warning'
    )

    # Use all default PSScriptAnalyzer rules except those explicitly excluded
    IncludeDefaultRules = $true

    # Rules to exclude (disabled)
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',  # We use Write-Host intentionally for colored user-facing output
        'PSUseBOMForUnicodeEncodedFile',  # We explicitly avoid BOM in HashUtils for cross-platform compatibility
        'PSUseCompatibleCmdlets',  # Requires complex profile configuration
        'PSUseCompatibleSyntax',  # Requires complex profile configuration
        'PSUseCompatibleTypes'  # Requires complex profile configuration
    )

    # Rules configuration (custom settings for specific rules)
    Rules = @{
        # Whitespace consistency
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator = $true
            CheckParameter = $false  # Allow flexibility in parameter spacing
        }

        # Indentation consistency
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4       # 4 spaces per indent level
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'            # Use spaces, not tabs
        }

        # Alignment
        PSAlignAssignmentStatement = @{
            Enable = $true
            CheckHashtable = $true
        }

        # Comment help requirements
        PSProvideCommentHelp = @{
            Enable = $true
            ExportedOnly = $true      # Only exported functions require comment help
            BlockComment = $true      # Use block comments (<# #>), not line comments
            VSCodeSnippetCorrection = $true
            Placement = 'before'      # Comment help should be before function definition
        }

        # Compatibility targets (commented out - requires complex profile configuration)
        # PSUseCompatibleCmdlets = @{
        #     Compatibility = @('core-7.0.0-windows', 'core-7.0.0-linux')
        # }
        #
        # PSUseCompatibleSyntax = @{
        #     Enable = $true
        #     TargetVersions = @('7.0')
        # }
        #
        # PSUseCompatibleTypes = @{
        #     Enable = $true
        #     TargetVersions = @('7.0')
        # }
    }
}
