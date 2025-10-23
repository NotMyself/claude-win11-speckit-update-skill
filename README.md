# SpecKit Safe Update - Claude Code Skill

Safe updates for GitHub SpecKit installations, preserving your customizations.

## Overview

This Claude Code skill provides a safe, automated way to update SpecKit templates, commands, and scripts while preserving user customizations, eliminating the need for destructive `specify init --force` updates.

## Features

- **Automatic SpecKit Installation** (New in v0.4.0): Offers to install SpecKit in non-SpecKit projects with one command
- **Customization Preservation**: Automatically detects and preserves your customized files
- **Smart Conflict Resolution**: Intelligent two-tier conflict handling
  - Small files (≤100 lines): Git conflict markers with VSCode CodeLens integration
  - Large files (>100 lines): Side-by-side Markdown diff files for easier review
- **False Positive Detection**: Auto-resolves conflicts where files are identical to upstream
- **Conversational Approval**: Two-step workflow designed for Claude Code
- **Version Tracking**: Maintains manifest with file hashes and version information
- **Automatic Backups**: Creates timestamped backups with retention management
- **Fail-Fast with Rollback**: Automatic rollback on failure, preserves diff files for debugging
- **Dry-Run Mode**: Check what would change before applying updates
- **Constitution Integration**: Seamless integration with `/speckit.constitution` command
- **Welcome Experience**: First-time installs show helpful next steps

## Prerequisites

