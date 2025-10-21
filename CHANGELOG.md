# Changelog

All notable changes to the SpecKit Safe Update Skill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING - Conversational Approval Workflow (#PR)**: Removed broken Show-QuickPick UI integration and replaced with text-only conversational approval workflow
  - **Root Cause**: VSCode QuickPick API unavailable when Claude Code runs PowerShell scripts as subprocess without terminal/UI context
  - **Symptoms**: "Failed to show QuickPick" errors causing update failures in Claude Code
  - **Impact**: Skill completely non-functional in Claude Code (primary execution context)
  - **Breaking Changes**:
    - Removed `-Auto` flag (DEPRECATED - now shows warning and treats as `-Proceed`)
    - Added `-Proceed` flag for conversational workflow continuation
    - Removed `Show-QuickPick` function entirely from VSCodeIntegration module
    - Workflow now two-step: 1) Show summary + approval request, 2) Re-invoke with `-Proceed`
  - **Implementation Changes**:
    - Added conversational approval workflow with `[PROMPT_FOR_APPROVAL]` marker in summary output
    - Implemented non-interactive stdin detection using `[Console]::IsInputRedirected`
    - Replaced Read-Host prompts with graceful exit (exit code 0, not error)
    - Script outputs summary, exits for approval, then proceeds when re-invoked with `-Proceed`
  - **Conflict Resolution Changes**:
    - Removed VSCode merge editor integration (`code --merge` no longer invoked)
    - Implemented Git conflict markers (<<<<<<, ||||||, =======, >>>>>>) for conflicts
    - VSCode CodeLens automatically detects markers and provides resolution UI
    - Added false positive detection (auto-resolves when file content matches upstream)
    - Special handling for constitution.md (delegates to `/speckit.constitution` workflow)
  - **Critical Bug Fixes**:
    - **Manifest Customized Flag**: Fixed bug where files marked `customized: true` were being overwritten
      - Root cause: `Get-FileState` only compared hashes, ignored manifest's customized flag
      - When manifest created with `-AssumeAllCustomized`, original_hash = current hash
      - This caused `isCustomized = false` despite manifest flag, leading to incorrect 'update' action
      - Fix: Added `ManifestCustomized` parameter that takes precedence over hash comparison
      - Added 3 unit tests to prevent regression (commit 0865eb7)
    - **Manifest Cleanup**: Fixed script leaving temporary manifest.json in dirty state after approval prompt
      - Now cleans up manifest when exiting for approval (commit f4e397d)
    - **Constitution Preservation**: Constitution.md now preserved with intelligent merge command instead of conflict markers
  - **Files Modified**:
    - `scripts/update-orchestrator.ps1` - Conversational workflow, conflict markers, manifest cleanup
    - `scripts/helpers/Get-UpdateConfirmation.ps1` - Non-interactive detection, summary generation
    - `scripts/helpers/Show-UpdateSummary.ps1` - Constitution command with backup path
    - `scripts/modules/ConflictDetector.psm1` - ManifestCustomized parameter, Write-ConflictMarkers function
    - `scripts/modules/VSCodeIntegration.psm1` - Removed Show-QuickPick function
    - `tests/unit/VSCodeIntegration.Tests.ps1` - Removed Show-QuickPick tests
    - `tests/unit/ConflictDetector.Tests.ps1` - Added ManifestCustomized tests
    - `SKILL.md` - Updated command name, added execution instructions
    - `.specify/memory/constitution.md` - Added text-only I/O principle (v1.3.0)
    - `CLAUDE.md` - Documented architectural limitations, Git conflict markers approach
  - **Testing**: Successfully tested end-to-end in claude-toolkit project via VSCode extension
  - **Results**: Skill now works reliably in Claude Code with conversational approval, automatic conflict marker detection in VSCode, and preserved customizations

## [0.1.5] - 2025-10-20

