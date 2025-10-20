<!--
Sync Impact Report:
- Version change: NONE → 1.0.0
- Modified principles: N/A (initial version)
- Added sections: All core principles (I-V), PowerShell Standards, Testing Requirements, Governance
- Removed sections: N/A
- Templates requiring updates:
  ✅ plan-template.md - reviewed, constitution check section aligns
  ✅ spec-template.md - reviewed, no conflicts with principles
  ✅ tasks-template.md - reviewed, testing gates align with principles
- Follow-up TODOs: None
-->

# SpecKit Safe Update Skill Constitution

## Core Principles

### I. Modular Architecture (NON-NEGOTIABLE)

All business logic MUST be implemented in PowerShell modules (`.psm1` files), not in
helper functions or the orchestrator. Modules MUST be:

- **Self-contained**: Each module has a single, clear responsibility
- **Stateless**: No module-level state; all state passed via parameters
- **Independently testable**: Can be tested in isolation with Pester
- **Reusable**: Functions can be called from any context

**Rationale**: This architecture enables unit testing, code reuse across features,
and clear separation of concerns. Helper functions are thin orchestration wrappers
that call module functions and handle user interaction only.

**Module Responsibilities**:
- `HashUtils.psm1` - File hashing with normalization
- `VSCodeIntegration.psm1` - VSCode context detection and editor integration
- `GitHubApiClient.psm1` - GitHub Releases API interaction
- `ManifestManager.psm1` - Manifest CRUD operations
- `BackupManager.psm1` - Backup/restore operations
- `ConflictDetector.psm1` - File state analysis

### II. Fail-Fast with Rollback (NON-NEGOTIABLE)

The update process MUST be transactional. Any error during critical steps (backup
creation through manifest update) MUST trigger automatic rollback.

**Requirements**:
- Backup created BEFORE any file modifications
- All file operations in try-catch blocks with rollback handler
- Exit code 6 on rollback
- Clear error messages indicating rollback occurred
- Manifest reverted to pre-update state

**Rationale**: Users trust this tool with their customizations. Any failure that
could corrupt their project state is unacceptable. Rollback ensures users can
always return to a working state.

### III. Customization Detection via Normalized Hashing

File customization detection MUST use normalized hashing to avoid false positives
from line ending differences, trailing whitespace, or BOM variations.

**Normalization Rules**:
- Convert CRLF → LF
- Trim trailing whitespace per line
- Remove BOM if present (0xFEFF)
- Compute SHA-256 hash
- Format as "sha256:HEXSTRING"

**Safe Default**: If no manifest exists, assume ALL files are customized. This
prevents accidental data loss on first run.

**Rationale**: Editors (VSCode, Vim, etc.) may change line endings or whitespace
without user intent. These formatting changes should not be treated as meaningful
customizations that trigger conflict resolution.

### IV. User Confirmation Required

The update process MUST obtain explicit user confirmation before applying changes,
except in `--check-only` mode.

**Requirements**:
- Show detailed change preview (files to add/update/merge/remove)
- Use VSCode Quick Pick UI when in Claude Code context
- Provide clear escape option (user can cancel with exit code 5)
- No destructive operations before confirmation

**Exception**: `--force` mode still requires confirmation but overrides
customization preservation (except custom commands).

**Rationale**: Respect user agency. Even with rollback capability, users should
explicitly approve changes to their project.

### V. Testing Discipline

All modules MUST have corresponding Pester unit tests. Integration tests MUST cover
the end-to-end orchestration workflow.

**Test Requirements**:
- Unit tests in `tests/unit/[ModuleName].Tests.ps1`
- Integration tests in `tests/integration/UpdateOrchestrator.Tests.ps1`
- Mock external dependencies (GitHub API, file system where appropriate)
- Test both success and error paths
- Test edge cases (empty manifests, corrupted data, network failures)

**Known Limitations**: VSCodeIntegration module has mocking limitations (acceptable).
Pester 5.x module scoping issues cause false failures but modules work correctly.

**Rationale**: PowerShell scripts are error-prone without tests. Tests document
expected behavior and prevent regressions during refactoring.

## PowerShell Standards

### Code Style

