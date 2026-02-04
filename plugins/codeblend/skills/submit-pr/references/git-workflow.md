# Git Workflow Reference for PR Submission

This document contains detailed git commands and procedures for the submit-pr skill.

## Branch Detection Commands

### Get Current Branch
```bash
git branch --show-current
```

### Check if Branch is Main/Master
```bash
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    echo "on-default"
else
    echo "on-feature"
fi
```

### Get Default Branch Name
```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

Or fallback:
```bash
git remote show origin | grep 'HEAD branch' | cut -d' ' -f5
```

### Check for Unpushed Commits
```bash
# Get count of unpushed commits
git rev-list --count origin/$(git branch --show-current)..HEAD 2>/dev/null || echo "0"
```

### List Unpushed Commits
```bash
git log origin/$(git branch --show-current)..HEAD --oneline --no-decorate
```

### Get Detailed Commit Info
```bash
git log origin/$(git branch --show-current)..HEAD --format="%h %s" --no-decorate
```

## Commit Selection

### Select All Commits (Default)
No special handling needed - use HEAD as-is.

### Select Specific Commits
For cherry-picking specific commits to a new branch:
```bash
# Create branch from origin/main
git checkout -b <branch-name> origin/main

# Cherry-pick selected commits
git cherry-pick <commit1> <commit2> <commit3>
```

### Select Range of Commits
```bash
# From commit A to HEAD
git log <commit-A>..HEAD --oneline

# Cherry-pick a range
git cherry-pick <older-commit>^..<newer-commit>
```

## Branch Name Generation

### Extract Commit Message
```bash
git log -1 --format="%s" HEAD
```

### Parse Conventional Commit Type
```bash
MSG=$(git log -1 --format="%s" HEAD)

# Extract type if present
if [[ "$MSG" =~ ^(fix|bugfix|feat|feature|add|refactor|chore|docs|test|style|perf|ci|build)(\(.+\))?:\ (.+) ]]; then
    TYPE="${BASH_REMATCH[1]}"
    DESCRIPTION="${BASH_REMATCH[3]}"
else
    TYPE=""
    DESCRIPTION="$MSG"
fi

# Map to branch prefix
case "$TYPE" in
    fix|bugfix)
        PREFIX="fix"
        ;;
    *)
        PREFIX="feature"
        ;;
esac
```

### Convert to Kebab-Case
```bash
# Convert description to kebab-case branch name
BRANCH_NAME=$(echo "$DESCRIPTION" | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9]/-/g' | \
    sed 's/--*/-/g' | \
    sed 's/^-//' | \
    sed 's/-$//' | \
    cut -c1-50)

echo "$PREFIX/$BRANCH_NAME"
```

## Branch Creation and Commit Migration

### Full Migration Workflow
```bash
# 1. Store current state
CURRENT_COMMIT=$(git rev-parse HEAD)
DEFAULT_BRANCH=$(git branch --show-current)
NEW_BRANCH="feature/my-changes"

# 2. Create new branch at current position
git checkout -b "$NEW_BRANCH"

# 3. Return to default branch and reset
git checkout "$DEFAULT_BRANCH"
git reset --hard "origin/$DEFAULT_BRANCH"

# 4. Switch to new branch for PR work
git checkout "$NEW_BRANCH"
```

### Partial Migration (Selected Commits)
```bash
# 1. Store commits to migrate
COMMITS_TO_MIGRATE="abc123 def456 ghi789"
DEFAULT_BRANCH=$(git branch --show-current)
NEW_BRANCH="feature/selected-changes"

# 2. Create new branch from origin
git checkout -b "$NEW_BRANCH" "origin/$DEFAULT_BRANCH"

# 3. Cherry-pick selected commits
for commit in $COMMITS_TO_MIGRATE; do
    git cherry-pick "$commit"
done

# 4. Reset default branch
git checkout "$DEFAULT_BRANCH"
git reset --hard "origin/$DEFAULT_BRANCH"

# 5. Return to feature branch
git checkout "$NEW_BRANCH"
```

## PR Creation

### Push Branch
```bash
git push -u origin "$(git branch --show-current)"
```

### Create PR with gh CLI
```bash
gh pr create \
    --title "Add user authentication" \
    --body "## Summary
Adds user authentication with JWT tokens.

## Changes
- Add login endpoint
- Add JWT token generation
- Add auth middleware

## Test Plan
- [ ] Test login with valid credentials
- [ ] Test login with invalid credentials
- [ ] Test protected endpoints

---
🤖 Generated with [Claude Code](https://claude.ai/code) via CodeBlend"
```

### Create Draft PR
```bash
gh pr create --draft --title "WIP: Feature name" --body "..."
```

### Add Label to PR
```bash
gh pr edit --add-label "codeblend"
```

### Create Label if Missing
```bash
# Check if label exists
gh label list | grep -q "codeblend" || \
    gh label create codeblend \
        --description "PR created with CodeBlend AI assistant" \
        --color "7C3AED"
```

## Edge Cases

### Remote Branch Already Exists
```bash
# Check if branch exists on remote
git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"

if [ $? -eq 0 ]; then
    echo "Branch already exists on remote"
    # Options: force push, use different name, or update existing
fi
```

### PR Already Exists for Branch
```bash
# Check for existing PR
EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number')

if [ -n "$EXISTING_PR" ]; then
    echo "PR #$EXISTING_PR already exists for this branch"
    gh pr view "$EXISTING_PR" --web
fi
```

### No Upstream Tracking
```bash
# Check if upstream is set
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null

if [ $? -ne 0 ]; then
    echo "No upstream tracking branch set"
    git push -u origin "$(git branch --show-current)"
fi
```

### Uncommitted Changes Present
```bash
# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "Warning: You have uncommitted changes"
    echo "Please commit or stash them before creating a PR"
fi
```

### Diverged from Remote
```bash
# Check if local and remote have diverged
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/$(git branch --show-current) 2>/dev/null)
BASE=$(git merge-base HEAD origin/$(git branch --show-current) 2>/dev/null)

if [ "$LOCAL" != "$REMOTE" ] && [ "$LOCAL" != "$BASE" ] && [ "$REMOTE" != "$BASE" ]; then
    echo "Warning: Local and remote have diverged"
    echo "Consider pulling or rebasing before creating PR"
fi
```

## Useful Queries

### Get PR URL After Creation
```bash
gh pr view --json url --jq '.url'
```

### Get PR Number
```bash
gh pr view --json number --jq '.number'
```

### List All Labels
```bash
gh label list
```

### View PR Status
```bash
gh pr status
```
