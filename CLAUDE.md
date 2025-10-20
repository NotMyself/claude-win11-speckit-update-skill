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

- **Constitution Updates:** When constitution template changes, skill notifies user to run `/speckit.constitution`
- **Official Commands:** Tracks 8 official SpecKit commands (speckit.analyze, speckit.checklist, etc.)
- **Custom Commands:** User-created commands in `.claude/commands/` are NEVER overwritten, even with `--force`
- **Template Source:** Fetches from GitHub SpecKit releases (not from npm)