- **Function Names**: PascalCase with approved verbs (`Get-FileState`, `Invoke-Validation`)
- **Variables**: camelCase (`$fileName`, `$manifestPath`)
- **Parameters**: PascalCase in param blocks with type annotations
- **Error Handling**: Use `try-catch-finally`; set `$ErrorActionPreference = 'Stop'` in scripts
- **Comment-Based Help**: All exported functions MUST have `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- **Verbose Logging**: Use `Write-Verbose` for debugging info; never `Write-Host` for logic

### Module Export Rules

Each module MUST:
- Use `[CmdletBinding()]` on exported functions
- Explicitly export functions with `Export-ModuleMember -Function`
- Not rely on implicit exports
- Include module-level documentation comment

### Module Import Rules (Added: 2025-10-20)

**Rule**: Modules MUST NOT import other modules. All module imports MUST be managed by the orchestrator script (`scripts/update-orchestrator.ps1`).

**Rationale**: Nested `Import-Module` statements create PowerShell scope isolation where imported functions exist in the module's internal scope but are not accessible to the calling script. This causes "command not recognized" errors despite successful imports.

When a module (e.g., `ManifestManager.psm1`) contains `Import-Module HashUtils.psm1`, PowerShell creates this scope hierarchy:

```
Global Scope
└── Orchestrator Script Scope
    └── ManifestManager Module Scope
        └── HashUtils Module Scope (nested import)
            └── Get-NormalizedHash function
```

When the orchestrator calls `Get-NormalizedHash`, PowerShell searches the orchestrator scope and parent scopes but does NOT search child module scopes, resulting in "command not recognized" errors.

**Enforcement**:
- Automated lint check in `tests/test-runner.ps1` scans all `.psm1` files before test execution
- Lint check fails with detailed error messages if `Import-Module` statements detected
- Integration tests in `tests/integration/ModuleDependencies.Tests.ps1` verify cross-module function calls work

**Correct Pattern** (orchestrator-managed imports in dependency order):
```powershell
# scripts/update-orchestrator.ps1

# TIER 0: Foundation modules (no dependencies)
Import-Module (Join-Path $modulesPath "HashUtils.psm1") -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $modulesPath "GitHubApiClient.psm1") -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $modulesPath "VSCodeIntegration.psm1") -Force -WarningAction SilentlyContinue

# TIER 1: Modules depending on Tier 0
Import-Module (Join-Path $modulesPath "ManifestManager.psm1") -Force -WarningAction SilentlyContinue

# TIER 2: Modules depending on Tier 1
Import-Module (Join-Path $modulesPath "BackupManager.psm1") -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $modulesPath "ConflictDetector.psm1") -Force -WarningAction SilentlyContinue
```

**Incorrect Pattern** (nested imports in module files):
```powershell
# scripts/modules/ManifestManager.psm1 - ❌ INCORRECT

# This creates scope isolation!
Import-Module (Join-Path $PSScriptRoot "HashUtils.psm1") -Force  # ❌ DO NOT DO THIS
```

**Exception**: None. This rule is absolute.

**Module Dependencies Documentation**: Each module file should document its dependencies in a comment:
```powershell
# Dependencies: HashUtils, GitHubApiClient
# All module imports are managed by the orchestrator script (update-orchestrator.ps1)
# Do NOT add Import-Module statements here - they create scope isolation issues
```

### Error Messages

Error messages MUST:
- Be actionable (tell user what to do)
- Include context (file path, operation attempted)
- Use proper error streams (`Write-Error` for errors, `Write-Warning` for warnings)
- Surface inner exceptions where helpful

## Testing Requirements

### Test Organization

```
tests/
├── unit/                    # Isolated module tests
│   ├── HashUtils.Tests.ps1
│   ├── ManifestManager.Tests.ps1
│   └── [others]
├── integration/             # End-to-end workflow tests
│   └── UpdateOrchestrator.Tests.ps1
└── fixtures/                # Test data
    ├── sample-manifests/
    └── mock-responses/
