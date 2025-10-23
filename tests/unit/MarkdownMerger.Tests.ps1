BeforeAll {
    # Import module
    $modulePath = Join-Path $PSScriptRoot "..\..\scripts\modules\MarkdownMerger.psm1"
    Import-Module $modulePath -Force
}

Describe "MarkdownMerger Module" {
    Context "Get-LevenshteinDistance" {
        It "Should return 0 for identical strings" {
            $result = Get-LevenshteinDistance -Source "hello" -Target "hello"
            $result | Should -Be 0
        }

        It "Should return length for empty source" {
            $result = Get-LevenshteinDistance -Source "" -Target "hello"
            $result | Should -Be 5
        }

        It "Should return length for empty target" {
            $result = Get-LevenshteinDistance -Source "hello" -Target ""
            $result | Should -Be 5
        }

        It "Should calculate correct distance for kitten->sitting" {
            $result = Get-LevenshteinDistance -Source "kitten" -Target "sitting"
            $result | Should -Be 3
        }

        It "Should calculate correct distance for Saturday->Sunday" {
            $result = Get-LevenshteinDistance -Source "Saturday" -Target "Sunday"
            $result | Should -Be 3
        }

        It "Should be case-sensitive" {
            $result = Get-LevenshteinDistance -Source "Hello" -Target "hello"
            $result | Should -Be 1
        }
    }

    Context "Get-StringSimilarity" {
        It "Should return 100% for identical strings" {
            $result = Get-StringSimilarity -Source "hello" -Target "hello"
            $result | Should -Be 100.0
        }

        It "Should return 0% for completely different strings of same length" {
            $result = Get-StringSimilarity -Source "abc" -Target "xyz"
            $result | Should -Be 0.0
        }

        It "Should return high similarity for similar strings" {
            $result = Get-StringSimilarity -Source "Hello World" -Target "Hello World!"
            $result | Should -BeGreaterThan 90.0
        }

        It "Should handle empty strings" {
            $result = Get-StringSimilarity -Source "" -Target ""
            $result | Should -Be 100.0
        }

        It "Should return percentage between 0 and 100" {
            $result = Get-StringSimilarity -Source "test" -Target "taste"
            $result | Should -BeGreaterThan 0
            $result | Should -BeLessThan 100
        }
    }

    Context "Get-MarkdownSections" {
        It "Should parse simple markdown with headers" {
            $markdown = @"
# Header 1
Content 1

## Header 2
Content 2
"@
            $sections = Get-MarkdownSections -Content $markdown
            $sections.Count | Should -Be 2
            $sections[0].Header | Should -Be "Header 1"
            $sections[0].Level | Should -Be 1
            $sections[1].Header | Should -Be "Header 2"
            $sections[1].Level | Should -Be 2
        }

        It "Should handle content before first header" {
            $markdown = @"
Frontmatter content

# First Header
Content
"@
            $sections = Get-MarkdownSections -Content $markdown
            $sections.Count | Should -Be 2
            $sections[0].Header | Should -Be "[Document Start]"
            $sections[0].Level | Should -Be 0
        }

        It "Should capture multi-line content" {
            $markdown = @"
# Header
Line 1
Line 2
Line 3
"@
            $sections = Get-MarkdownSections -Content $markdown
            $sections[0].Content | Should -Match "Line 1"
            $sections[0].Content | Should -Match "Line 2"
            $sections[0].Content | Should -Match "Line 3"
        }

        It "Should handle nested headers" {
            $markdown = @"
# H1
## H2
### H3
Content
"@
            $sections = Get-MarkdownSections -Content $markdown
            $sections.Count | Should -Be 3
            $sections[0].Level | Should -Be 1
            $sections[1].Level | Should -Be 2
            $sections[2].Level | Should -Be 3
        }

        It "Should handle empty sections" {
            $markdown = @"
# Header 1

# Header 2
Content
"@
            $sections = Get-MarkdownSections -Content $markdown
            $sections.Count | Should -Be 2
            $sections[0].Content.Trim() | Should -Be ""
        }

        It "Should track line numbers" {
            $markdown = @"
# Header 1
Content

# Header 2
More content
"@
            $sections = Get-MarkdownSections -Content $markdown
            $sections[0].LineStart | Should -Be 1
            $sections[1].LineStart | Should -Be 4
        }
    }

    Context "Find-MatchingSection" {
        BeforeEach {
            $script:TestSections = @(
                [PSCustomObject]@{ Header = "Introduction"; Content = "This is the intro"; Level = 1 }
                [PSCustomObject]@{ Header = "Installation"; Content = "Install steps here"; Level = 1 }
                [PSCustomObject]@{ Header = "Usage"; Content = "How to use"; Level = 1 }
            )
        }

        It "Should find exact match" {
            $target = [PSCustomObject]@{ Header = "Installation"; Content = "Install steps here"; Level = 1 }
            $match = Find-MatchingSection -TargetSection $target -SectionList $script:TestSections
            $match | Should -Not -BeNullOrEmpty
            $match.Header | Should -Be "Installation"
        }

        It "Should find fuzzy match for similar header" {
            $target = [PSCustomObject]@{ Header = "Install"; Content = "Install steps here"; Level = 1 }
            $match = Find-MatchingSection -TargetSection $target -SectionList $script:TestSections -Threshold 70.0
            $match | Should -Not -BeNullOrEmpty
            $match.Header | Should -Be "Installation"
        }

        It "Should return null when no match exceeds threshold" {
            $target = [PSCustomObject]@{ Header = "Completely Different"; Content = "No match"; Level = 1 }
            $match = Find-MatchingSection -TargetSection $target -SectionList $script:TestSections
            $match | Should -BeNullOrEmpty
        }

        It "Should mark matched section" {
            $target = [PSCustomObject]@{ Header = "Installation"; Content = "Install steps here"; Level = 1 }
            $match = Find-MatchingSection -TargetSection $target -SectionList $script:TestSections
            $match.Matched | Should -Be $true
        }

        It "Should skip already matched sections" {
            $target1 = [PSCustomObject]@{ Header = "Installation"; Content = "Install steps here"; Level = 1 }
            $target2 = [PSCustomObject]@{ Header = "Installation Guide"; Content = "Different content"; Level = 1 }

            $match1 = Find-MatchingSection -TargetSection $target1 -SectionList $script:TestSections
            $match2 = Find-MatchingSection -TargetSection $target2 -SectionList $script:TestSections

            $match1 | Should -Not -BeNullOrEmpty
            $match2 | Should -BeNullOrEmpty  # Should not match already-matched section
        }

        It "Should weight header similarity higher than content" {
            $sections = @(
                [PSCustomObject]@{ Header = "Setup"; Content = "Short content"; Level = 1 }
                [PSCustomObject]@{ Header = "Installation"; Content = "Install steps with lots of detailed content here"; Level = 1 }
            )

            $target = [PSCustomObject]@{ Header = "Install"; Content = "Install steps with lots of detailed content here"; Level = 1 }
            $match = Find-MatchingSection -TargetSection $target -SectionList $sections -Threshold 60.0

            # Should match "Installation" due to header similarity, even though both have same content
            $match.Header | Should -Be "Installation"
        }
    }

    Context "New-ConflictMarker" {
        It "Should generate git conflict marker with all sections" {
            $result = New-ConflictMarker -Header "## Test" `
                                          -CurrentContent "Current content" `
                                          -BaseContent "Base content" `
                                          -IncomingContent "Incoming content" `
                                          -CurrentVersion "v1" `
                                          -IncomingVersion "v2"

            $result | Should -Match "<<<<<<< v1"
            $result | Should -Match "\|\|\|\|\|\|\| Base"
            $result | Should -Match "======="
            $result | Should -Match ">>>>>>> v2"
            $result | Should -Match "Current content"
            $result | Should -Match "Base content"
            $result | Should -Match "Incoming content"
        }

        It "Should include header in output" {
            $result = New-ConflictMarker -Header "## Installation" `
                                          -CurrentContent "A" `
                                          -IncomingContent "B"

            $result | Should -Match "## Installation"
        }

        It "Should handle empty base content" {
            $result = New-ConflictMarker -Header "## Test" `
                                          -CurrentContent "Current" `
                                          -IncomingContent "Incoming"

            $result | Should -Match "\|\|\|\|\|\|\| Base"
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Merge-MarkdownFiles" {
        BeforeEach {
            # Create temp directory for test files
            $script:TestDir = Join-Path $TestDrive "merge-tests"
            New-Item -Path $script:TestDir -ItemType Directory -Force | Out-Null
        }

        It "Should perform clean merge when current unchanged" {
            # Base version
            $base = @"
# Introduction
This is the intro.

# Installation
Install it.
"@
            # Current (unchanged)
            $current = $base

            # Incoming (updated)
            $incoming = @"
# Introduction
This is the updated intro.

# Installation
Install it with new steps.
"@

            $basePath = Join-Path $script:TestDir "base.md"
            $currentPath = Join-Path $script:TestDir "current.md"
            $incomingPath = Join-Path $script:TestDir "incoming.md"
            $outputPath = Join-Path $script:TestDir "output.md"

            Set-Content -Path $basePath -Value $base
            Set-Content -Path $currentPath -Value $current
            Set-Content -Path $incomingPath -Value $incoming

            $result = Merge-MarkdownFiles -BasePath $basePath `
                                           -CurrentPath $currentPath `
                                           -IncomingPath $incomingPath `
                                           -OutputPath $outputPath `
                                           -BaseVersion "v1" `
                                           -IncomingVersion "v2"

            $result.Success | Should -Be $true
            $result.ConflictCount | Should -Be 0
            $output = Get-Content -Path $outputPath -Raw
            $output | Should -Match "updated intro"
        }

        It "Should preserve current changes when incoming unchanged" {
            # Base version
            $base = @"
# Installation
Install it.
"@
            # Current (customized)
            $current = @"
# Installation
Install it with custom steps.
"@
            # Incoming (unchanged from base)
            $incoming = $base

            $basePath = Join-Path $script:TestDir "base.md"
            $currentPath = Join-Path $script:TestDir "current.md"
            $incomingPath = Join-Path $script:TestDir "incoming.md"
            $outputPath = Join-Path $script:TestDir "output.md"

            Set-Content -Path $basePath -Value $base
            Set-Content -Path $currentPath -Value $current
            Set-Content -Path $incomingPath -Value $incoming

            $result = Merge-MarkdownFiles -BasePath $basePath `
                                           -CurrentPath $currentPath `
                                           -IncomingPath $incomingPath `
                                           -OutputPath $outputPath

            $result.Success | Should -Be $true
            $result.ConflictCount | Should -Be 0
            $output = Get-Content -Path $outputPath -Raw
            $output | Should -Match "custom steps"
        }

        It "Should detect conflict when both current and incoming changed" {
            # Base version
            $base = @"
# Installation
Install it.
"@
            # Current (changed)
            $current = @"
# Installation
Install with current changes.
"@
            # Incoming (also changed)
            $incoming = @"
# Installation
Install with incoming changes.
"@

            $basePath = Join-Path $script:TestDir "base.md"
            $currentPath = Join-Path $script:TestDir "current.md"
            $incomingPath = Join-Path $script:TestDir "incoming.md"
            $outputPath = Join-Path $script:TestDir "output.md"

            Set-Content -Path $basePath -Value $base
            Set-Content -Path $currentPath -Value $current
            Set-Content -Path $incomingPath -Value $incoming

            $result = Merge-MarkdownFiles -BasePath $basePath `
                                           -CurrentPath $currentPath `
                                           -IncomingPath $incomingPath `
                                           -OutputPath $outputPath `
                                           -BaseVersion "v1" `
                                           -IncomingVersion "v2"

            $result.Success | Should -Be $true
            $result.ConflictCount | Should -Be 1
            $output = Get-Content -Path $outputPath -Raw
            $output | Should -Match "<<<<<<<"
            $output | Should -Match ">>>>>>>"
        }

        It "Should add new sections from incoming" {
            # Base version
            $base = @"
# Introduction
Intro content.
"@
            # Current (unchanged)
            $current = $base

            # Incoming (with new section)
            $incoming = @"
# Introduction
Intro content.

# New Section
New content here.
"@

            $basePath = Join-Path $script:TestDir "base.md"
            $currentPath = Join-Path $script:TestDir "current.md"
            $incomingPath = Join-Path $script:TestDir "incoming.md"
            $outputPath = Join-Path $script:TestDir "output.md"

            Set-Content -Path $basePath -Value $base
            Set-Content -Path $currentPath -Value $current
            Set-Content -Path $incomingPath -Value $incoming

            $result = Merge-MarkdownFiles -BasePath $basePath `
                                           -CurrentPath $currentPath `
                                           -IncomingPath $incomingPath `
                                           -OutputPath $outputPath

            $result.Success | Should -Be $true
            $result.NewSections | Should -Be 1
            $output = Get-Content -Path $outputPath -Raw
            $output | Should -Match "New Section"
        }

        It "Should preserve custom sections from current" {
            # Base version
            $base = @"
# Introduction
Intro content.
"@
            # Current (with custom section)
            $current = @"
# Introduction
Intro content.

# My Custom Section
Custom content.
"@
            # Incoming
            $incoming = @"
# Introduction
Updated intro.
"@

            $basePath = Join-Path $script:TestDir "base.md"
            $currentPath = Join-Path $script:TestDir "current.md"
            $incomingPath = Join-Path $script:TestDir "incoming.md"
            $outputPath = Join-Path $script:TestDir "output.md"

            Set-Content -Path $basePath -Value $base
            Set-Content -Path $currentPath -Value $current
            Set-Content -Path $incomingPath -Value $incoming

            $result = Merge-MarkdownFiles -BasePath $basePath `
                                           -CurrentPath $currentPath `
                                           -IncomingPath $incomingPath `
                                           -OutputPath $outputPath

            $result.Success | Should -Be $true
            $output = Get-Content -Path $outputPath -Raw
            $output | Should -Match "My Custom Section"
            $output | Should -Match "Custom content"
        }

        It "Should use incoming structure as canonical" {
            # Base version
            $base = @"
# Section A
# Section B
# Section C
"@
            # Current (same structure)
            $current = $base

            # Incoming (reordered)
            $incoming = @"
# Section C
# Section A
# Section B
"@

            $basePath = Join-Path $script:TestDir "base.md"
            $currentPath = Join-Path $script:TestDir "current.md"
            $incomingPath = Join-Path $script:TestDir "incoming.md"
            $outputPath = Join-Path $script:TestDir "output.md"

            Set-Content -Path $basePath -Value $base
            Set-Content -Path $currentPath -Value $current
            Set-Content -Path $incomingPath -Value $incoming

            $result = Merge-MarkdownFiles -BasePath $basePath `
                                           -CurrentPath $currentPath `
                                           -IncomingPath $incomingPath `
                                           -OutputPath $outputPath

            $result.Success | Should -Be $true
            $output = Get-Content -Path $outputPath -Raw

            # Output should follow incoming order (C, A, B)
            $posC = $output.IndexOf("# Section C")
            $posA = $output.IndexOf("# Section A")
            $posB = $output.IndexOf("# Section B")

            $posC | Should -BeLessThan $posA
            $posA | Should -BeLessThan $posB
        }
    }
}
