# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **Claude Code Skill** that provides safe, automated updates for SpecKit installations. The skill preserves user customizations while applying template updates from GitHub releases, eliminating destructive `specify init --force` workflows.

**Key Concept:** This is distributed as a Git repository that users clone into `$env:USERPROFILE\.claude\skills\speckit-updater`. Claude Code automatically loads the `/speckit-update` command from [SKILL.md](SKILL.md).

## Common Commands

### Testing
```powershell
# Run all tests (unit + integration)
./tests/test-runner.ps1

# Run only unit tests
./tests/test-runner.ps1 -Unit

# Run only integration tests
./tests/test-runner.ps1 -Integration

# Run with code coverage
./tests/test-runner.ps1 -Coverage
```

### Manual Testing
```powershell
# Test the orchestrator directly (from a SpecKit project directory)
& "path\to\scripts\update-orchestrator.ps1" -CheckOnly

# Test with specific version
& "path\to\scripts\update-orchestrator.ps1" -Version v0.0.72 -CheckOnly

# Test rollback
& "path\to\scripts\update-orchestrator.ps1" -Rollback
```

### Development
```powershell
# Import modules for testing in PowerShell session
Import-Module .\scripts\modules\HashUtils.psm1 -Force
Import-Module .\scripts\modules\ManifestManager.psm1 -Force

# Test individual functions
Get-NormalizedHash -FilePath ".\README.md"
```

## Architecture

### Module vs. Helper Pattern

**IMPORTANT**: This codebase uses two distinct patterns for organizing PowerShell code. Understanding this distinction is critical to prevent recurring module import errors.

**Modules** (`.psm1` files in `scripts/modules/`):
- Imported with `Import-Module`
- Run in their own module scope (isolated from caller)
- MUST use `Export-ModuleMember` to export functions
- Used for business logic with public/private function separation
- Example: `HashUtils.psm1`, `ManifestManager.psm1`

**Helpers** (`.ps1` files in `scripts/helpers/`):
- Dot-sourced with `. script.ps1`
- Run in the caller's current scope (no isolation)
- MUST NOT use `Export-ModuleMember` (causes fatal errors)
- Functions are automatically available after dot-sourcing
- Used for thin orchestration wrappers around module functions
- Example: `Show-UpdateSummary.ps1`, `Get-UpdateConfirmation.ps1`

**Why This Matters**: `Export-ModuleMember` only works inside PowerShell module scope. Using it in dot-sourced scripts causes "Export-ModuleMember cmdlet can only be called from inside a module" errors that terminate script execution.

**Rule of Thumb**:
- If you use `Import-Module`, use `Export-ModuleMember`
- If you use dot-sourcing (`. script.ps1`), do NOT use `Export-ModuleMember`

**Nested Import Prohibition** (Added: 2025-10-20):
- **Modules MUST NOT import other modules**
- All `Import-Module` statements MUST be in the orchestrator (`update-orchestrator.ps1`)
- Nested imports create scope isolation where functions imported within a module are not accessible to the calling script
- **Enforcement**: Automated lint check in `tests/test-runner.ps1` fails if any `.psm1` file contains `Import-Module`
- **Pattern**: Orchestrator imports modules in dependency order (Tier 0 → Tier 1 → Tier 2)

**Correct Pattern** (orchestrator manages all imports):
```powershell
# scripts/update-orchestrator.ps1

# TIER 0: Foundation modules (no dependencies)
Import-Module (Join-Path $modulesPath "HashUtils.psm1") -Force
Import-Module (Join-Path $modulesPath "GitHubApiClient.psm1") -Force
Import-Module (Join-Path $modulesPath "VSCodeIntegration.psm1") -Force

# TIER 1: Modules depending on Tier 0
Import-Module (Join-Path $modulesPath "ManifestManager.psm1") -Force

# TIER 2: Modules depending on Tier 1
Import-Module (Join-Path $modulesPath "BackupManager.psm1") -Force
Import-Module (Join-Path $modulesPath "ConflictDetector.psm1") -Force
```