```

### Test Execution

- `./tests/test-runner.ps1` - Run all tests
- `./tests/test-runner.ps1 -Unit` - Run only unit tests
- `./tests/test-runner.ps1 -Integration` - Run only integration tests
- `./tests/test-runner.ps1 -Coverage` - Generate code coverage report

### Test Coverage Goals

- Module functions: 80% coverage minimum
- Error paths: All critical error handlers tested
- Edge cases: Empty inputs, null values, corrupted data

## Git & Version Control

### Commit Message Format

Use conventional commits:
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `test:` - Test additions/changes
- `refactor:` - Code refactoring without behavior change
- `chore:` - Maintenance tasks

### Pre-Commit Checklist

Before committing:
1. Run `./tests/test-runner.ps1` and verify all tests pass
2. Review changes to ensure no secrets or test data included
3. Update `CHANGELOG.md` under `[Unreleased]` section
4. Update relevant documentation (README, SKILL.md, CONTRIBUTING.md)

### Branch Strategy

- `main` - Production-ready code
- Feature branches - `feature/description` or `fix/description`
- No direct commits to `main` without PR review

## Distribution & Installation

This skill is distributed as a **Git repository**, NOT via npm or PowerShell Gallery.

**Installation Method**:
```powershell
cd $env:USERPROFILE\.claude\skills
git clone https://github.com/NotMyself/claude-win11-speckit-update-skill speckit-updater
```

Claude Code automatically discovers `SKILL.md` and makes `/speckit-update` available.

**Rationale**: Skills are user-installed by design. Git distribution enables version
control, easy updates via `git pull`, and transparency (users can inspect code).

## SpecKit Integration

This skill integrates with GitHub SpecKit projects (`.specify/` directories).

### Official SpecKit Commands

The following 8 commands are considered official and tracked in the manifest:
- `speckit.constitution.md`
- `speckit.specify.md`
- `speckit.clarify.md`
- `speckit.plan.md`
- `speckit.tasks.md`
- `speckit.implement.md`
- `speckit.analyze.md`
- `speckit.checklist.md`

### Custom Command Preservation

User-created commands in `.claude/commands/` are NEVER overwritten, even with
`--force`. The skill detects custom commands by checking if they appear in the
`speckit_commands` list in the manifest.

### Constitution Update Integration

When the constitution template (`.specify/memory/constitution.md`) has upstream
changes, the skill MUST:
1. Detect the change via hash comparison
2. Mark as conflict (file is typically customized)
3. Notify user to run `/speckit.constitution` after update completes

The skill does NOT automatically update constitution content; that is the
responsibility of `/speckit.constitution` command.

## Governance

### Amendment Procedure

Constitution amendments require:
1. Propose change via GitHub issue with rationale
2. Discussion and approval from maintainer
3. Update this constitution document with version increment
4. Update dependent templates/documentation
5. Add migration notes to CHANGELOG.md if breaking change

### Version Increment Rules

- **MAJOR** (X.0.0): Backward incompatible principle changes, removals, or redefinitions
- **MINOR** (x.Y.0): New principle added or materially expanded guidance
- **PATCH** (x.y.Z): Clarifications, wording, typo fixes, non-semantic refinements

### Compliance Validation

All pull requests MUST:
- Pass `./tests/test-runner.ps1` with no failures
- Follow PowerShell style guidelines
- Include comment-based help for new functions
- Update tests for modified modules
- Verify no principles violated

Reviewers MUST check:
- Module architecture preserved (no business logic in helpers)
- Error handling includes rollback where appropriate
- User confirmation obtained before destructive operations
- Customization detection uses normalized hashing

### Constitution Supersedes

When conflict arises between this constitution and other documentation:
1. This constitution takes precedence
2. Update conflicting documentation to align
3. If constitution is incorrect, amend constitution first, then update docs

### Development Guidance

For runtime development guidance, consult:
- [CLAUDE.md](../../CLAUDE.md) - Repository architecture and common commands
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Development workflow and PR guidelines
- [specs/001-safe-update/spec.md](../../specs/001-safe-update/spec.md) - Full specification

**Version**: 1.1.0 | **Ratified**: 2025-10-20 | **Last Amended**: 2025-10-20 | **Amendment**: Added Module Import Rules (prohibits nested imports in modules)
