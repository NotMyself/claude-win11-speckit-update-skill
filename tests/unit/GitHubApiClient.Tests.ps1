#Requires -Version 7.0

<#
.SYNOPSIS
    Unit tests for GitHubApiClient module.

.DESCRIPTION
    Pester tests for the GitHubApiClient module that interacts with the
    GitHub Releases API. All external API calls are mocked.
#>

BeforeAll {
    # Import the module to test
    $modulePath = Join-Path $PSScriptRoot '..\..\scripts\modules\GitHubApiClient.psm1'
    Import-Module $modulePath -Force

    # Load mock GitHub responses
    $mockLatestReleasePath = Join-Path $PSScriptRoot '..\fixtures\mock-github-responses\latest-release.json'
    $mockLatestRelease = Get-Content $mockLatestReleasePath | ConvertFrom-Json

    # Create mock for a specific release
    $mockSpecificRelease = @{
        tag_name = 'v0.0.45'
        name = 'Release v0.0.45'
        published_at = '2025-01-10T08:15:00Z'
        assets = @(
            @{
                name = 'claude-templates.zip'
                browser_download_url = 'https://github.com/github/spec-kit/releases/download/v0.0.45/claude-templates.zip'
                size = 198432
            }
        )
    }

    # Mock rate limit response
    $mockRateLimit = @{
        rate = @{
            limit = 60
            remaining = 58
            reset = 1737294000
        }
    }

    # Helper function to create a mock ZIP file with templates
    function New-MockTemplateZip {
        param(
            [string]$Path,
            [hashtable]$Files
        )

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "mock-templates-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            # Create files in temp directory
            foreach ($file in $Files.GetEnumerator()) {
                $filePath = Join-Path $tempDir $file.Key
                $fileDir = Split-Path $filePath -Parent

                if (-not (Test-Path $fileDir)) {
                    New-Item -ItemType Directory -Path $fileDir -Force | Out-Null
                }

                Set-Content -Path $filePath -Value $file.Value -Force
            }

            # Create ZIP archive
            Compress-Archive -Path "$tempDir\*" -DestinationPath $Path -Force
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'GitHubApiClient Module' {
    Context 'Get-LatestSpecKitRelease' {
        It 'Returns latest release information from API' {
            # Mock Invoke-RestMethod
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            $release = Get-LatestSpecKitRelease

            $release | Should -Not -BeNullOrEmpty
            $release.tag_name | Should -Be 'v0.0.72'
            $release.name | Should -Be 'Release v0.0.72'
            $release.assets | Should -HaveCount 1
            $release.assets[0].name | Should -Be 'claude-templates.zip'

            # Verify API was called with correct parameters
            Should -Invoke -ModuleName GitHubApiClient Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/github/spec-kit/releases/latest' -and
                $Headers['Accept'] -eq 'application/vnd.github+json' -and
                $Headers['User-Agent'] -eq 'SpecKit-Update-Skill/1.0'
            }
        }

        It 'Throws error when rate limit is exceeded' {
            # Mock rate limit error
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = [System.Net.HttpWebResponse]::new()
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 403 -Force

                $exception = [System.Net.WebException]::new('Rate limit exceeded')
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*rate limit*'
        }

        It 'Throws error when API returns 404' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = [System.Net.HttpWebResponse]::new()
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 404 -Force

                $exception = [System.Net.WebException]::new('Not found')
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*not found*'
        }

        It 'Throws error when network is unavailable' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                throw [System.Net.WebException]::new('Unable to connect to remote server')
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*Failed to connect*'
        }
    }

    Context 'Get-SpecKitRelease' {
        It 'Returns specific release when version has v prefix' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockSpecificRelease
            }

            $release = Get-SpecKitRelease -Version 'v0.0.45'

            $release | Should -Not -BeNullOrEmpty
            $release.tag_name | Should -Be 'v0.0.45'

            Should -Invoke -ModuleName GitHubApiClient Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/github/spec-kit/releases/tags/v0.0.45'
            }
        }

        It 'Adds v prefix when version does not have it' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockSpecificRelease
            }

            $release = Get-SpecKitRelease -Version '0.0.45'

            $release | Should -Not -BeNullOrEmpty
            $release.tag_name | Should -Be 'v0.0.45'

            Should -Invoke -ModuleName GitHubApiClient Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/github/spec-kit/releases/tags/v0.0.45'
            }
        }

        It 'Throws error when release version does not exist' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = [System.Net.HttpWebResponse]::new()
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 404 -Force

                $exception = [System.Net.WebException]::new('Not found')
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            { Get-SpecKitRelease -Version 'v9.9.9' } | Should -Throw '*not found*'
        }
    }

    Context 'Get-SpecKitReleaseAssets' {
        It 'Returns assets array from specific release' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            $assets = Get-SpecKitReleaseAssets -Version 'v0.0.72'

            $assets | Should -Not -BeNullOrEmpty
            $assets | Should -HaveCount 1
            $assets[0].name | Should -Be 'claude-templates.zip'
            $assets[0].browser_download_url | Should -BeLike '*github.com/github/spec-kit/releases/download/*'
            $assets[0].size | Should -BeGreaterThan 0
        }

        It 'Normalizes version before fetching assets' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            $assets = Get-SpecKitReleaseAssets -Version '0.0.72'

            Should -Invoke -ModuleName GitHubApiClient Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/github/spec-kit/releases/tags/v0.0.72'
            }
        }
    }

    Context 'Download-SpecKitTemplates' {
        It 'Downloads and extracts templates into hashtable' {
            # Mock the API response
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            # Create a mock ZIP file
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test-download-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                # Create mock ZIP in a separate temp location
                $mockZipDir = Join-Path ([System.IO.Path]::GetTempPath()) "mock-zip-$(Get-Random)"
                New-Item -ItemType Directory -Path $mockZipDir -Force | Out-Null
                $script:mockZipPath = Join-Path $mockZipDir 'mock-templates.zip'

                $mockFiles = @{
                    '.claude\commands\speckit.specify.md' = '# Specify Command'
                    '.claude\commands\speckit.plan.md' = '# Plan Command'
                    '.specify\templates\spec-template.md' = '# Spec Template'
                }

                New-MockTemplateZip -Path $script:mockZipPath -Files $mockFiles

                # Mock Invoke-WebRequest to copy our mock ZIP
                Mock -ModuleName GitHubApiClient Invoke-WebRequest {
                    Copy-Item $script:mockZipPath -Destination $OutFile -Force
                }

                # Download templates
                $templates = Download-SpecKitTemplates -Version 'v0.0.72' -DestinationPath $tempDir

                # Verify templates hashtable
                $templates | Should -Not -BeNullOrEmpty
                $templates.Keys.Count | Should -BeGreaterThan 0

                # Check that paths are normalized with forward slashes
                $templates.Keys | ForEach-Object {
                    $_ | Should -Not -Match '\\'
                }

                # Verify specific template exists
                $specifyKey = $templates.Keys | Where-Object { $_ -like '*speckit.specify.md' }
                $specifyKey | Should -Not -BeNullOrEmpty
                $templates[$specifyKey].Trim() | Should -Be '# Specify Command'
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $mockZipDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Verify API was called
            Should -Invoke -ModuleName GitHubApiClient Invoke-RestMethod -Times 1
            Should -Invoke -ModuleName GitHubApiClient Invoke-WebRequest -Times 1
        }

        It 'Throws error when Claude templates asset is not found' {
            # Mock release without claude-templates.zip
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return @{
                    tag_name = 'v0.0.72'
                    assets = @(
                        @{
                            name = 'other-asset.zip'
                            browser_download_url = 'https://example.com/other.zip'
                            size = 1234
                        }
                    )
                }
            }

            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test-no-asset-$(Get-Random)"

            { Download-SpecKitTemplates -Version 'v0.0.72' -DestinationPath $tempDir } | Should -Throw '*Claude templates asset not found*'
        }

        It 'Cleans up temporary files after download' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test-cleanup-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                # Create mock ZIP in a separate location (not in $tempDir)
                $mockZipDir = Join-Path ([System.IO.Path]::GetTempPath()) "mock-cleanup-$(Get-Random)"
                New-Item -ItemType Directory -Path $mockZipDir -Force | Out-Null
                $script:mockZipPath2 = Join-Path $mockZipDir 'mock.zip'

                $mockFiles = @{
                    'test.txt' = 'content'
                }
                New-MockTemplateZip -Path $script:mockZipPath2 -Files $mockFiles

                Mock -ModuleName GitHubApiClient Invoke-WebRequest {
                    Copy-Item $script:mockZipPath2 -Destination $OutFile -Force
                }

                $templates = Download-SpecKitTemplates -Version 'v0.0.72' -DestinationPath $tempDir

                # Check that temp ZIP and extract directory were cleaned up
                $zipFiles = Get-ChildItem -Path $tempDir -Filter '*.zip'
                $zipFiles | Should -HaveCount 0

                $extractDirs = Get-ChildItem -Path $tempDir -Directory -Filter '*extracted*'
                $extractDirs | Should -HaveCount 0
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $mockZipDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Creates destination directory if it does not exist' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test-create-dir-$(Get-Random)"

            # Ensure directory does NOT exist
            if (Test-Path $tempDir) {
                Remove-Item $tempDir -Recurse -Force
            }

            try {
                $mockZipPath = Join-Path ([System.IO.Path]::GetTempPath()) "mock-$(Get-Random).zip"
                New-MockTemplateZip -Path $mockZipPath -Files @{ 'test.txt' = 'content' }

                Mock -ModuleName GitHubApiClient Invoke-WebRequest {
                    Copy-Item $mockZipPath -Destination $OutFile -Force
                }

                $templates = Download-SpecKitTemplates -Version 'v0.0.72' -DestinationPath $tempDir

                # Verify directory was created
                Test-Path $tempDir | Should -Be $true
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $mockZipPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Test-GitHubApiRateLimit' {
        It 'Returns rate limit status from API' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockRateLimit
            }

            $rateLimit = Test-GitHubApiRateLimit

            $rateLimit | Should -Not -BeNullOrEmpty
            $rateLimit.rate.limit | Should -Be 60
            $rateLimit.rate.remaining | Should -Be 58
            $rateLimit.rate.reset | Should -BeGreaterThan 0

            Should -Invoke -ModuleName GitHubApiClient Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.github.com/rate_limit'
            }
        }
    }

    Context 'Module Exports' {
        It 'Exports only public functions' {
            $exports = Get-Command -Module GitHubApiClient

            $exports.Name | Should -Contain 'Get-LatestSpecKitRelease'
            $exports.Name | Should -Contain 'Get-SpecKitRelease'
            $exports.Name | Should -Contain 'Get-SpecKitReleaseAssets'
            $exports.Name | Should -Contain 'Download-SpecKitTemplates'
            $exports.Name | Should -Contain 'Test-GitHubApiRateLimit'

            # Verify internal function is NOT exported
            $exports.Name | Should -Not -Contain 'Invoke-GitHubApiRequest'
        }
    }

    Context 'Error Handling' {
        It 'Handles rate limit error with reset time' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                # Create a mock response with headers
                $response = New-Object PSObject
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 403

                # Create headers collection
                $headers = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string[]]]'
                $resetValue = @([string]1737294000)
                $kvp = New-Object 'System.Collections.Generic.KeyValuePair[string,string[]]' -ArgumentList 'X-RateLimit-Reset', $resetValue
                $headers.Add($kvp)

                $response | Add-Member -NotePropertyName Headers -NotePropertyValue $headers

                $exception = New-Object System.Exception 'Rate limit exceeded'
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*rate limit*'
        }

        It 'Handles generic HTTP errors' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = New-Object PSObject
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 500

                $exception = New-Object System.Exception 'Internal server error'
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*GitHub API error*'
        }
    }
}