**Incorrect Pattern** (nested imports):
```powershell
# scripts/modules/ManifestManager.psm1 - ❌ INCORRECT
Import-Module (Join-Path $PSScriptRoot "HashUtils.psm1") -Force  # DO NOT DO THIS
```

See [.specify/memory/constitution.md - Module Import Rules](.specify/memory/constitution.md#module-import-rules-added-2025-10-20) for detailed rationale.

### Entry Point and Orchestration

**[scripts/update-orchestrator.ps1](scripts/update-orchestrator.ps1)** is the main entry point invoked by Claude Code. It coordinates all 15 steps of the update workflow in sequence:

1. Validates prerequisites (Git, permissions, .specify/ directory)
2. Handles rollback requests
3. Loads/creates manifest (`.specify/manifest.json`)
4. Fetches target version from GitHub Releases API
5. Analyzes file states (customized vs. default)
6. Shows check-only report (if `-CheckOnly`)
7. Gets user confirmation
8. Creates timestamped backup
9. Downloads templates from GitHub
10. Applies selective updates
11. Handles conflicts via 3-way merge
12. Notifies about constitution updates
13. Updates manifest with new version/hashes
14. Cleans up old backups (retention management)
15. Shows detailed summary

### Core Modules (scripts/modules/)

**Critical Architecture Decision:** All business logic lives in modules, not helpers. Modules are stateless, reusable, and testable.

- **[HashUtils.psm1](scripts/modules/HashUtils.psm1)** - Normalized SHA-256 hashing
  - Handles CRLF/LF normalization, trailing whitespace, BOM removal
  - Ensures cross-platform/editor consistency for detecting real changes

- **[VSCodeIntegration.psm1](scripts/modules/VSCodeIntegration.psm1)** - VSCode context detection
  - Detects if running in Claude Code vs. terminal
  - Opens VSCode 3-way merge editor for conflicts
  - Invokes `code` CLI commands

- **[GitHubApiClient.psm1](scripts/modules/GitHubApiClient.psm1)** - GitHub Releases API
  - Fetches latest/specific release metadata
  - Downloads template archives
  - Unauthenticated (60 req/hour rate limit)

- **[ManifestManager.psm1](scripts/modules/ManifestManager.psm1)** - Manifest CRUD
  - Reads/writes `.specify/manifest.json`
  - Tracks SpecKit version, file hashes, customization flags
  - Maintains backup history

- **[BackupManager.psm1](scripts/modules/BackupManager.psm1)** - Backup/restore
  - Creates timestamped backups in `.specify/backups/YYYY-MM-DD_HH-MM-SS/`
  - Restores from backup on rollback
  - Manages retention (keeps 5 most recent)

- **[ConflictDetector.psm1](scripts/modules/ConflictDetector.psm1)** - File state analysis
  - Compares current file hashes vs. manifest vs. upstream
  - Categorizes files: `add`, `remove`, `update`, `preserve`, `merge`, `skip`
  - Identifies official SpecKit commands vs. custom commands

### Helper Functions (scripts/helpers/)

Helpers are thin orchestration wrappers that call module functions. They handle user prompts and UI:

- **Invoke-PreUpdateValidation.ps1** - Prerequisites checks (Git, .specify/, permissions)
- **Show-UpdateReport.ps1** - Check-only mode detailed report
- **Get-UpdateConfirmation.ps1** - User confirmation prompt with change preview
- **Show-UpdateSummary.ps1** - Post-update results display
- **Invoke-ConflictResolutionWorkflow.ps1** - Flow A conflict resolution (one-at-a-time)
- **Invoke-ThreeWayMerge.ps1** - VSCode merge editor integration
- **Invoke-RollbackWorkflow.ps1** - Backup restoration workflow

### Data Structures

**Manifest Schema** (`.specify/manifest.json`):
```json
{
  "version": "1.0",
  "speckit_version": "v0.0.72",
  "initialized_at": "2025-01-19T12:34:56Z",
  "last_updated": "2025-01-19T14:22:10Z",
  "agent": "claude-code",
  "speckit_commands": ["speckit.specify.md", "speckit.plan.md", ...],
  "tracked_files": [
    {
      "path": ".claude/commands/speckit.specify.md",
      "original_hash": "sha256:abc123...",
      "customized": false,
      "is_official": true
    }
  ],
  "custom_files": [".claude/commands/custom-deploy.md"],
  "backup_history": [
    {
      "timestamp": "2025-01-19T12:00:00Z",
      "path": ".specify/backups/2025-01-19_12-00-00/",
      "from_version": "v0.0.71",
      "to_version": "v0.0.72"
    }
  ]
}
```

**File State Enum** (used throughout ConflictDetector):
- `add` - New file in upstream, not in local
- `remove` - File removed from upstream
- `update` - File unchanged locally, has upstream changes (safe to update)
- `preserve` - File customized locally, no upstream changes (keep as-is)
- `merge` - File customized locally AND has upstream changes (conflict!)
- `skip` - No changes needed

## Architectural Limitations

### Text-Only I/O Constraint

**Critical Design Constraint:** This skill runs as a PowerShell subprocess spawned by Claude Code via `pwsh -Command`. The execution model has fundamental I/O limitations:

```
Claude Code Extension (JavaScript)
    ↓ spawns
PowerShell Process (pwsh -Command "& 'script.ps1'")
    ↓ captures
stdout (text stream) + stderr (text stream)
    ↓ displays
User sees text output
```

**Implications:**
- **No VSCode UI Access**: PowerShell subprocess cannot invoke VSCode extension APIs or UI elements (Quick Pick, dialogs, webviews)
- **No IPC Bridge**: No inter-process communication mechanism exists for passing structured data between PowerShell and VSCode extension host
- **Text Streams Only**: All communication must use stdout/stderr text streams
- **No External GUI**: PowerShell GUI cmdlets (e.g., `Out-GridView`, WPF windows) won't work in Claude Code context

**What Works:**
- ✅ Text output to stdout (Write-Host, Write-Output)
- ✅ Error messages to stderr (Write-Error, Write-Warning)
- ✅ Reading environment variables (e.g., `$env:VSCODE_PID` for context detection)
- ✅ File I/O operations
- ✅ Invoking `code` CLI commands (e.g., `code --diff`, `code --merge`) as separate processes

**What Doesn't Work:**
- ❌ Returning PowerShell objects expecting Claude extension to parse them
- ❌ Sentinel hashtables for VSCode Quick Pick interception
- ❌ Direct calls to VSCode extension APIs
- ❌ GUI dialog boxes or interactive prompts expecting VSCode UI integration

### Conversational Workflow Pattern

Given the text-only constraint, this skill uses a **conversational approval workflow**:

1. **Skill outputs structured summary** to stdout (Markdown format)
2. **Claude Code parses summary** and presents it to user in natural language
3. **User responds via chat** ("yes", "proceed", "no", questions, etc.)
4. **Claude re-invokes skill** with `-Proceed` flag if approved
5. **Skill executes update** without prompts (approval already obtained)

This pattern:
- Respects text-only I/O constraint
- Leverages Claude's conversational interface
- Provides better UX than Read-Host prompts in terminal
- Works identically in Claude Code CLI and VSCode Extension contexts

## Smart Conflict Resolution

When files have both local customizations AND upstream changes, the skill uses **intelligent conflict resolution** that adapts based on file size:

### Two-Tier Resolution Strategy

**Small Files (≤100 lines):** Git conflict markers (standard 3-way merge)
**Large Files (>100 lines):** Side-by-side diff files in Markdown format

This dual approach provides optimal UX for different scenarios:
- Small files: Quick inline resolution with VSCode CodeLens
- Large files: Comprehensive side-by-side comparison in readable format

### Small File Resolution: Git Conflict Markers

For files with 100 lines or fewer, the skill writes Git-style conflict markers directly to the file:

```markdown
<<<<<<< Current (Your Version)
# Custom content you added
||||||| Base (v0.0.71)
# Original version content
=======
# New upstream content
>>>>>>> Incoming (v0.0.72)
```

**VSCode Integration:** VSCode automatically detects these markers and displays **CodeLens actions**:
- Accept Current Change
- Accept Incoming Change
- Accept Both Changes
- Compare Changes

**Benefits:**
- Familiar UX for developers (standard Git workflow)
- Immediate inline editing
- Works in all text editors
- User resolves conflicts at their own pace

### Large File Resolution: Side-by-Side Diff Files

For files with more than 100 lines, the skill generates a detailed Markdown diff file in `.specify/.tmp-conflicts/`:

**Example:** If `custom-large.md` has a conflict, the skill creates `.specify/.tmp-conflicts/custom-large.diff.md`

**Diff File Features:**
- Header with version comparison and file metadata
- Only changed sections shown (with 3-line context before/after)
- Side-by-side comparison: "Your Version" vs "Incoming Version"
- Syntax highlighting based on file extension
- Summary of unchanged sections (e.g., "Lines 1-50 unchanged")
- UTF-8 encoding without BOM for cross-platform compatibility

**Why This Approach:**
- Large files with Git markers are difficult to navigate
- Side-by-side view makes changes easier to understand
- Unchanged sections summary helps focus on what actually changed
- Markdown format previews beautifully in VSCode
- Diff files are automatically cleaned up after successful updates

See [Example Diff File Output](#example-diff-file-output) below for a complete example.

### Implementation

The `Write-SmartConflictResolution` function (ConflictDetector.psm1) automatically routes to the appropriate resolution method:

```powershell
Write-SmartConflictResolution -FilePath ".claude/commands/custom-file.md" `
                               -CurrentContent $currentVersion `
                               -BaseContent $originalVersion `
                               -IncomingContent $upstreamVersion `
                               -OriginalVersion "v0.0.71" `
                               -NewVersion "v0.0.72"
```

The function counts lines in `CurrentContent` and:
- If ≤100 lines: Calls `Write-ConflictMarkers` (Git markers)
- If >100 lines: Calls `Compare-FileSections` + `Write-SideBySideDiff` (Markdown diff)
- On error: Falls back to Git markers as a safety measure

**Automatic Cleanup:** After a successful update, `.specify/.tmp-conflicts/` is automatically removed. On rollback, diff files are preserved for debugging.

### Example Diff File Output

Here's an example of a generated diff file for a large file conflict:

```markdown
# Conflict Resolution: speckit.plan.md

**Your Version**: v0.0.71
**Incoming Version**: v0.0.72
**File Path**: `.claude/commands/speckit.plan.md`
**File Size**: 150 lines
**Changed Sections**: 2
**Total Changed Lines**: 8

---

## Changed Section 1

### Your Version (Lines 45-51)

```markdown
## Step 3: Design Phase

Review the requirements and create a detailed implementation plan.
Use the plan template to structure your approach.
```

### Incoming Version (Lines 45-51)

```markdown
## Step 3: Design Phase

Review the requirements and create a detailed implementation plan.
Use the plan template to structure your approach and identify dependencies.
Consider error handling and edge cases early in the design.
```

---

## Changed Section 2

### Your Version (Lines 98-104)

```markdown
## Validation Checklist

- [ ] All requirements met
- [ ] Tests passing
```

### Incoming Version (Lines 98-106)

```markdown
## Validation Checklist

- [ ] All requirements met
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] Documentation updated
```

---

## Unchanged Sections

The following sections remain unchanged between versions:

- **Lines 1-44** (44 lines): Header and introduction
- **Lines 52-97** (46 lines): Middle content sections
- **Lines 107-150** (44 lines): Footer and references

**Total Unchanged**: 134 lines (89.3%)
```

This format makes it easy to:
1. See exactly what changed and where
2. Compare side-by-side without scrolling through the entire file
3. Understand the scope of changes (only 11% of the file changed)
4. Preview beautifully in VSCode's Markdown preview

## Key Workflows

### Conflict Resolution (Flow A)

When a file is customized locally AND changed upstream:

1. List all conflicts upfront
2. For each conflict, prompt user with 4 options:
   - **Open merge editor** - VSCode 3-way merge (base/current/incoming)
   - **Keep my version** - Discard upstream changes
   - **Use new version** - Discard local changes
   - **Skip for now** - Resolve manually later
3. Track resolved vs. skipped conflicts
4. Clean up temporary `.tmp-merge/` files automatically

### Customization Detection

Files are considered "customized" if their normalized hash differs from `original_hash` in manifest. Normalization ensures line ending differences don't trigger false positives.

**Safe Default:** If no manifest exists, assume ALL files are customized (prevents data loss).

### Fail-Fast with Rollback

Any error during steps 8-13 triggers automatic rollback:
1. Error displayed
2. Most recent backup restored
3. Exit code 6 returned
4. Manifest reverted to pre-update state

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Prerequisites not met |
| 3 | Network/API error |
| 4 | Git error |
| 5 | User cancelled |
| 6 | Rollback occurred (automatic) |

## Testing Strategy

### Unit Tests
- **Location:** [tests/unit/](tests/unit/)
- **Pattern:** `ModuleName.Tests.ps1` (e.g., `HashUtils.Tests.ps1`)
- **Framework:** Pester 5.x
- **Scope:** Test individual module functions in isolation with mocking
- **Status:** 132 passing, 45 failing (known Pester 5.x scoping issues - modules work correctly in real usage)

### Integration Tests
- **Location:** [tests/integration/](tests/integration/)
- **Pattern:** `UpdateOrchestrator.Tests.ps1`
- **Scope:** Test full end-to-end workflows with real file system operations
- **Note:** Skipped in CI/CD, run manually before releases

### Known Testing Issues
- VSCodeIntegration module has mocking limitations (10 tests skipped)
- Pester 5.x module scoping causes false failures in unit tests
- All actual module functionality works correctly in practice

## PowerShell Style Guidelines

Follow these conventions (enforced in [CONTRIBUTING.md](CONTRIBUTING.md)):

- **Function Names:** PascalCase with approved verbs (`Get-FileState`, `Invoke-PreUpdateValidation`)
- **Variables:** camelCase (`$fileName`, `$manifestPath`)
- **Parameters:** PascalCase in param blocks
- **Comment-Based Help:** Every exported function MUST have `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- **Error Handling:** Use try-catch-finally, `$ErrorActionPreference = 'Stop'` in scripts
- **Verbose Logging:** Use `Write-Verbose` liberally for debugging

Example:
```powershell
function Get-Example {
    <#
    .SYNOPSIS
        Brief description
    .PARAMETER Name
        Parameter description
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        Write-Verbose "Processing: $Name"
        # Implementation
    }
    catch {
        Write-Error "Error: $($_.Exception.Message)"
        throw
    }
}
```

## Distribution Model

**This skill is NOT published to npm or PowerShell Gallery.** Users install by cloning the Git repository:

```powershell
cd $env:USERPROFILE\.claude\skills
git clone https://github.com/NotMyself/claude-win11-speckit-update-skill speckit-updater
```

Claude Code automatically discovers [SKILL.md](SKILL.md) and makes `/speckit-update` available.

## Important Files

- **[SKILL.md](SKILL.md)** - Claude Code skill definition (defines `/speckit-update` command)
- **[specs/001-safe-update/spec.md](specs/001-safe-update/spec.md)** - Complete specification with user stories, architecture, workflows
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development guidelines, testing, PR process
- **[CHANGELOG.md](CHANGELOG.md)** - Version history
- **[templates/manifest-template.json](templates/manifest-template.json)** - Empty manifest template

## Git Workflow

When creating commits for this repository:

1. **Review recent commits** for commit message style:
   ```powershell
   git log --oneline -10
   ```

2. **Follow conventional commits:**
   - `feat:` - New features
   - `fix:` - Bug fixes
   - `docs:` - Documentation changes
   - `test:` - Test additions/changes
   - `refactor:` - Code refactoring
   - `chore:` - Maintenance tasks

3. **Run tests before committing:**
   ```powershell
   ./tests/test-runner.ps1
   ```

## SpecKit Integration

This skill is designed for projects using **GitHub SpecKit** (`.specify/` directories with template-driven workflows). Key integration points:

- **Constitution Updates:** When constitution template changes, the skill uses hash verification to detect actual content changes before notifying users:
  - **Hash Verification**: Compares normalized hashes of current and backup constitution files to eliminate false positives
  - **Informational Notifications** (ℹ️): Shown for clean updates with no conflicts - marked "OPTIONAL" for user review
  - **Urgent Notifications** (⚠️): Shown for conflicts requiring manual resolution - marked "REQUIRED" with red/yellow colors
  - **Fail-Safe Behavior**: If hash comparison fails or backup is missing, notification is shown (errs on side of caution)
  - **Structured Logging**: Verbose mode (`-Verbose`) shows detailed hash comparison for debugging
  - **Command**: User runs `/speckit.constitution <backup-path>` to merge changes
- **Official Commands:** Tracks 8 official SpecKit commands (speckit.analyze, speckit.checklist, etc.)
- **Custom Commands:** User-created commands in `.claude/commands/` are NEVER overwritten, even with `--force`
- **Template Source:** Fetches from GitHub SpecKit releases (not from npm)

## Troubleshooting

### GitHub API Issues

The skill fetches SpecKit templates from GitHub Releases API. Common issues:

**"Failed to connect to GitHub API"**
- **Cause**: Network connectivity issue or firewall blocking api.github.com
- **Solution**:
  - Check internet connection
  - Verify api.github.com is accessible: `Test-NetConnection api.github.com -Port 443`
  - Check corporate firewall/proxy settings
  - Use `-Verbose` flag to see detailed connection attempts

**"GitHub API rate limit exceeded"**
- **Cause**: Exceeded 60 requests/hour limit for unauthenticated API calls
- **Solution**:
  - Wait until rate limit resets (time shown in error message)
  - Error message shows exact reset time: "Resets at: {timestamp}"
  - Rate limits reset on the hour (e.g., if exceeded at 2:45pm, resets at 3:00pm)

**"GitHub API returned empty response"**
- **Cause**: GitHub API returned null or invalid JSON
- **Solution**:
  - Check GitHub Status: https://www.githubstatus.com/
  - Retry in a few minutes if GitHub is experiencing issues
  - Use `-Verbose` flag to see API endpoint and response details

**"GitHub resource not found"**
- **Cause**: Specified version doesn't exist in GitHub releases
- **Solution**:
  - Verify version format: `v0.0.72` (with 'v' prefix)
  - Check available releases: https://github.com/github/spec-kit/releases
  - Omit `-Version` parameter to automatically use latest release

**"Invalid version format in tag_name"**
- **Cause**: GitHub release tag doesn't match semantic versioning (v0.0.0 format)
- **Solution**:
  - Report to SpecKit maintainers if official release has invalid tag
  - Use explicit `-Version` parameter with valid version

### Diagnostic Commands

```powershell
# Test GitHub API connectivity manually
Import-Module .\scripts\modules\GitHubApiClient.psm1 -Force
$release = Get-LatestSpecKitRelease -Verbose
$release | ConvertTo-Json -Depth 3

# Check current rate limit status
$rateLimit = Test-GitHubApiRateLimit
Write-Host "Remaining requests: $($rateLimit.rate.remaining) / $($rateLimit.rate.limit)"

# Test with verbose logging
& .\scripts\update-orchestrator.ps1 -CheckOnly -Verbose

# Test specific version
& .\scripts\update-orchestrator.ps1 -CheckOnly -Version v0.0.72 -Verbose
```

### Common Error Codes

- **Exit Code 0**: Success
- **Exit Code 1**: General error
- **Exit Code 2**: Prerequisites not met (Git missing, not in SpecKit project, etc.)
- **Exit Code 3**: Network/API error (GitHub API unreachable, rate limited, etc.)
- **Exit Code 4**: Git error (uncommitted changes, merge conflicts, etc.)
- **Exit Code 5**: User cancelled operation
- **Exit Code 6**: Automatic rollback occurred due to update failure

### Getting Help

- **Verbose Output**: Always use `-Verbose` flag when troubleshooting
- **Error Logs**: Check PowerShell error stream and verbose output
- **GitHub Issues**: Report issues at https://github.com/NotMyself/claude-win11-speckit-update-skill/issues
- **Bug Reports**: See `docs/bugs/` directory for known issues and resolutions
