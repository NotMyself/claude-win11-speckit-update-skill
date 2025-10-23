# GitHub Actions Workflows

This directory contains automated workflows for the SpecKit Safe Update Skill.

## Workflows

### update-fingerprints.yml

**Purpose**: Automatically maintains the SpecKit fingerprint database by detecting new releases and updating the database.

**Triggers**:
- **Schedule**: Runs daily at 2 AM UTC
- **Manual**: Can be triggered via workflow_dispatch with optional force update

**What it does**:
1. Checks current fingerprint database version
2. Queries GitHub API for latest SpecKit release
3. If new release found:
   - Regenerates fingerprint database using `scripts/generate-fingerprints.ps1`
   - Verifies changes
   - Creates a pull request with updated database
4. If no new release: Exits gracefully

**Outputs**:
- Pull request with updated `data/speckit-fingerprints.json`
- PR includes version stats and size information
- Auto-labeled with `automated`, `database-update`, `relates-to-#25`

**Permissions Required**:
- `contents: write` - To commit database changes
- `pull-requests: write` - To create PRs

**Environment Variables**:
- `GITHUB_TOKEN` - Provided automatically by GitHub Actions
  - Used to query SpecKit releases API
  - Used to create pull requests

**Error Handling**:
- Validates database file exists before comparing versions
- Checks for changes before creating PR (avoids empty PRs)
- Verifies script exit codes
- Provides detailed summary at end

**Manual Trigger**:
```bash
# Via GitHub CLI
gh workflow run update-fingerprints.yml

# Force update even if no new releases
gh workflow run update-fingerprints.yml -f force_update=true
```

**Pull Request Example**:
```
Title: chore: Update fingerprint database to v0.0.80

Body:
## Automated Fingerprint Database Update

This PR updates the SpecKit fingerprint database to include the latest releases.

### Changes
- **Latest Version**: v0.0.80
- **Total Versions**: 80
- **Database Size**: 72.5 KB

### Testing
- ✅ Database regenerated successfully
- ✅ File size within 500 KB limit
- ✅ Schema version validated
```

**Monitoring**:
- Check workflow runs: https://github.com/NotMyself/claude-win11-speckit-safe-update-skill/actions
- Review open PRs: Filter by `automated` label
- Failed runs will show in Actions tab with detailed logs

**Troubleshooting**:

| Issue | Cause | Solution |
|-------|-------|----------|
| Workflow fails at "Check for new releases" | GitHub API rate limit or network issue | Wait for rate limit reset, or trigger manually later |
| Workflow fails at "Generate updated fingerprints" | SpecKit release archive not available | Check SpecKit releases, may need to skip older versions |
| No PR created despite new release | Database unchanged (already up to date) | Normal behavior, no action needed |
| PR created but database size >500 KB | Too many versions tracked | Review and potentially archive older versions |

**Related Files**:
- Generator script: `scripts/generate-fingerprints.ps1`
- Database: `data/speckit-fingerprints.json`
- Feature PRD: `docs/PRDs/004-Smart-Merge-Frictionless-Onboarding.md`
- GitHub Issue: #25

## Future Workflows

Potential workflows to add:

- **test-modules.yml**: Run Pester tests on PR creation
- **lint-powershell.yml**: PSScriptAnalyzer linting
- **release.yml**: Automated version tagging and changelog generation
