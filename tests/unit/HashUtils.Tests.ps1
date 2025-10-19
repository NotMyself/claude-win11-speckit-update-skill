#Requires -Version 7.0

<#
.SYNOPSIS
    Unit tests for HashUtils module.

.DESCRIPTION
    Tests normalized hash computation and comparison functions.
    Uses Pester 5.x syntax for test isolation and comprehensive coverage.

.NOTES
    Test Framework: Pester 5.x
    Module Under Test: HashUtils.psm1
#>

BeforeAll {
    # Import module under test
    $modulePath = Join-Path $PSScriptRoot "..\..\scripts\modules\HashUtils.psm1"
    Import-Module $modulePath -Force

    # Helper function to create temporary test files
    function New-TestFile {
        param(
            [string]$Content,
            [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8,
            [switch]$IncludeBOM
        )

        $tempFile = [System.IO.Path]::GetTempFileName()

        if ($IncludeBOM) {
            # Write with BOM
            $bytes = $Encoding.GetPreamble() + $Encoding.GetBytes($Content)
            [System.IO.File]::WriteAllBytes($tempFile, $bytes)
        }
        else {
            # Write without BOM
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($tempFile, $Content, $utf8NoBom)
        }

        return $tempFile
    }
}

Describe "HashUtils Module" {
    Context "Get-NormalizedHash" {
        Describe "Line Ending Normalization" {
            It "Produces same hash for CRLF and LF line endings" {
                # Arrange
                $contentCRLF = "Line 1`r`nLine 2`r`nLine 3"
                $contentLF = "Line 1`nLine 2`nLine 3"

                $fileCRLF = New-TestFile -Content $contentCRLF
                $fileLF = New-TestFile -Content $contentLF

                try {
                    # Act
                    $hashCRLF = Get-NormalizedHash -FilePath $fileCRLF
                    $hashLF = Get-NormalizedHash -FilePath $fileLF

                    # Assert
                    $hashCRLF | Should -Be $hashLF
                    $hashCRLF | Should -Match '^sha256:[A-F0-9]{64}$'
                }
                finally {
                    Remove-Item $fileCRLF, $fileLF -ErrorAction SilentlyContinue
                }
            }

            It "Handles mixed line endings (CRLF and LF)" {
                # Arrange
                $contentMixed = "Line 1`r`nLine 2`nLine 3`r`nLine 4"
                $contentNormalized = "Line 1`nLine 2`nLine 3`nLine 4"

                $fileMixed = New-TestFile -Content $contentMixed
                $fileNormalized = New-TestFile -Content $contentNormalized

                try {
                    # Act
                    $hashMixed = Get-NormalizedHash -FilePath $fileMixed
                    $hashNormalized = Get-NormalizedHash -FilePath $fileNormalized

                    # Assert
                    $hashMixed | Should -Be $hashNormalized
                }
                finally {
                    Remove-Item $fileMixed, $fileNormalized -ErrorAction SilentlyContinue
                }
            }

            It "Handles CR-only line endings" {
                # Arrange
                $contentCR = "Line 1`rLine 2`rLine 3"
                $contentLF = "Line 1`nLine 2`nLine 3"

                $fileCR = New-TestFile -Content $contentCR
                $fileLF = New-TestFile -Content $contentLF

                try {
                    # Act - CR alone should NOT be normalized (only CRLF → LF)
                    $hashCR = Get-NormalizedHash -FilePath $fileCR
                    $hashLF = Get-NormalizedHash -FilePath $fileLF

                    # Assert - These should be different since CR is not normalized
                    $hashCR | Should -Not -Be $hashLF
                }
                finally {
                    Remove-Item $fileCR, $fileLF -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Trailing Whitespace Normalization" {
            It "Produces same hash with and without trailing whitespace" {
                # Arrange
                $contentWithSpaces = "Line 1   `nLine 2  `nLine 3    "
                $contentWithoutSpaces = "Line 1`nLine 2`nLine 3"

                $fileWith = New-TestFile -Content $contentWithSpaces
                $fileWithout = New-TestFile -Content $contentWithoutSpaces

                try {
                    # Act
                    $hashWith = Get-NormalizedHash -FilePath $fileWith
                    $hashWithout = Get-NormalizedHash -FilePath $fileWithout

                    # Assert
                    $hashWith | Should -Be $hashWithout
                }
                finally {
                    Remove-Item $fileWith, $fileWithout -ErrorAction SilentlyContinue
                }
            }

            It "Handles trailing tabs and mixed whitespace" {
                # Arrange
                $contentWithTabs = "Line 1`t`t`nLine 2 `t `nLine 3"
                $contentClean = "Line 1`nLine 2`nLine 3"

                $fileWithTabs = New-TestFile -Content $contentWithTabs
                $fileClean = New-TestFile -Content $contentClean

                try {
                    # Act
                    $hashWithTabs = Get-NormalizedHash -FilePath $fileWithTabs
                    $hashClean = Get-NormalizedHash -FilePath $fileClean

                    # Assert
                    $hashWithTabs | Should -Be $hashClean
                }
                finally {
                    Remove-Item $fileWithTabs, $fileClean -ErrorAction SilentlyContinue
                }
            }

            It "Preserves leading whitespace" {
                # Arrange
                $contentWithLeading = "  Line 1`n    Line 2`n      Line 3"
                $contentWithoutLeading = "Line 1`nLine 2`nLine 3"

                $fileWith = New-TestFile -Content $contentWithLeading
                $fileWithout = New-TestFile -Content $contentWithoutLeading

                try {
                    # Act
                    $hashWith = Get-NormalizedHash -FilePath $fileWith
                    $hashWithout = Get-NormalizedHash -FilePath $fileWithout

                    # Assert - Leading whitespace is significant
                    $hashWith | Should -Not -Be $hashWithout
                }
                finally {
                    Remove-Item $fileWith, $fileWithout -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "BOM Handling" {
            It "Produces same hash with and without BOM" {
                # Arrange
                $content = "Line 1`nLine 2`nLine 3"

                $fileWithBOM = New-TestFile -Content $content -IncludeBOM
                $fileWithoutBOM = New-TestFile -Content $content

                try {
                    # Act
                    $hashWithBOM = Get-NormalizedHash -FilePath $fileWithBOM
                    $hashWithoutBOM = Get-NormalizedHash -FilePath $fileWithoutBOM

                    # Assert
                    $hashWithBOM | Should -Be $hashWithoutBOM
                }
                finally {
                    Remove-Item $fileWithBOM, $fileWithoutBOM -ErrorAction SilentlyContinue
                }
            }

            It "Handles BOM with CRLF line endings" {
                # Arrange
                $content = "Line 1`r`nLine 2`r`nLine 3"

                $fileWithBOM = New-TestFile -Content $content -IncludeBOM
                $fileWithoutBOM = New-TestFile -Content $content

                try {
                    # Act
                    $hashWithBOM = Get-NormalizedHash -FilePath $fileWithBOM
                    $hashWithoutBOM = Get-NormalizedHash -FilePath $fileWithoutBOM

                    # Assert
                    $hashWithBOM | Should -Be $hashWithoutBOM
                }
                finally {
                    Remove-Item $fileWithBOM, $fileWithoutBOM -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Content Change Detection" {
            It "Produces different hashes for different content" {
                # Arrange
                $content1 = "Line 1`nLine 2`nLine 3"
                $content2 = "Line 1`nLine 2 modified`nLine 3"

                $file1 = New-TestFile -Content $content1
                $file2 = New-TestFile -Content $content2

                try {
                    # Act
                    $hash1 = Get-NormalizedHash -FilePath $file1
                    $hash2 = Get-NormalizedHash -FilePath $file2

                    # Assert
                    $hash1 | Should -Not -Be $hash2
                }
                finally {
                    Remove-Item $file1, $file2 -ErrorAction SilentlyContinue
                }
            }

            It "Detects added lines" {
                # Arrange
                $content1 = "Line 1`nLine 2"
                $content2 = "Line 1`nLine 2`nLine 3"

                $file1 = New-TestFile -Content $content1
                $file2 = New-TestFile -Content $content2

                try {
                    # Act
                    $hash1 = Get-NormalizedHash -FilePath $file1
                    $hash2 = Get-NormalizedHash -FilePath $file2

                    # Assert
                    $hash1 | Should -Not -Be $hash2
                }
                finally {
                    Remove-Item $file1, $file2 -ErrorAction SilentlyContinue
                }
            }

            It "Detects removed lines" {
                # Arrange
                $content1 = "Line 1`nLine 2`nLine 3"
                $content2 = "Line 1`nLine 2"

                $file1 = New-TestFile -Content $content1
                $file2 = New-TestFile -Content $content2

                try {
                    # Act
                    $hash1 = Get-NormalizedHash -FilePath $file1
                    $hash2 = Get-NormalizedHash -FilePath $file2

                    # Assert
                    $hash1 | Should -Not -Be $hash2
                }
                finally {
                    Remove-Item $file1, $file2 -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Empty File Handling" {
            It "Produces consistent hash for empty files" {
                # Arrange
                $file1 = New-TestFile -Content ""
                $file2 = New-TestFile -Content ""

                try {
                    # Act
                    $hash1 = Get-NormalizedHash -FilePath $file1
                    $hash2 = Get-NormalizedHash -FilePath $file2

                    # Assert
                    $hash1 | Should -Be $hash2
                    $hash1 | Should -Match '^sha256:[A-F0-9]{64}$'
                }
                finally {
                    Remove-Item $file1, $file2 -ErrorAction SilentlyContinue
                }
            }

            It "Handles file with only whitespace" {
                # Arrange
                $contentWhitespace = "   `n  `n   "
                $contentEmpty = "`n`n"  # After trimming, we get empty lines (newlines remain)

                $fileWhitespace = New-TestFile -Content $contentWhitespace
                $fileEmpty = New-TestFile -Content $contentEmpty

                try {
                    # Act
                    $hashWhitespace = Get-NormalizedHash -FilePath $fileWhitespace
                    $hashEmpty = Get-NormalizedHash -FilePath $fileEmpty

                    # Assert - Trailing whitespace trimmed but newlines preserved
                    $hashWhitespace | Should -Be $hashEmpty
                }
                finally {
                    Remove-Item $fileWhitespace, $fileEmpty -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Error Handling" {
            It "Throws when file does not exist" {
                # Arrange
                $nonExistentFile = "C:\nonexistent\path\file.txt"

                # Act & Assert
                { Get-NormalizedHash -FilePath $nonExistentFile } | Should -Throw "*File not found*"
            }

            It "Throws when file path is empty" {
                # Act & Assert
                { Get-NormalizedHash -FilePath "" } | Should -Throw
            }

            It "Throws when file path is null" {
                # Act & Assert
                { Get-NormalizedHash -FilePath $null } | Should -Throw
            }

            It "Handles locked files gracefully" {
                # Arrange
                $file = New-TestFile -Content "Test content"

                try {
                    # Lock the file
                    $stream = [System.IO.File]::Open($file, 'Open', 'Read', 'None')

                    try {
                        # Act & Assert
                        { Get-NormalizedHash -FilePath $file } | Should -Throw "*locked*"
                    }
                    finally {
                        $stream.Close()
                    }
                }
                finally {
                    Remove-Item $file -ErrorAction SilentlyContinue
                }
            }

            It "Handles permission denied gracefully" -Skip:($env:USERNAME -eq 'SYSTEM') {
                # This test is platform-specific and may not work in all environments
                # Skip if running as SYSTEM (CI/CD environments)

                # Arrange
                $file = New-TestFile -Content "Test content"

                try {
                    # Remove read permissions (Windows)
                    if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                        $acl = Get-Acl $file
                        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                            $currentUser,
                            "Read",
                            "Deny"
                        )
                        $acl.SetAccessRule($rule)
                        Set-Acl $file $acl

                        # Act & Assert
                        { Get-NormalizedHash -FilePath $file } | Should -Throw "*Permission denied*"
                    }
                }
                finally {
                    # Restore permissions and cleanup
                    if (Test-Path $file) {
                        $acl = Get-Acl $file
                        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                            $currentUser,
                            "Read",
                            "Allow"
                        )
                        $acl.SetAccessRule($rule)
                        Set-Acl $file $acl
                        Remove-Item $file -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        Describe "Hash Format" {
            It "Returns hash in sha256:HEXSTRING format" {
                # Arrange
                $file = New-TestFile -Content "Test content"

                try {
                    # Act
                    $hash = Get-NormalizedHash -FilePath $file

                    # Assert
                    $hash | Should -Match '^sha256:[A-F0-9]{64}$'
                    $hash | Should -BeLike "sha256:*"
                }
                finally {
                    Remove-Item $file -ErrorAction SilentlyContinue
                }
            }

            It "Produces uppercase hex string" {
                # Arrange
                $file = New-TestFile -Content "Test content"

                try {
                    # Act
                    $hash = Get-NormalizedHash -FilePath $file

                    # Assert
                    $hexPart = $hash.Substring(7) # Remove "sha256:" prefix
                    $hexPart | Should -Match '^[A-F0-9]+$'
                    $hexPart | Should -Not -CMatch '[a-z]'  # Case-sensitive match for lowercase
                }
                finally {
                    Remove-Item $file -ErrorAction SilentlyContinue
                }
            }
        }

        Describe "Real-world Scenarios" {
            It "Handles typical markdown file with CRLF (Windows)" {
                # Arrange
                $markdown = "# Title`r`n`r`n## Section 1`r`n`r`nContent here.`r`n"
                $file = New-TestFile -Content $markdown

                try {
                    # Act
                    $hash = Get-NormalizedHash -FilePath $file

                    # Assert
                    $hash | Should -Match '^sha256:[A-F0-9]{64}$'
                }
                finally {
                    Remove-Item $file -ErrorAction SilentlyContinue
                }
            }

            It "Handles PowerShell script with mixed whitespace" {
                # Arrange
                $script = "function Test-Func {  `r`n    param([string]`$Name)  `r`n    Write-Host `$Name`r`n}  "
                $file = New-TestFile -Content $script

                try {
                    # Act
                    $hash = Get-NormalizedHash -FilePath $file

                    # Assert
                    $hash | Should -Match '^sha256:[A-F0-9]{64}$'
                }
                finally {
                    Remove-Item $file -ErrorAction SilentlyContinue
                }
            }

            It "Handles JSON file with BOM (VSCode default)" {
                # Arrange
                $json = "{`r`n  `"version`": `"1.0`",`r`n  `"name`": `"test`"`r`n}"
                $file = New-TestFile -Content $json -IncludeBOM

                try {
                    # Act
                    $hash = Get-NormalizedHash -FilePath $file

                    # Assert
                    $hash | Should -Match '^sha256:[A-F0-9]{64}$'
                }
                finally {
                    Remove-Item $file -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "Compare-FileHashes" {
        Describe "Basic Comparison" {
            It "Returns true for identical hashes" {
                # Arrange
                $hash1 = "sha256:ABC123DEF456"
                $hash2 = "sha256:ABC123DEF456"

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeTrue
            }

            It "Returns false for different hashes" {
                # Arrange
                $hash1 = "sha256:ABC123DEF456"
                $hash2 = "sha256:XYZ789UVW012"

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeFalse
            }

            It "Returns false for hashes with different hex values" {
                # Arrange
                $hash1 = "sha256:ABC123DEF456"
                $hash2 = "sha256:ABC123DEF457"  # Last digit different

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeFalse
            }
        }

        Describe "Case Sensitivity" {
            It "Returns true for hashes with different case" {
                # Arrange
                $hash1 = "sha256:ABC123DEF456"
                $hash2 = "sha256:abc123def456"

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeTrue
            }

            It "Returns true for mixed case hashes" {
                # Arrange
                $hash1 = "SHA256:ABC123def456"
                $hash2 = "sha256:abc123DEF456"

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeTrue
            }
        }

        Describe "Edge Cases" {
            It "Handles full-length SHA-256 hashes (64 hex chars)" {
                # Arrange
                $hash1 = "sha256:" + ("A" * 64)
                $hash2 = "sha256:" + ("a" * 64)

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeTrue
            }

            It "Returns false for empty hash vs non-empty hash" {
                # Arrange
                $hash1 = "sha256:"
                $hash2 = "sha256:ABC123"

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeFalse
            }

            It "Returns true for two empty hashes" {
                # Arrange
                $hash1 = "sha256:"
                $hash2 = "sha256:"

                # Act
                $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                # Assert
                $result | Should -BeTrue
            }
        }

        Describe "Error Handling" {
            It "Throws when Hash1 is null" {
                # Act & Assert
                { Compare-FileHashes -Hash1 $null -Hash2 "sha256:ABC123" } | Should -Throw
            }

            It "Throws when Hash2 is null" {
                # Act & Assert
                { Compare-FileHashes -Hash1 "sha256:ABC123" -Hash2 $null } | Should -Throw
            }

            It "Throws when Hash1 is empty string" {
                # Act & Assert
                { Compare-FileHashes -Hash1 "" -Hash2 "sha256:ABC123" } | Should -Throw
            }

            It "Throws when Hash2 is empty string" {
                # Act & Assert
                { Compare-FileHashes -Hash1 "sha256:ABC123" -Hash2 "" } | Should -Throw
            }
        }

        Describe "Integration with Get-NormalizedHash" {
            It "Correctly compares hashes from identical files" {
                # Arrange
                $content = "Line 1`nLine 2`nLine 3"
                $file1 = New-TestFile -Content $content
                $file2 = New-TestFile -Content $content

                try {
                    # Act
                    $hash1 = Get-NormalizedHash -FilePath $file1
                    $hash2 = Get-NormalizedHash -FilePath $file2
                    $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                    # Assert
                    $result | Should -BeTrue
                }
                finally {
                    Remove-Item $file1, $file2 -ErrorAction SilentlyContinue
                }
            }

            It "Correctly compares hashes from different files" {
                # Arrange
                $content1 = "Line 1`nLine 2`nLine 3"
                $content2 = "Line 1`nLine 2 modified`nLine 3"
                $file1 = New-TestFile -Content $content1
                $file2 = New-TestFile -Content $content2

                try {
                    # Act
                    $hash1 = Get-NormalizedHash -FilePath $file1
                    $hash2 = Get-NormalizedHash -FilePath $file2
                    $result = Compare-FileHashes -Hash1 $hash1 -Hash2 $hash2

                    # Assert
                    $result | Should -BeFalse
                }
                finally {
                    Remove-Item $file1, $file2 -ErrorAction SilentlyContinue
                }
            }

            It "Compares files with CRLF vs LF as identical" {
                # Arrange
                $contentCRLF = "Line 1`r`nLine 2`r`nLine 3"
                $contentLF = "Line 1`nLine 2`nLine 3"
                $fileCRLF = New-TestFile -Content $contentCRLF
                $fileLF = New-TestFile -Content $contentLF

                try {
                    # Act
                    $hashCRLF = Get-NormalizedHash -FilePath $fileCRLF
                    $hashLF = Get-NormalizedHash -FilePath $fileLF
                    $result = Compare-FileHashes -Hash1 $hashCRLF -Hash2 $hashLF

                    # Assert
                    $result | Should -BeTrue
                }
                finally {
                    Remove-Item $fileCRLF, $fileLF -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
