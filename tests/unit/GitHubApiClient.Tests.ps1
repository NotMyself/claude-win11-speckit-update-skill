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

        It 'Throws error when API returns null response' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $null
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*empty response*'
        }

        It 'Throws error when response is missing tag_name property' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return @{
                    name = 'Release v0.0.72'
                    assets = @()
                }
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*Missing required property: tag_name*'
        }

        It 'Throws error when response is missing assets property' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return @{
                    tag_name = 'v0.0.72'
                    name = 'Release v0.0.72'
                }
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*Missing required property: assets*'
        }

        It 'Throws error when tag_name has invalid format' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return @{
                    tag_name = 'release-72'
                    name = 'Release 72'
                    assets = @()
                }
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*Invalid version format*'
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

        It 'Throws error when API returns 500-599 server error' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = [System.Net.HttpWebResponse]::new()
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 503 -Force

                $exception = [System.Net.WebException]::new('Service unavailable')
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            { Get-LatestSpecKitRelease } | Should -Throw '*server error*'
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

        It 'Throws error when API returns null response' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $null
            }

            { Get-SpecKitRelease -Version 'v0.0.45' } | Should -Throw '*empty response*'
        }

        It 'Throws error when response is missing tag_name property' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return @{
                    name = 'Release v0.0.45'
                    assets = @()
                }
            }

            { Get-SpecKitRelease -Version 'v0.0.45' } | Should -Throw '*Missing required property: tag_name*'
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

    # Phase 2: Token Support Unit Tests (T009-T020)
    Context 'Token Support - User Story 1 (Backward Compatibility)' {
        BeforeEach {
            # Ensure no token is set
            $env:GITHUB_PAT = $null
        }

        AfterEach {
            # Clean up
            $env:GITHUB_PAT = $null
        }

        It '[T009] Unauthenticated request has no Authorization header' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                param($Uri, $Method, $Headers)

                # Verify Authorization header is NOT present
                $Headers.ContainsKey('Authorization') | Should -Be $false

                return $mockLatestRelease
            }

            $release = Get-LatestSpecKitRelease
            $release | Should -Not -BeNullOrEmpty
        }

        It '[T010] Verbose output shows unauthenticated status' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            # Capture verbose output
            $verboseOutput = Get-LatestSpecKitRelease -Verbose 4>&1 | Out-String

            $verboseOutput | Should -BeLike '*Using unauthenticated request*'
            $verboseOutput | Should -BeLike '*60 req/hour*'
        }

        It '[T011] Existing tests still pass without token set' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            # This test represents backward compatibility - all existing functionality works
            $release = Get-LatestSpecKitRelease
            $release.tag_name | Should -Be 'v0.0.72'
            $release.assets | Should -HaveCount 1
        }
    }

    Context 'Token Support - User Story 2 (Authenticated Requests)' {
        BeforeEach {
            # Set a test token
            $env:GITHUB_PAT = 'ghp_TestToken1234567890123456789012345678'
        }

        AfterEach {
            # Clean up
            $env:GITHUB_PAT = $null
        }

        It '[T012] Token detection when GITHUB_PAT environment variable set' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                param($Uri, $Method, $Headers)

                # Verify Authorization header IS present
                $Headers.ContainsKey('Authorization') | Should -Be $true

                return $mockLatestRelease
            }

            $release = Get-LatestSpecKitRelease
            $release | Should -Not -BeNullOrEmpty
        }

        It '[T013] Authorization header constructed as "Bearer {token}"' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                param($Uri, $Method, $Headers)

                # Verify Authorization header format
                $Headers['Authorization'] | Should -Be "Bearer $env:GITHUB_PAT"
                $Headers['Authorization'] | Should -BeLike 'Bearer ghp_*'

                return $mockLatestRelease
            }

            $release = Get-LatestSpecKitRelease
            $release | Should -Not -BeNullOrEmpty
        }

        It '[T014] Verbose output shows authenticated status with 5,000 req/hour' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            # Capture verbose output
            $verboseOutput = Get-LatestSpecKitRelease -Verbose 4>&1 | Out-String

            $verboseOutput | Should -BeLike '*Using authenticated request*'
            $verboseOutput | Should -BeLike '*5,000 req/hour*'
        }

        It '[T015] Token value never appears in verbose output (security check)' {
            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                return $mockLatestRelease
            }

            # Capture all output streams
            $allOutput = Get-LatestSpecKitRelease -Verbose 4>&1 | Out-String

            # Verify token value is NOT present
            $allOutput | Should -Not -BeLike '*ghp_TestToken*'
            $allOutput | Should -Not -BeLike "*$env:GITHUB_PAT*"
        }
    }

    Context 'Token Support - User Story 5 (Error Message Guidance)' {
        AfterEach {
            # Clean up
            $env:GITHUB_PAT = $null
        }

        It '[T016] Rate limit error without token includes setup tip' {
            $env:GITHUB_PAT = $null

            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = New-Object PSObject
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 403

                # Create headers for rate limit
                $headers = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string[]]]'

                $remainingKvp = New-Object 'System.Collections.Generic.KeyValuePair[string,string[]]' -ArgumentList 'X-RateLimit-Remaining', @('0')
                $headers.Add($remainingKvp)

                $resetKvp = New-Object 'System.Collections.Generic.KeyValuePair[string,string[]]' -ArgumentList 'X-RateLimit-Reset', @('1737294000')
                $headers.Add($resetKvp)

                $response | Add-Member -NotePropertyName Headers -NotePropertyValue $headers

                $exception = New-Object System.Exception 'Rate limit exceeded'
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            $errorThrown = $false
            $errorMessage = ''
            try {
                Get-LatestSpecKitRelease
            }
            catch {
                $errorThrown = $true
                $errorMessage = $_.Exception.Message
            }

            $errorThrown | Should -Be $true
            $errorMessage | Should -BeLike '*Set GITHUB_PAT environment variable*'
            $errorMessage | Should -BeLike '*60 to 5,000 requests/hour*'
        }

        It '[T017] Rate limit error without token includes documentation link' {
            $env:GITHUB_PAT = $null

            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = New-Object PSObject
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 403

                $headers = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string[]]]'
                $remainingKvp = New-Object 'System.Collections.Generic.KeyValuePair[string,string[]]' -ArgumentList 'X-RateLimit-Remaining', @('0')
                $headers.Add($remainingKvp)

                $response | Add-Member -NotePropertyName Headers -NotePropertyValue $headers

                $exception = New-Object System.Exception 'Rate limit exceeded'
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            try {
                Get-LatestSpecKitRelease
            }
            catch {
                $_.Exception.Message | Should -BeLike '*Learn more:*github.com*'
                $_.Exception.Message | Should -BeLike '*#using-github-tokens*'
            }
        }

        It '[T018] Rate limit error WITH token does NOT show setup tip' {
            $env:GITHUB_PAT = 'ghp_TestToken1234567890123456789012345678'

            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = New-Object PSObject
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 403

                $headers = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string[]]]'
                $remainingKvp = New-Object 'System.Collections.Generic.KeyValuePair[string,string[]]' -ArgumentList 'X-RateLimit-Remaining', @('0')
                $headers.Add($remainingKvp)

                $response | Add-Member -NotePropertyName Headers -NotePropertyValue $headers

                $exception = New-Object System.Exception 'Rate limit exceeded'
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            try {
                Get-LatestSpecKitRelease
            }
            catch {
                # Should have rate limit error message
                $_.Exception.Message | Should -BeLike '*rate limit exceeded*'

                # Should NOT have token setup tip (user already has token)
                $_.Exception.Message | Should -Not -BeLike '*Set GITHUB_PAT*'
            }
        }

        It '[T019] Rate limit error shows reset time in local timezone' {
            $env:GITHUB_PAT = $null

            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = New-Object PSObject
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 403

                $headers = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string[]]]'

                $remainingKvp = New-Object 'System.Collections.Generic.KeyValuePair[string,string[]]' -ArgumentList 'X-RateLimit-Remaining', @('0')
                $headers.Add($remainingKvp)

                $resetKvp = New-Object 'System.Collections.Generic.KeyValuePair[string,string[]]' -ArgumentList 'X-RateLimit-Reset', @('1737294000')
                $headers.Add($resetKvp)

                $response | Add-Member -NotePropertyName Headers -NotePropertyValue $headers

                $exception = New-Object System.Exception 'Rate limit exceeded'
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            try {
                Get-LatestSpecKitRelease
            }
            catch {
                # Should contain "Resets at:" with a timestamp
                $_.Exception.Message | Should -BeLike '*Resets at:*'

                # Verify timestamp format (should contain date/time components)
                # Unix timestamp 1737294000 = 2025-01-19 12:00:00 UTC (varies by timezone)
                $_.Exception.Message | Should -Match 'Resets at: \d'
            }
        }

        It '[T020] Invalid token (401) produces clear error message' {
            $env:GITHUB_PAT = 'ghp_InvalidToken123456789012345678901234'

            Mock -ModuleName GitHubApiClient Invoke-RestMethod {
                $response = New-Object PSObject
                $response | Add-Member -NotePropertyName StatusCode -NotePropertyValue 401

                $exception = New-Object System.Exception 'Unauthorized'
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force

                throw $exception
            }

            try {
                Get-LatestSpecKitRelease
            }
            catch {
                $_.Exception.Message | Should -BeLike '*401 Unauthorized*'
                $_.Exception.Message | Should -BeLike '*GITHUB_PAT may be invalid*'
                $_.Exception.Message | Should -BeLike '*https://github.com/settings/tokens*'
            }
        }
    }
}