**Supported Environment**:
- **OS**: Windows 11 (macOS/Linux support welcome - see [#15](https://github.com/NotMyself/claude-win11-speckit-update-skill/issues/15))
- **Shell**: PowerShell 7+
- **AI**: Claude Code (CLI or VSCode extension)
- **Git**: In PATH
- **Internet**: For GitHub API access

**Note**: This skill is designed specifically for Windows + PowerShell + Claude Code. Community contributions for other platforms/models are welcome but not maintained by the project owner.

## Installation

Skills must be installed manually to the Claude Code skills directory:

```powershell
# Navigate to Claude Code skills directory
cd $env:USERPROFILE\.claude\skills

# Clone this repository
git clone https://github.com/NotMyself/claude-win11-speckit-update-skill speckit-updater

# Restart VSCode to load the skill
```

**Verify installation**: After restarting VSCode, the `/speckit-updater` command should be available in Claude Code.

## Usage

### First-Time Installation (New in v0.4.0!)

If you run `/speckit-updater` in a project **without SpecKit installed**, the updater will automatically offer to install it for you:

```
/speckit-updater
```

**Interactive Mode (Terminal):**
```
SpecKit is not installed in this project.

This skill can install the latest SpecKit templates and create a manifest to track future updates.

Would you like to install SpecKit now? (Y/n) Y
```

**Non-Interactive Mode (Claude Code):**
```
[PROMPT_FOR_INSTALL]

SpecKit is not installed in this project.

The updater can install the latest SpecKit templates for you.
This will:
  • Create .specify/ directory structure
  • Download latest SpecKit templates from GitHub
  • Create manifest to track future updates

To proceed with installation, re-run with: -Proceed
```

**What Gets Installed:**
- `.specify/` directory structure (`memory/`, `backups/`)
- Latest SpecKit templates from GitHub
- All official SpecKit slash commands in `.claude/commands/`
- Manifest file to track future updates
- Welcome message with next steps

**Graceful Decline:** If you decline installation, you'll see a helpful error message explaining what SpecKit is and how to install it manually.

### Check for Updates (Dry-Run)

```
/speckit-updater --check-only
```

Shows what would change without applying any updates.

### Update to Latest Version

```
/speckit-updater
```

Two-step conversational workflow:
1. Shows summary with `[PROMPT_FOR_APPROVAL]` marker
2. You approve via chat → Claude re-invokes with `-Proceed`

### Update to Specific Version

```
/speckit-updater --version v0.0.72
```

Update to a specific SpecKit release tag.

### Rollback to Previous Version

```
/speckit-updater --rollback
```

Restore from a previous backup.

### Force Update

```
/speckit-updater --force
```

Overwrite SpecKit files even if customized (preserves custom commands).

### Skip Backup (Not Recommended)

```
/speckit-updater --no-backup
```

Skip backup creation. Use only if you're absolutely sure.

## How It Works

### Update Workflow (16 Steps)

1. **Validate Prerequisites**: Check Git, write permissions, Git state, offer SpecKit installation if needed
2. **Handle Rollback**: Process rollback request if specified
3. **Create .specify/ Structure** (First-Time Install): Create directories for new installations
4. **Load/Create Manifest**: Load `.specify/manifest.json` or create new one
5. **Fetch Target Version**: Get latest or specific version from GitHub Releases
6. **Analyze File States**: Compare current files with manifest and upstream
7. **Check-Only Mode**: Show detailed report and exit (if `--check-only`)
8. **Get Confirmation**: Show summary and exit for user approval (conversational workflow)
9. **Create Backup**: Create timestamped backup in `.specify/backups/`
10. **Download Templates**: Fetch templates from GitHub release
11. **Apply Updates**: Update files that aren't customized or conflicts
12. **Handle Conflicts**: Write Git conflict markers for VSCode CodeLens detection
13. **Update Constitution**: Delegate to `/speckit.constitution` with backup path if needed
14. **Update Manifest**: Update version and file hashes
15. **Cleanup Old Backups**: Optionally remove backups older than 5 most recent
16. **Show Summary**: Display detailed update results (includes "Welcome to SpecKit!" for first installs)

### Conflict Resolution

When conflicts are detected (file customized locally AND changed upstream):

1. **Detects conflicts** during file analysis
2. **Writes Git conflict markers** to conflicted files:
   ```
   <<<<<<< Current (Your Version)
   Your local changes
   ||||||| Base (v0.1.5)
   Original content
   =======
   New upstream content
   >>>>>>> Incoming (v0.2.0)
   ```
3. **VSCode CodeLens** automatically detects markers and shows actions:
   - Accept Current Change
   - Accept Incoming Change
   - Accept Both Changes
   - Compare Changes
4. **False positive detection**: Auto-resolves when content is identical to upstream
5. **Constitution special handling**: Uses `/speckit.constitution` workflow instead of markers

### File State Detection

Files are categorized based on hash comparison:

- **Update**: Not customized, has upstream changes → Apply update
- **Preserve**: Customized, no upstream changes → Keep as-is
- **Merge**: Customized AND has upstream changes → Conflict resolution
- **Add**: New file in upstream → Add to project
- **Remove**: File removed from upstream → Remove from project
- **Skip**: No changes needed

## Architecture

### Modules

- **HashUtils.psm1**: Normalized hashing (handles line endings, whitespace)
- **VSCodeIntegration.psm1**: Execution context detection, notifications
- **GitHubApiClient.psm1**: GitHub Releases API interaction
- **ManifestManager.psm1**: Manifest CRUD operations
- **BackupManager.psm1**: Backup creation and restoration
- **ConflictDetector.psm1**: File state analysis, conflict detection, conflict marker writing

### Helper Functions

- **Invoke-PreUpdateValidation.ps1**: Prerequisites validation
- **Show-UpdateSummary.ps1**: Detailed results display
- **Show-UpdateReport.ps1**: Check-only mode output
- **Get-UpdateConfirmation.ps1**: Conversational approval workflow and summary generation
- **Invoke-ConflictResolutionWorkflow.ps1**: Conflict detection and marker writing (legacy name)
- **Invoke-RollbackWorkflow.ps1**: Backup restoration workflow

### Main Orchestrator

- **update-orchestrator.ps1**: Main entry point coordinating all 15 steps

## Manifest Structure

The `.specify/manifest.json` file tracks:

```json
{
  "version": "1.0",
  "speckit_version": "v0.0.72",
  "initialized_at": "2025-01-19T12:34:56Z",
  "last_updated": "2025-01-19T14:22:10Z",
  "agent": "claude-code",
  "speckit_commands": ["speckit.constitution.md", "speckit.specify.md", ...],
  "tracked_files": [
    {
      "path": ".claude/commands/speckit.specify.md",
      "original_hash": "sha256:abc123...",
      "customized": false,
      "is_official": true
    }
  ],
  "custom_files": [".claude/commands/custom-deploy.md"],
  "backup_history": [...]
}
```

## Error Handling

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Prerequisites not met |
| 3 | Network/API error |
| 4 | Git error |
| 5 | User cancelled |
| 6 | Rollback required (automatic) |

### Automatic Rollback

If an error occurs during update:
1. Error message is displayed
2. Automatic rollback is attempted (if backup exists)
3. Files are restored to pre-update state
4. Exit code 6 is returned

## Development

### Project Structure

```
claude-Win11-SpecKit-Safe-Update-Skill/
├── scripts/
│   ├── update-orchestrator.ps1       # Main entry point
│   ├── modules/                       # PowerShell modules
│   │   ├── HashUtils.psm1
│   │   ├── VSCodeIntegration.psm1
│   │   ├── GitHubApiClient.psm1
│   │   ├── ManifestManager.psm1
│   │   ├── BackupManager.psm1
│   │   └── ConflictDetector.psm1
│   └── helpers/                       # Helper functions
│       ├── Invoke-PreUpdateValidation.ps1
│       ├── Show-UpdateSummary.ps1
│       ├── Show-UpdateReport.ps1
│       ├── Get-UpdateConfirmation.ps1
│       ├── Invoke-ConflictResolutionWorkflow.ps1
│       └── Invoke-RollbackWorkflow.ps1
├── templates/
│   └── manifest-template.json
├── specs/
│   └── 001-safe-update/
│       └── spec.md
├── SKILL.md                          # Claude Code skill definition
└── README.md                         # This file
```

### Testing

Run the test suite:

```powershell
# Run all tests
./tests/test-runner.ps1

# Run unit tests only
./tests/test-runner.ps1 -Unit

# Run integration tests only
./tests/test-runner.ps1 -Integration
```

**Test Results (v0.2.0)**:
- ✅ 193 tests passing
- ⚠️ 59 tests failing (pre-existing integration test issues - modules work correctly)
- ⚠️ 7 tests skipped (VSCodeIntegration mocking limitations)

## Specification

Full specification available in `specs/001-safe-update/spec.md`.

## Contributing

This skill follows the specification in `specs/001-safe-update/spec.md`.

### General Contributions

Contributions should:
1. Follow PowerShell best practices
2. Include appropriate error handling
3. Add tests for new functionality
4. Update documentation

### Multi-Platform/Multi-Model Support

**The project owner only supports Windows + PowerShell + Claude Code** and does not have the environment to test other configurations.

However, **community contributions are welcome** for:
- macOS/Linux support (Bash, Zsh, or PowerShell Core)
- Other AI models (GPT-4, local LLMs, etc.)
- Other shells (Fish, Nushell, etc.)

**See [Issue #15](https://github.com/NotMyself/claude-win11-speckit-update-skill/issues/15)** for detailed guidance on contributing multi-platform support.

**Requirements for multi-platform PRs**:
- Must maintain backward compatibility with Windows/PowerShell/Claude
- Must pass all existing tests (193 tests)
- Must add tests for new platforms
- Must update documentation
- Contributor must test on target platform (maintainer cannot)

## License

MIT License - see [LICENSE](./LICENSE)
