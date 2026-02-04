---
name: Submit PR
description: This skill should be used when the user asks to "submit a PR", "create a pull request", "open a PR", "push my changes as PR", or wants help with PR workflow including branch management and commit migration.
invokable: true
version: 1.0.0
---

# Submit PR Skill

This skill guides users through submitting pull requests with intelligent branch management, automatic PR generation, and proper labeling.

## Overview

The submit-pr skill handles the complete PR workflow:
- Detects if you're on main/master with unpushed commits
- Helps migrate commits to a feature branch
- Generates branch names from commit messages
- Creates PR title and description automatically
- Submits PR via GitHub CLI
- Adds the "codeblend" label to track AI-assisted PRs

## Pre-flight Checks

Before starting the PR workflow, verify the GitHub CLI is available and authenticated.

### Check gh CLI Installation

Run: `command -v gh`

If gh is not installed, attempt to install based on the platform:
- **macOS**: `brew install gh`
- **Debian/Ubuntu**: `sudo apt install gh`
- **Fedora**: `sudo dnf install gh`
- **Windows**: `winget install GitHub.cli`

### Check gh Authentication

Run: `gh auth status`

If not authenticated, inform the user:
> Please run `gh auth login` to authenticate with GitHub before continuing.

## Workflow Steps

### Step 1: Detect Current Branch

Use the detect-branch script or run these commands:

```bash
# Get current branch name
git branch --show-current

# Check if on main/master
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    echo "On default branch"
fi

# Check for unpushed commits
git log origin/$BRANCH..$BRANCH --oneline
```

### Step 2: Branch Decision Logic

**If on main/master with unpushed commits:**
1. Display the unpushed commits to the user
2. Ask which commits to include (default: all)
3. Generate a branch name from the first commit message
4. Create the new branch
5. Reset main/master to match origin
6. Continue to PR creation

**If already on a feature branch:**
1. Skip to PR creation

### Step 3: Commit Selection

Show unpushed commits:
```bash
git log origin/main..HEAD --oneline --no-decorate
```

Present options to the user:
- Include all commits (default)
- Select specific commits by hash
- Select a range of commits

### Step 4: Branch Name Generation

Generate a branch name from the first commit message using these rules:

**Detect commit type from conventional commit prefix:**
| Prefix | Branch Prefix |
|--------|---------------|
| `fix:`, `bugfix:` | `fix/` |
| `feat:`, `feature:`, `add:` | `feature/` |
| `refactor:`, `chore:`, `docs:`, `test:`, `style:`, `perf:`, `ci:`, `build:` | `feature/` |
| No prefix | `feature/` |

**Convert to kebab-case:**
1. Remove the commit type prefix (e.g., `fix:`)
2. Convert to lowercase
3. Replace spaces and special characters with hyphens
4. Remove consecutive hyphens
5. Limit to 50 characters
6. Remove trailing hyphens

**Examples:**
- `fix: authentication bug in login` → `fix/authentication-bug-login`
- `feat: add user profile page` → `feature/add-user-profile-page`
- `Add dark mode support` → `feature/add-dark-mode-support`
- `refactor: simplify API handlers` → `feature/simplify-api-handlers`

Present the generated branch name to the user and allow them to modify it if desired.

### Step 5: Create Branch and Migrate Commits

If migrating from main/master:

```bash
# Store current commit hash
CURRENT_COMMIT=$(git rev-parse HEAD)

# Create new branch at current position
git checkout -b <branch-name>

# Go back to main/master and reset to origin
git checkout main
git reset --hard origin/main

# Return to feature branch
git checkout <branch-name>
```

**Important:** Warn the user that this will modify their main/master branch. Get confirmation before proceeding.

### Step 6: Generate PR Title and Description

**PR Title:**
- Use the first commit's subject line
- Or derive from branch name if more descriptive
- Keep under 72 characters

**PR Description:**
Generate a structured description:

```markdown
## Summary

<Brief summary of changes based on commit messages>

## Changes

<Bulleted list of commits included>

## Test Plan

- [ ] <Suggested test items based on change type>

---
🤖 Generated with [Claude Code](https://claude.ai/code) via CodeBlend
```

Show the generated title and description to the user for review/editing.

### Step 7: Push and Create PR

```bash
# Push the branch
git push -u origin <branch-name>

# Create the PR
gh pr create --title "<title>" --body "<description>"

# Add the codeblend label
gh pr edit --add-label "codeblend"
```

If the "codeblend" label doesn't exist, create it:
```bash
gh label create codeblend --description "PR created with CodeBlend AI assistant" --color "7C3AED"
```

### Step 8: Confirmation

After successful PR creation, display:
- PR URL
- PR number
- Reminder about the codeblend label
- Next steps (request reviewers, add more labels, etc.)

## Error Handling

### Common Issues

**No upstream configured:**
```bash
git push -u origin <branch-name>
```

**Branch already exists on remote:**
Ask user if they want to force push or use a different branch name.

**PR already exists for branch:**
Show existing PR URL and ask if user wants to update it instead.

**Label creation fails (no permission):**
Skip label addition and inform user they can add it manually.

## Reference Files

For detailed git commands and edge case handling, see:
- `references/git-workflow.md` - Complete git operation reference

## Scripts

Helper scripts are available in the `scripts/` directory:
- `detect-branch.sh` - Detects current branch and commit status

## Tips

1. **Commit messages matter** - Well-written conventional commits make for better branch names and PR descriptions
2. **Review before submit** - Always review the generated PR content before submission
3. **Keep PRs focused** - If you have many unrelated commits, consider splitting into multiple PRs
4. **Use draft PRs** - Add `--draft` flag for work-in-progress PRs
