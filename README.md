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

## Using GitHub Tokens

The updater fetches SpecKit templates from the GitHub Releases API. By default, requests are **unauthenticated** with a rate limit of **60 requests/hour** per IP address. This is usually sufficient for normal use.

### When Do You Need a Token?

You should set up a GitHub Personal Access Token if you:

- Develop or test the updater frequently
- Work on a team sharing the same office network/IP address
- Run updates in CI/CD pipelines
- Hit rate limit errors: `GitHub API rate limit exceeded`

**With a token**, your rate limit increases to **5,000 requests/hour** per user.

### Quick Setup

**1. Create a GitHub Personal Access Token:**

Go to [github.com/settings/tokens](https://github.com/settings/tokens) and click "Generate new token (classic)".

- **Note**: `SpecKit Updater`
- **Expiration**: 90 days (recommended)
- **Scopes**: Leave all unchecked ✅ (no scopes needed for public repos)

Copy the token (format: `ghp_...`) immediately - it's shown only once!

**2. Set the Environment Variable:**

Choose one method:

**PowerShell Session** (temporary - testing):
```powershell
$env:GITHUB_PAT = "ghp_YOUR_TOKEN_HERE"
```

**PowerShell Profile** (persistent - daily use):
```powershell
# Open profile in editor
notepad $PROFILE

# Add this line and save:
$env:GITHUB_PAT = "ghp_YOUR_TOKEN_HERE"

# Reload profile
. $PROFILE
```

**Windows System Variable** (global - all applications):
```powershell
# Via GUI: Win+R → sysdm.cpl → Environment Variables → New
# Variable name: GITHUB_PAT
# Variable value: ghp_YOUR_TOKEN_HERE

# Or via PowerShell:
[System.Environment]::SetEnvironmentVariable(
    "GITHUB_PAT",
    "ghp_YOUR_TOKEN_HERE",
    [System.EnvironmentVariableTarget]::User
)
# Restart PowerShell after this
```

**3. Verify It Works:**

```powershell
/speckit-updater --check-only -Verbose
# Should show: "Using authenticated request (rate limit: 5,000 req/hour)"
```

### Team Collaboration

Each team member should create their own Personal Access Token. This provides:

- **Isolated rate limits**: Each person gets 5,000 req/hour independently
- **Better security**: Tokens can be revoked individually
- **Audit trail**: GitHub tracks API usage per token

**Shared IP address scenario**: If your team shares an office network, you're all sharing the same 60 req/hour limit without tokens. Individual tokens solve this completely.

### CI/CD Integration

#### GitHub Actions (Zero Configuration)

GitHub automatically provides `GITHUB_PAT` - no setup needed:

```yaml
name: Check SpecKit Updates

on: [push, pull_request]

jobs:
  check-updates:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3

      - name: Check SpecKit Updates
        env:
          GITHUB_PAT: ${{ secrets.GITHUB_PAT }}  # Automatic
        run: |
          pwsh -Command "& '.\.claude\skills\speckit-updater\scripts\update-orchestrator.ps1' -CheckOnly"
```

#### Azure Pipelines

Add `GITHUB_PAT` as a secret variable in your pipeline settings, then:

```yaml
trigger:
  - main

pool:
  vmImage: 'windows-latest'

steps:
- task: PowerShell@2
  displayName: 'Check SpecKit Updates'
  env:
    GITHUB_PAT: $(GITHUB_PAT)  # From pipeline variables
  inputs:
    targetType: 'inline'
    script: |
      & '.\.claude\skills\speckit-updater\scripts\update-orchestrator.ps1' -CheckOnly
```

#### Jenkins

Add token via Credentials Plugin (Secret text with ID `github-token`), then:

```groovy
pipeline {
    agent any

    environment {
        GITHUB_PAT = credentials('github-token')
    }

    stages {
        stage('Check Updates') {
            steps {
                pwsh '''
                    & '.\.claude\skills\speckit-updater\scripts\update-orchestrator.ps1' -CheckOnly
                '''
            }
        }
    }
}
```

#### CircleCI

Add `GITHUB_PAT` as an environment variable in project settings, then:

```yaml
version: 2.1

jobs:
  check-updates:
    docker:
      - image: mcr.microsoft.com/powershell:latest
    steps:
      - checkout
      - run:
          name: Check SpecKit Updates
          command: |
            pwsh -Command "& '.\.claude\skills\speckit-updater\scripts\update-orchestrator.ps1' -CheckOnly"
          # GITHUB_PAT automatically available from environment
```

### Security Best Practices

**✅ DO:**
- Use tokens with **no scopes** (reading public repos doesn't require permissions)
- Set **expiration dates** (90 days recommended)
- Store tokens in **password managers**
- Create **separate tokens** for different purposes (dev vs CI/CD)
- **Revoke immediately** if compromised

**❌ DON'T:**
- Commit tokens to Git repositories
- Share tokens between team members
- Use tokens with unnecessary scopes
- Store in plain text files (except PowerShell profile with proper permissions)
- Keep tokens indefinitely without expiration

**Token Exposure Prevention**: The updater NEVER logs token values. Security check:
```powershell
# Verify token not exposed (should return False)
$output = /speckit-updater --check-only -Verbose 4>&1 | Out-String
$output -match "ghp_"
```

### Troubleshooting

**"GitHub API rate limit exceeded"**
- **Without token**: Wait until reset time (shown in error) or set up token
- **With token**: You've exceeded 5,000 requests/hour - wait until reset

**"401 Unauthorized"**
- Token is invalid, expired, or revoked
- Verify at [github.com/settings/tokens](https://github.com/settings/tokens)
- Create new token or remove `GITHUB_PAT` to use unauthenticated mode

**Token not working**
```powershell
# Check token is set correctly
$env:GITHUB_PAT
# Should output your token (ghp_...)

# Check token format (should be True)
$env:GITHUB_PAT -match "^ghp_"

# Try setting in current session
$env:GITHUB_PAT = "ghp_YOUR_TOKEN_HERE"
```

For detailed setup instructions, see [specs/012-github-token-support/quickstart.md](specs/012-github-token-support/quickstart.md).

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
Claude will ask naturally: "SpecKit is not currently installed in this project. Would you like me to install it?"

Simply reply "yes" or "install it" and Claude will handle the rest automatically.

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

### Customization Detection

The updater automatically detects which files you've customized by comparing file hashes:

- **Customized files** are preserved and never overwritten
- **Unchanged files** are safely updated to the latest version
- **Your custom commands** are always protected, even with `--force`

### Smart Update Process

When you run `/speckit-updater`:

1. **Safety First**: Creates a timestamped backup before making any changes
2. **Intelligent Analysis**: Compares your files with the latest SpecKit templates
3. **Conflict Detection**: Identifies files that need your attention
4. **Conversational Approval**: Shows you exactly what will change and waits for your approval
5. **Safe Application**: Updates only what's safe, preserving your customizations
6. **Automatic Rollback**: If anything goes wrong, automatically restores from backup

### Handling Conflicts

When a file has been customized locally **and** changed in the upstream template, you'll see conflict markers:

```markdown
<<<<<<< Current (Your Version)
Your local changes
||||||| Base (v0.1.5)
Original content
=======
New upstream content
>>>>>>> Incoming (v0.2.0)
```

**VSCode automatically detects these markers** and shows you options:
- Accept Current Change (keep yours)
- Accept Incoming Change (use upstream)
- Accept Both Changes (merge manually)
- Compare Changes (side-by-side view)

**Large files** (>100 lines) get special treatment with side-by-side Markdown diff files for easier review.

### Backup & Recovery

- **Automatic backups** created before every update in `.specify/backups/`
- **Timestamped folders** make it easy to find the right backup
- **Quick rollback** with `/speckit-updater --rollback`
- **Automatic cleanup** keeps your 5 most recent backups

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

## License

MIT License - see [LICENSE](./LICENSE)
