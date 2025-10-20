# Contributing to SpecKit Safe Update Skill

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Development Setup

### Prerequisites

- PowerShell 7+
- Git
- VSCode (recommended)
- Pester 5.x testing framework

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```powershell
   git clone https://github.com/YOUR_USERNAME/claude-win11-speckit-update-skill
   cd claude-win11-speckit-update-skill
   ```

3. Install Pester (if not already installed):
   ```powershell
   Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
   ```

## Project Structure

```
claude-Win11-SpecKit-Safe-Update-Skill/
├── scripts/
│   ├── update-orchestrator.ps1       # Main entry point
│   ├── modules/                       # PowerShell modules (6 files)
│   └── helpers/                       # Helper functions (7 files)
├── tests/
│   ├── unit/                          # Unit tests
│   ├── integration/                   # Integration tests
│   └── fixtures/                      # Test data
├── specs/                             # Specifications
└── templates/                         # Template files
```

## Development Workflow

### 1. Create a Branch

```powershell
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

### 2. Make Changes

Follow these guidelines:

**PowerShell Code Style:**
- Use PascalCase for function names (`Get-FileState`)
- Use camelCase for variables (`$fileName`)
- Use proper cmdlet binding with `[CmdletBinding()]`
- Include comment-based help for all exported functions
- Use try-catch-finally for error handling
- Add verbose logging with `Write-Verbose`

**Example:**
```powershell
function Get-Example {
    <#
    .SYNOPSIS
        Short description
    .DESCRIPTION
        Longer description
    .PARAMETER Name
        Parameter description
    .EXAMPLE
        Get-Example -Name "test"
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

### 3. Write Tests

All new functionality must include tests:

**Unit Tests:**
- Create in `tests/unit/`
- Name pattern: `ModuleName.Tests.ps1`
- Use Pester 5.x syntax (`Describe`, `Context`, `It`)
- Mock external dependencies
- Test both success and error cases

**Example:**
```powershell
Describe "Get-Example" {
    Context "When called with valid input" {
        It "Returns expected result" {
            $result = Get-Example -Name "test"
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "When called with invalid input" {
        It "Throws an error" {
            { Get-Example -Name "" } | Should -Throw
        }
    }
}
```

### 4. Run Tests

```powershell
# Run all tests
./tests/test-runner.ps1

# Run unit tests only
./tests/test-runner.ps1 -Unit

# Run integration tests only
./tests/test-runner.ps1 -Integration

# Run with code coverage
./tests/test-runner.ps1 -Coverage
```

### 5. Update Documentation

- Update README.md if adding user-facing features
- Update CHANGELOG.md under [Unreleased] section
- Update SKILL.md if changing command behavior
- Add inline comments for complex logic

### 6. Commit Changes

```powershell
git add .
git commit -m "feat: add new feature"
# or
git commit -m "fix: resolve issue with X"
```

**Commit Message Format:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `test:` Test additions/changes
- `refactor:` Code refactoring
- `style:` Formatting changes
- `chore:` Maintenance tasks

### 7. Push and Create Pull Request

```powershell
git push origin feature/your-feature-name
```

Then create a pull request on GitHub.

## Pull Request Guidelines

### Before Submitting

- [ ] All tests pass locally
- [ ] Code follows PowerShell style guidelines
- [ ] New functionality includes tests
- [ ] Documentation is updated
- [ ] No merge conflicts with main branch
- [ ] Commit messages are clear and descriptive

#### PowerShell-Specific Checks

- [ ] **Module vs. Helper Pattern**:
  - [ ] New helper scripts (`.ps1` in `scripts/helpers/`) do NOT use `Export-ModuleMember`
  - [ ] New modules (`.psm1` in `scripts/modules/`) DO use `Export-ModuleMember`
  - [ ] Use `templates/helper-template.ps1` as starting point for helpers
  - [ ] Use `templates/module-template.psm1` as starting point for modules
- [ ] **Error Handling**:
  - [ ] Module import logic in orchestrator uses proper error handling (no blanket suppression)
  - [ ] No `-ErrorAction SilentlyContinue` on `Import-Module` calls (masks real errors)
  - [ ] No `2>$null` redirection on helper dot-sourcing (masks real errors)
  - [ ] Try-catch blocks with stack trace logging for real errors
- [ ] **Code Standards**:
  - [ ] All new PowerShell functions have comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
  - [ ] Verbose logging added with `Write-Verbose` for debugging
  - [ ] Error messages are clear and actionable

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
Describe how you tested your changes

## Checklist
- [ ] Tests added/updated
- [ ] All tests passing (`./tests/test-runner.ps1`)
- [ ] Lint check passes (no `Import-Module` in `.psm1` files - see constitution)
- [ ] Code review: Verified no nested module imports
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
```

## Code Review Process

1. Automated tests run via GitHub Actions
2. Maintainer reviews code
3. Address any feedback
4. Once approved, maintainer merges PR

## Reporting Issues

### Bug Reports

Include:
- PowerShell version (`$PSVersionTable.PSVersion`)
- Operating system
- Steps to reproduce
- Expected behavior
- Actual behavior
- Error messages (if any)
- Relevant logs

### Feature Requests

Include:
- Clear description of the feature
- Use case(s)
- Why it would be useful
- Potential implementation approach (optional)

## Areas to Contribute

### High Priority
- Additional test coverage
- Bug fixes
- Documentation improvements
- Performance optimizations

### Medium Priority
- New helper functions
- Enhanced error messages
- Better user prompts
- Additional validation checks

### Future Enhancements
- GitHub token authentication support
- Partial updates (specific files/directories)
- Team version locking
- Migration from older manifest formats

## Questions?

- Open an issue for discussion
- Check existing issues for related topics
- Review the specification in `specs/001-safe-update/`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