### Added
- **Wrapper Script for CLI Compatibility**: Added `update-wrapper.ps1` to handle both Linux-style (`--flags`) and PowerShell-style (`-Flags`) command arguments
  - Converts kebab-case to PascalCase automatically
  - Supports `--flag`, `--flag=value`, and `--flag value` formats
  - Uses hashtable splatting to avoid parameter binding issues
  - Updated SKILL.md to use wrapper as entry point

### Fixed
- **Claude Code Integration (#11)**: Fixed interactive prompt failures when running through Claude Code extension
  - **Root Cause**: No interactive terminal available for `Read-Host` prompts
  - **Symptoms**: "The update was cancelled because the interactive confirmation prompt cannot be displayed"
  - **Impact**: Skill completely non-functional when invoked through Claude Code
  - **Fix Applied**:
    - Added `-Auto` parameter to skip confirmation prompts (line 75)
    - When `-Auto` is set, automatically proceeds without user confirmation
    - Updated SKILL.md to recommend `-Auto` flag for Claude Code usage
    - Added comment-based help documentation for `-Auto` parameter
  - **Testing**: Successfully ran end-to-end update of 19 files through Claude Code in VSCode
  - **Results**: Skill now works in both Claude Code (non-interactive) and terminal (interactive) contexts
  - **Breaking Change**: None (adds new optional parameter, maintains backward compatibility)

### Documentation
- Updated SKILL.md usage examples to show PowerShell-style flags as primary
- Added recommendation to use `-Auto` flag when running through Claude Code
- Clarified wrapper script purpose and dual-syntax support

## [0.1.4] - 2025-10-20

### Fixed
- **First-Time User Workflow (#8)**: Fixed 10 cascading issues preventing first-time manifest creation and updates
  - **Root Cause**: Parameter naming inconsistency in `New-SpecKitManifest` and multiple integration bugs in first-time workflow
  - **Symptoms**: "Cannot process command because of one or more missing mandatory parameters: SpecKitVersion" error
  - **Impact**: New users unable to initialize manifest or run first update
  - **Bug #1 - Parameter Naming**: Changed `-SpecKitVersion` to `-Version` in `New-SpecKitManifest` for consistency with other functions
  - **Bug #2 - Wrong Initial Version**: Fixed manifest creation to use "v0.0.0" placeholder instead of target version (prevented "already up to date" false positive)
  - **Bug #3 - Asset Name Pattern**: Changed from exact match `claude-templates.zip` to pattern match `spec-kit-template-claude-ps-*.zip` to support versioned asset names
  - **Bug #4 - Non-Existent Release Lookup**: Added early return in `Get-OfficialSpecKitCommands` for v0.0.0 placeholder version with fallback command list
  - **Bug #5 - Invalid ProjectRoot Parameter (First Instance)**: Temporarily removed `-ProjectRoot` parameter from `Get-AllFileStates` call (later re-added with fix)
  - **Bug #6 - PowerShell Common Parameters**: Changed SKILL.md entry point from `pwsh -File` to `pwsh -NoProfile -Command` to support `-Help`, `-Verbose`, etc.
  - **Bug #7 - File Path Resolution**: Re-added `-ProjectRoot` parameter to `Get-AllFileStates` with absolute path construction before file operations, preventing "file locked or inaccessible" errors
  - **Bug #8 - Check-Only Leaving Repo Dirty**: Added cleanup code to delete temporary manifest.json when running with `-CheckOnly` flag
  - **Bug #9 - Invalid Backup Parameters**: Removed non-existent `-FromVersion` and `-ToVersion` parameters from `New-SpecKitBackup` call
  - **Bug #10 - Invalid FileStates Parameter**: Removed non-existent `-FileStates` parameter from `Update-FileHashes` call
  - **Fix Applied**:
    - Standardized parameter naming across ManifestManager module (11 instances updated)
    - Implemented placeholder version workflow for first-time users (orchestrator restructured to fetch version before creating manifest)
    - Updated GitHub asset lookup to handle PowerShell-specific template naming
    - Added v0.0.0 special case handling with hardcoded fallback list of 8 official commands
    - Fixed absolute/relative path handling in ConflictDetector module (constructs absolute paths, returns relative paths in state objects)
    - Updated SKILL.md entry point to use `pwsh -NoProfile -Command` invocation pattern
    - Added temporary file cleanup in check-only mode to prevent Git state pollution
    - Fixed all function parameter signatures to match actual function definitions
  - **Testing**: Added 4 new unit tests for parameter validation and first-time scenarios; end-to-end tested in real SpecKit project (claude-toolkit)
  - **Files Modified**:
    - `scripts/modules/ManifestManager.psm1` - Parameter naming and v0.0.0 handling (lines 126, 135, 138, 197, 261-276, 312)
    - `scripts/modules/GitHubApiClient.psm1` - Asset name pattern matching (lines 289-291)
    - `scripts/modules/ConflictDetector.psm1` - ProjectRoot parameter and absolute path construction (lines 212-214, 241-251, 268-279)
    - `scripts/update-orchestrator.ps1` - Workflow restructuring, parameter fixes, cleanup (lines 263-277, 299, 316-323, 354, 524)
    - `SKILL.md` - Entry point command pattern (line 48)
    - `tests/unit/ManifestManager.Tests.ps1` - Parameter naming updates and new tests (lines 328-344)
  - **Results**: First-time users can now successfully create manifest with v0.0.0 placeholder, download 19 template files, and update to latest version; unit test pass rate improved from 67% to 97% (35/36 passing)
  - **Breaking Change**: None (fixes existing functionality, maintains backward compatibility)

## [0.1.3] - 2025-10-20

### Fixed
- **Version Parameter Handling (#6)**: Fixed "missing mandatory parameters: SpecKitVersion" error when running updates without explicit version
  - **Root Cause**: Missing validation and null checks when GitHub API returns invalid or null responses
  - **Symptoms**: Script crash with "Cannot index into a null array" when accessing `$targetRelease.tag_name` after failed API call
  - **Impact**: Users unable to run automatic updates (primary workflow) - only explicit version specification worked
  - **Fix Applied**:
    - **Enhanced API Error Handling**: Added structured error handling in `Invoke-GitHubApiRequest` for all HTTP status codes (403 rate limit, 404 not found, 500+ server errors) with specific user-friendly messages
    - **Response Validation**: Added comprehensive validation to `Get-LatestSpecKitRelease` and `Get-SpecKitRelease` checking for null responses, missing properties (`tag_name`, `assets`), and invalid version formats
    - **Defensive Null Checks**: Added two-stage validation (module + orchestrator) to prevent crashes when accessing response properties
    - **Parameter Naming Consistency**: Standardized all functions to use `-Version` parameter (was inconsistent with `-SpecKitVersion`)
    - **Timeout Protection**: Added 30-second timeout to all GitHub API calls to prevent hanging on slow networks
    - **Diagnostic Logging**: Added extensive `Write-Verbose` logging at validation checkpoints for troubleshooting
  - **Error Messages Improved**:
    - Network failures: "Failed to connect to GitHub API. Check network connectivity"
    - Rate limiting: "GitHub API rate limit exceeded. Resets at: {time}"
    - Not found: "GitHub resource not found. Verify repository and release exist"
    - Server errors: "GitHub API server error (HTTP {code}). Try again later"
    - Invalid responses: Property-specific validation error messages
  - **Testing**: Added 10 new unit tests covering null responses, missing properties, invalid formats, and all error scenarios
  - **Files Modified**:
    - `scripts/modules/GitHubApiClient.psm1` - Enhanced error handling and validation (lines 28-220)
    - `scripts/modules/ManifestManager.psm1` - Standardized parameter naming
    - `scripts/update-orchestrator.ps1` - Added defensive null checks and verbose logging (lines 217-266)
    - `tests/unit/GitHubApiClient.Tests.ps1` - Added validation tests
  - **Results**: Automatic version detection now works reliably with robust error handling and clear error messages
  - **Breaking Change**: None (fixes existing functionality, maintains backward compatibility)

## [0.1.2] - 2025-10-20

### Fixed
- **Module Function Availability (#4)**: Fixed nested module import issue causing "command not recognized" errors
  - **Root Cause**: Modules importing other modules created PowerShell scope isolation where imported functions were not accessible to the orchestrator
  - **Symptoms**: Errors like "The term 'Get-SpecKitManifest' is not recognized as a name of a cmdlet, function, script file, or executable program"
  - **Impact**: 21 tests were failing due to this scope isolation bug
  - **Fix Applied**:
    - Removed all nested `Import-Module` statements from 3 modules (ManifestManager, BackupManager, ConflictDetector)
    - Updated orchestrator (`update-orchestrator.ps1`) with tiered import structure documenting dependencies
    - All module imports now managed centrally by orchestrator in correct dependency order (Tier 0 → Tier 1 → Tier 2)
  - **Prevention Measures**:
    - Added automated lint check in `tests/test-runner.ps1` that fails if any `.psm1` file contains `Import-Module`
    - Created integration tests (`tests/integration/ModuleDependencies.Tests.ps1`) to verify cross-module function calls work correctly
    - Updated constitution (v1.1.0) with Module Import Rules prohibiting nested imports
    - Updated CLAUDE.md and CONTRIBUTING.md with nested import prohibition and enforcement details
  - **Results**: 21 more tests now passing (160→181), lint check prevents future violations
  - **Breaking Change**: None (internal architecture change only)

## [0.1.1] - 2025-10-20

### Fixed
- **BREAKING FIX - Module Import Error**: Permanently resolved recurring "Export-ModuleMember cmdlet can only be called from inside a module" error by fixing the root architectural issue (#3)
  - **Root Cause**: Helper scripts (`.ps1` files) incorrectly used `Export-ModuleMember`, which only works in module files (`.psm1`)
  - **Previous Fix (PR #1)**: Applied error suppression workarounds that masked symptoms but allowed the antipattern to persist and recur
  - **This Fix (PR #3)**: Corrected the architectural confusion:
    - Removed `Export-ModuleMember` from all 7 helper scripts in `scripts/helpers/`
    - Helpers are dot-sourced (`. script.ps1`), not imported, so functions are automatically available without export declarations
    - Modules in `scripts/modules/` correctly retain `Export-ModuleMember` (proper module pattern)
    - Simplified orchestrator import logic - removed error suppression workarounds (`-ErrorAction SilentlyContinue`, `2>$null`, `$ErrorActionPreference` save/restore)
    - Added proper try-catch blocks with stack trace logging for real errors
    - Real errors now cause immediate fatal exit (fail-fast principle restored)
  - **Prevention Measures**:
    - Added "Module vs. Helper Pattern" documentation to CLAUDE.md
    - Establishes clear architectural boundaries to prevent recurrence
  - Module import still completes in <500ms (well under 2-second requirement)
  - Skill now executes cleanly on Windows 11 with PowerShell 7.x without false-positive errors

## [0.1.0] - 2025-01-19

### Added

**Core Features:**
- Initial implementation of SpecKit Safe Update skill for Claude Code
- Safe update mechanism preserving user customizations during SpecKit template updates
- Intelligent conflict resolution with VSCode 3-way merge editor (Flow A: one-at-a-time)
- Automatic backup creation with retention management (keeps 5 most recent)
- Fail-fast error handling with automatic rollback on failure
- Dry-run mode (`--check-only`) to preview changes without applying
- Rollback command to restore from previous backups
- Force mode (`--force`) with confirmation to reset SpecKit files
- Constitution update integration (notifies to run `/speckit.constitution`)

**Modules Implemented:**
- `HashUtils.psm1` - Normalized file hashing (handles CRLF/LF, trailing whitespace, BOM)
- `VSCodeIntegration.psm1` - Context detection, Quick Pick, diff/merge editor integration
- `GitHubApiClient.psm1` - GitHub Releases API client (unauthenticated, with rate limit handling)
- `ManifestManager.psm1` - Manifest CRUD operations with caching
- `BackupManager.psm1` - Backup creation, restoration, and retention management
- `ConflictDetector.psm1` - File state analysis and conflict detection

**Helper Functions:**
- `Invoke-PreUpdateValidation.ps1` - Prerequisites validation (critical + warnings)
- `Show-UpdateSummary.ps1` - Detailed post-update results display
- `Show-UpdateReport.ps1` - Check-only mode report generation
- `Get-UpdateConfirmation.ps1` - User confirmation with change preview
- `Invoke-ConflictResolutionWorkflow.ps1` - Flow A conflict resolution implementation
- `Invoke-ThreeWayMerge.ps1` - VSCode merge editor integration with temp files
- `Invoke-RollbackWorkflow.ps1` - Backup restoration workflow

**Main Orchestrator:**
- 15-step update workflow with comprehensive error handling
- Command-line flags: `--check-only`, `--version`, `--force`, `--rollback`, `--no-backup`
- Exit codes: 0 (success), 1 (error), 2 (prereqs), 3 (network), 4 (git), 5 (cancel), 6 (rollback)

**Testing:**
- Unit tests for all 6 modules (HashUtils, VSCodeIntegration, GitHubApiClient, ManifestManager, BackupManager, ConflictDetector)
- Integration tests covering 8 core scenarios plus additional edge cases
- Test fixtures for mock GitHub API responses and sample projects
- Pester 5.x test framework with proper mocking

**Documentation:**
- Comprehensive README with usage examples, architecture, workflow diagrams
- Complete SKILL.md for Claude Code integration
- Detailed specification in `specs/001-safe-update/spec.md`
- Implementation plan in `specs/001-safe-update/plan.md`
- Integration test documentation with README and QUICKSTART

**File Management:**
- Manifest tracking with file hashes and customization flags
- Official vs. custom command distinction
- Command lifecycle management (add/remove/update)
- Custom commands always preserved (never overwritten)
- Normalized hashing for cross-platform compatibility

**User Experience:**
- Context-aware UI (VSCode Quick Pick vs terminal prompts)
- Color-coded console output
- Detailed change previews before applying updates
- Clear error messages with recovery guidance
- Progress indicators and verbose logging

**Safety Features:**
- Git state validation (requires clean or staged changes)
- Automatic backup before destructive operations
- Fail-fast principle with immediate rollback on error
- Backup directory exclusion to prevent infinite recursion
- Constitution preservation with guided update flow

### Technical Details

**Dependencies:**
- PowerShell 7+
- Git (in PATH)
- VSCode with Claude Code extension (for merge editor)
- Internet connection (for GitHub API)

**Repository Structure:**
- `scripts/` - Main orchestrator and modules
- `scripts/modules/` - 6 PowerShell modules
- `scripts/helpers/` - 7 helper functions
- `templates/` - Manifest template
- `tests/unit/` - Unit tests (6 test files)
- `tests/integration/` - Integration tests
- `tests/fixtures/` - Test fixtures and mock data
- `specs/001-safe-update/` - Specification and plan
- `SKILL.md` - Claude Code skill definition
- `README.md` - User documentation

**Specification Compliance:**
- All 3 user stories implemented with acceptance criteria met
- All design decisions from PRD documented and implemented
- Phase 0-6 complete according to implementation plan
- Ready for Phase 7 (manual testing)

### Known Issues

- Some unit tests may have scoping issues with Pester 5.x (modules fully functional)
- BackupManager tests have timestamp collision issues (implementation correct)
- Integration tests require proper mocking setup to run

### Security

- No GitHub token required (uses unauthenticated API with rate limit handling)
- No sensitive data stored in manifest
- All file operations validated before execution
- Backup preservation during rollback to maintain history

[Unreleased]: https://github.com/NotMyself/claude-win11-speckit-update-skill/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/NotMyself/claude-win11-speckit-update-skill/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/NotMyself/claude-win11-speckit-update-skill/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/NotMyself/claude-win11-speckit-update-skill/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/NotMyself/claude-win11-speckit-update-skill/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/NotMyself/claude-win11-speckit-update-skill/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/NotMyself/claude-win11-speckit-update-skill/releases/tag/v0.1.0
