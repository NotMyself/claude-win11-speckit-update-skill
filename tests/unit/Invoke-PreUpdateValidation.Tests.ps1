#Requires -Version 7.0

<#
.SYNOPSIS
    Unit tests for Invoke-PreUpdateValidation helper functions.

.DESCRIPTION
    Tests helper functions for SpecKit command detection and error message generation.
    Uses Pester 5.x syntax for test isolation and comprehensive coverage.

.NOTES
    Test Framework: Pester 5.x
    Module Under Test: Invoke-PreUpdateValidation.ps1 (helper script)
#>

BeforeAll {
    # Dot-source the helper script under test
    $helperPath = Join-Path $PSScriptRoot "..\..\scripts\helpers\Invoke-PreUpdateValidation.ps1"
    . $helperPath
}

Describe "Test-SpecKitCommandsAvailable" {
    Context "When .claude/commands directory exists with SpecKit commands" {
        It "Should return true if speckit.constitution.md exists" {
            Mock Test-Path {
                param($Path)
                if ($Path -match "\.claude\\commands$") { return $true }
                if ($Path -match "speckit\.constitution\.md$") { return $true }
                return $false
            }

            $result = Test-SpecKitCommandsAvailable

            $result | Should -Be $true
        }

        It "Should return true if speckit.specify.md exists" {
            Mock Test-Path {
                param($Path)
                if ($Path -match "\.claude\\commands$") { return $true }
                if ($Path -match "speckit\.specify\.md$") { return $true }
                return $false
            }

            $result = Test-SpecKitCommandsAvailable

            $result | Should -Be $true
        }

        It "Should return true if speckit.plan.md exists" {
            Mock Test-Path {
                param($Path)
                if ($Path -match "\.claude\\commands$") { return $true }
                if ($Path -match "speckit\.plan\.md$") { return $true }
                return $false
            }

            $result = Test-SpecKitCommandsAvailable

            $result | Should -Be $true
        }
    }

    Context "When .claude/commands directory does not exist" {
        It "Should return false" {
            Mock Test-Path { return $false }

            $result = Test-SpecKitCommandsAvailable

            $result | Should -Be $false
        }
    }

    Context "When .claude/commands exists but no SpecKit commands found" {
        It "Should return false" {
            Mock Test-Path {
                param($Path)
                if ($Path -match "\.claude\\commands$") { return $true }
                return $false  # No SpecKit command files
            }

            $result = Test-SpecKitCommandsAvailable

            $result | Should -Be $false
        }
    }
}

Describe "Get-HelpfulSpecKitError" {
    Context "When SpecKit commands are available" {
        It "Should suggest running /speckit.constitution" {
            Mock Test-SpecKitCommandsAvailable { return $true }

            $result = Get-HelpfulSpecKitError

            $result | Should -Match "/speckit\.constitution"
            $result | Should -Match "SpecKit is a Claude Code workflow framework"
            $result | Should -Match "To initialize SpecKit in this project"
        }
    }

    Context "When SpecKit commands are not available" {
        It "Should provide documentation link" {
            Mock Test-SpecKitCommandsAvailable { return $false }

            $result = Get-HelpfulSpecKitError

            $result | Should -Match "https://github.com/github/spec-kit"
            $result | Should -Match "SpecKit is a Claude Code workflow framework"
            $result | Should -Match "This updater requires SpecKit to be installed first"
        }
    }

    Context "When detection fails" {
        It "Should return fallback message with both options" {
            Mock Test-SpecKitCommandsAvailable { throw "Simulated error" }

            $result = Get-HelpfulSpecKitError

            $result | Should -Match "/speckit\.constitution"
            $result | Should -Match "https://github.com/github/spec-kit"
            $result | Should -Match "If SpecKit is already installed"
            $result | Should -Match "If SpecKit is not installed"
        }
    }
}
