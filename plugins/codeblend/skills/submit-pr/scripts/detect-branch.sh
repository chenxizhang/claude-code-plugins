#!/bin/bash
# detect-branch.sh - Detect current branch and commit status for PR workflow
# Usage: ./detect-branch.sh
# Output: JSON with branch info for PR decision making

set -e

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

if [ -z "$CURRENT_BRANCH" ]; then
    echo '{"error": "Not in a git repository or in detached HEAD state"}'
    exit 1
fi

# Detect default branch (main or master)
DEFAULT_BRANCH=""
if git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
    DEFAULT_BRANCH="main"
elif git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
    DEFAULT_BRANCH="master"
else
    # Try to get from remote HEAD
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
fi

# Check if on default branch
IS_DEFAULT_BRANCH="false"
if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
    IS_DEFAULT_BRANCH="true"
fi

# Check for unpushed commits
UNPUSHED_COUNT=0
UNPUSHED_COMMITS="[]"

if git rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
    UNPUSHED_COUNT=$(git rev-list --count "origin/$CURRENT_BRANCH..HEAD" 2>/dev/null || echo "0")

    if [ "$UNPUSHED_COUNT" -gt 0 ]; then
        # Get commit details as JSON array
        UNPUSHED_COMMITS=$(git log "origin/$CURRENT_BRANCH..HEAD" --format='{"hash":"%h","subject":"%s"}' --no-decorate | \
            jq -s '.' 2>/dev/null || echo "[]")
    fi
else
    # No remote tracking branch - all commits are "unpushed"
    UNPUSHED_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    if [ "$UNPUSHED_COUNT" -gt 0 ]; then
        UNPUSHED_COMMITS=$(git log HEAD --format='{"hash":"%h","subject":"%s"}' --no-decorate | \
            jq -s '.' 2>/dev/null || echo "[]")
    fi
fi

# Check for uncommitted changes
HAS_UNCOMMITTED="false"
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    HAS_UNCOMMITTED="true"
fi

# Check for staged changes
HAS_STAGED="false"
if ! git diff --cached --quiet 2>/dev/null; then
    HAS_STAGED="true"
fi

# Get first unpushed commit message for branch name generation
FIRST_COMMIT_MSG=""
if [ "$UNPUSHED_COUNT" -gt 0 ]; then
    if git rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
        FIRST_COMMIT_MSG=$(git log "origin/$CURRENT_BRANCH..HEAD" --format="%s" --reverse | head -1)
    else
        FIRST_COMMIT_MSG=$(git log --format="%s" --reverse | head -1)
    fi
fi

# Generate suggested branch name from first commit
SUGGESTED_BRANCH=""
if [ -n "$FIRST_COMMIT_MSG" ] && [ "$IS_DEFAULT_BRANCH" = "true" ]; then
    # Extract commit type
    PREFIX="feature"
    DESCRIPTION="$FIRST_COMMIT_MSG"

    if echo "$FIRST_COMMIT_MSG" | grep -qE "^(fix|bugfix)(\(.+\))?:"; then
        PREFIX="fix"
        DESCRIPTION=$(echo "$FIRST_COMMIT_MSG" | sed -E 's/^(fix|bugfix)(\(.+\))?:\s*//')
    elif echo "$FIRST_COMMIT_MSG" | grep -qE "^(feat|feature|add)(\(.+\))?:"; then
        PREFIX="feature"
        DESCRIPTION=$(echo "$FIRST_COMMIT_MSG" | sed -E 's/^(feat|feature|add)(\(.+\))?:\s*//')
    elif echo "$FIRST_COMMIT_MSG" | grep -qE "^(refactor|chore|docs|test|style|perf|ci|build)(\(.+\))?:"; then
        PREFIX="feature"
        DESCRIPTION=$(echo "$FIRST_COMMIT_MSG" | sed -E 's/^(refactor|chore|docs|test|style|perf|ci|build)(\(.+\))?:\s*//')
    fi

    # Convert to kebab-case
    KEBAB=$(echo "$DESCRIPTION" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-//' | \
        sed 's/-$//' | \
        cut -c1-50)

    SUGGESTED_BRANCH="$PREFIX/$KEBAB"
fi

# Check gh CLI status
GH_INSTALLED="false"
GH_AUTHENTICATED="false"

if command -v gh >/dev/null 2>&1; then
    GH_INSTALLED="true"
    if gh auth status >/dev/null 2>&1; then
        GH_AUTHENTICATED="true"
    fi
fi

# Output JSON
cat <<EOF
{
    "current_branch": "$CURRENT_BRANCH",
    "default_branch": "$DEFAULT_BRANCH",
    "is_default_branch": $IS_DEFAULT_BRANCH,
    "unpushed_count": $UNPUSHED_COUNT,
    "unpushed_commits": $UNPUSHED_COMMITS,
    "first_commit_message": $(echo "$FIRST_COMMIT_MSG" | jq -R . 2>/dev/null || echo '""'),
    "suggested_branch": "$SUGGESTED_BRANCH",
    "has_uncommitted_changes": $HAS_UNCOMMITTED,
    "has_staged_changes": $HAS_STAGED,
    "gh_installed": $GH_INSTALLED,
    "gh_authenticated": $GH_AUTHENTICATED
}
EOF
