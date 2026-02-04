#!/usr/bin/env bash
# on-commit.sh
# Generates usage metrics when git commit is executed
# and appends summary to commit message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
INPUT_JSON=$(cat)

if [ -z "$INPUT_JSON" ]; then
    exit 0
fi

# Ensure jq is available
JQ=$("$SCRIPT_DIR/ensure-jq.sh" 2>/dev/null) || exit 0

# Check if this is a git commit command
COMMAND=$(echo "$INPUT_JSON" | "$JQ" -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Check if command is a git commit (but not amend, as we'll do that ourselves)
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
    exit 0
fi

# Skip if this is already an amend (avoid infinite loop)
if echo "$COMMAND" | grep -qE '\-\-amend'; then
    exit 0
fi

# Extract session info
SESSION_ID=$(echo "$INPUT_JSON" | "$JQ" -r '.session_id // empty')
CWD=$(echo "$INPUT_JSON" | "$JQ" -r '.cwd // empty')

if [ -z "$CWD" ]; then
    CWD=$(pwd)
fi

# Change to working directory
cd "$CWD" || exit 0

# Get the latest commit hash
COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || true)
if [ -z "$COMMIT_HASH" ]; then
    exit 0
fi

# Get commit details
ORIGINAL_MESSAGE=$(git log -1 --format="%B" 2>/dev/null || echo "")
COMMIT_SUBJECT=$(git log -1 --format="%s" 2>/dev/null || echo "")
COMMIT_TIME=$(git log -1 --format="%aI" 2>/dev/null || echo "")
AUTHOR_NAME=$(git log -1 --format="%an" 2>/dev/null || echo "")
AUTHOR_EMAIL=$(git log -1 --format="%ae" 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Check if commit message already contains CodeBlend info (avoid duplicate)
if echo "$ORIGINAL_MESSAGE" | grep -q "CodeBlend"; then
    exit 0
fi

# Parse file changes
FILES_CHANGED=0
TOTAL_INSERTIONS=0
TOTAL_DELETIONS=0
ADDED_FILES="[]"
MODIFIED_FILES="[]"
DELETED_FILES="[]"

# Get diff statistics
DIFF_STAT=$(git diff-tree --no-commit-id --numstat -r "$COMMIT_HASH" 2>/dev/null || true)

if [ -n "$DIFF_STAT" ]; then
    while IFS=$'\t' read -r insertions deletions filepath; do
        [ -z "$filepath" ] && continue

        # Handle binary files (shown as -)
        [ "$insertions" = "-" ] && insertions=0
        [ "$deletions" = "-" ] && deletions=0

        FILES_CHANGED=$((FILES_CHANGED + 1))
        TOTAL_INSERTIONS=$((TOTAL_INSERTIONS + insertions))
        TOTAL_DELETIONS=$((TOTAL_DELETIONS + deletions))

        # Determine file status using git show
        PARENT_EXISTS=$(git show "${COMMIT_HASH}^:$filepath" 2>/dev/null && echo "yes" || echo "no")
        CURRENT_EXISTS=$(git show "${COMMIT_HASH}:$filepath" 2>/dev/null && echo "yes" || echo "no")

        FILE_INFO=$("$JQ" -n --arg path "$filepath" --argjson ins "$insertions" --argjson del "$deletions" \
            '{path: $path, insertions: $ins, deletions: $del}')

        if [ "$PARENT_EXISTS" = "no" ] && [ "$CURRENT_EXISTS" = "yes" ]; then
            ADDED_FILES=$(echo "$ADDED_FILES" | "$JQ" --argjson f "$FILE_INFO" '. + [$f]')
        elif [ "$PARENT_EXISTS" = "yes" ] && [ "$CURRENT_EXISTS" = "no" ]; then
            DELETED_FILES=$(echo "$DELETED_FILES" | "$JQ" --argjson f "$FILE_INFO" '. + [$f]')
        else
            MODIFIED_FILES=$(echo "$MODIFIED_FILES" | "$JQ" --argjson f "$FILE_INFO" '. + [$f]')
        fi
    done <<< "$DIFF_STAT"
fi

# Find state file
if [ -n "${TMPDIR:-}" ]; then
    TEMP_DIR="$TMPDIR"
elif [ -n "${TMP:-}" ]; then
    TEMP_DIR="$TMP"
elif [ -n "${TEMP:-}" ]; then
    TEMP_DIR="$TEMP"
elif [ -d "/tmp" ]; then
    TEMP_DIR="/tmp"
else
    TEMP_DIR="."
fi

STATE_DIR="$TEMP_DIR/codeblend"
STATE_FILE="$STATE_DIR/$SESSION_ID.json"

# Load session state if exists
if [ -f "$STATE_FILE" ]; then
    SESSION_STATE=$(cat "$STATE_FILE")
    CLAUDE_VERSION=$(echo "$SESSION_STATE" | "$JQ" -r '.claude_version // "unknown"')
    MODEL=$(echo "$SESSION_STATE" | "$JQ" -r '.model // "unknown"')
    PERMISSION_MODE=$(echo "$SESSION_STATE" | "$JQ" -r '.permission_mode // "unknown"')
    TOOL_USAGE=$(echo "$SESSION_STATE" | "$JQ" -c '.tool_usage // {}')
    FILE_OPERATIONS=$(echo "$SESSION_STATE" | "$JQ" -c '.file_operations // {}')
else
    CLAUDE_VERSION="unknown"
    MODEL="unknown"
    PERMISSION_MODE="unknown"
    TOOL_USAGE='{"builtin_tools":{},"skills":[],"mcp_tools":[],"subagents":[]}'
    FILE_OPERATIONS='{"files_read":[],"files_created":[],"files_modified":[],"search_patterns":{"glob":[],"grep":[]}}'
fi

# Detect AI agent configuration files
detect_ai_agents() {
    local cwd="$1"
    local agents='{}'

    # Claude Code
    local claude_found="false"
    local claude_files="[]"
    [ -f "$cwd/CLAUDE.md" ] && claude_found="true" && claude_files=$(echo "$claude_files" | "$JQ" '. + ["CLAUDE.md"]')
    [ -d "$cwd/.claude" ] && claude_found="true" && claude_files=$(echo "$claude_files" | "$JQ" '. + [".claude"]')
    agents=$(echo "$agents" | "$JQ" --arg found "$claude_found" --argjson files "$claude_files" \
        '.claude_code = {found: ($found == "true"), files: $files}')

    # Cursor
    local cursor_found="false"
    local cursor_files="[]"
    [ -f "$cwd/.cursorrules" ] && cursor_found="true" && cursor_files='[".cursorrules"]'
    agents=$(echo "$agents" | "$JQ" --arg found "$cursor_found" --argjson files "$cursor_files" \
        '.cursor = {found: ($found == "true"), files: $files}')

    # GitHub Copilot
    local copilot_found="false"
    local copilot_files="[]"
    [ -f "$cwd/.github/copilot-instructions.md" ] && copilot_found="true" && copilot_files='[".github/copilot-instructions.md"]'
    agents=$(echo "$agents" | "$JQ" --arg found "$copilot_found" --argjson files "$copilot_files" \
        '.github_copilot = {found: ($found == "true"), files: $files}')

    # Aider
    local aider_found="false"
    local aider_files="[]"
    for f in "$cwd"/.aider* "$cwd"/aider.conf.*; do
        if [ -e "$f" ]; then
            aider_found="true"
            fname=$(basename "$f")
            aider_files=$(echo "$aider_files" | "$JQ" --arg f "$fname" '. + [$f]')
        fi
    done
    agents=$(echo "$agents" | "$JQ" --arg found "$aider_found" --argjson files "$aider_files" \
        '.aider = {found: ($found == "true"), files: $files}')

    # Continue
    local continue_found="false"
    local continue_files="[]"
    [ -d "$cwd/.continue" ] && continue_found="true" && continue_files='[".continue"]'
    agents=$(echo "$agents" | "$JQ" --arg found "$continue_found" --argjson files "$continue_files" \
        '.continue_dev = {found: ($found == "true"), files: $files}')

    # Codeium
    local codeium_found="false"
    local codeium_files="[]"
    [ -d "$cwd/.codeium" ] && codeium_found="true" && codeium_files='[".codeium"]'
    agents=$(echo "$agents" | "$JQ" --arg found "$codeium_found" --argjson files "$codeium_files" \
        '.codeium = {found: ($found == "true"), files: $files}')

    # Amazon Q
    local amazonq_found="false"
    local amazonq_files="[]"
    [ -d "$cwd/.amazonq" ] && amazonq_found="true" && amazonq_files='[".amazonq"]'
    agents=$(echo "$agents" | "$JQ" --arg found "$amazonq_found" --argjson files "$amazonq_files" \
        '.amazon_q = {found: ($found == "true"), files: $files}')

    # Windsurf
    local windsurf_found="false"
    local windsurf_files="[]"
    [ -d "$cwd/.windsurf" ] && windsurf_found="true" && windsurf_files='[".windsurf"]'
    agents=$(echo "$agents" | "$JQ" --arg found "$windsurf_found" --argjson files "$windsurf_files" \
        '.windsurf = {found: ($found == "true"), files: $files}')

    # Tabby
    local tabby_found="false"
    local tabby_files="[]"
    [ -d "$cwd/.tabby" ] && tabby_found="true" && tabby_files='[".tabby"]'
    agents=$(echo "$agents" | "$JQ" --arg found "$tabby_found" --argjson files "$tabby_files" \
        '.tabby = {found: ($found == "true"), files: $files}')

    echo "$agents"
}

AI_AGENTS=$(detect_ai_agents "$CWD")

# Count detected agents
DETECTED_COUNT=$(echo "$AI_AGENTS" | "$JQ" '[.[] | select(.found == true)] | length')
IS_MIXED_REPO="false"
[ "$DETECTED_COUNT" -gt 1 ] && IS_MIXED_REPO="true"

# Build the output JSON for file storage
OUTPUT=$("$JQ" -n \
    --arg commit_hash "$COMMIT_HASH" \
    --arg commit_message "$COMMIT_SUBJECT" \
    --arg commit_time "$COMMIT_TIME" \
    --arg branch "$BRANCH" \
    --arg author_name "$AUTHOR_NAME" \
    --arg author_email "$AUTHOR_EMAIL" \
    --argjson files_changed "$FILES_CHANGED" \
    --argjson insertions "$TOTAL_INSERTIONS" \
    --argjson deletions "$TOTAL_DELETIONS" \
    --argjson added "$ADDED_FILES" \
    --argjson modified "$MODIFIED_FILES" \
    --argjson deleted "$DELETED_FILES" \
    --arg claude_version "$CLAUDE_VERSION" \
    --arg model "$MODEL" \
    --arg session_id "$SESSION_ID" \
    --arg permission_mode "$PERMISSION_MODE" \
    --argjson tool_usage "$TOOL_USAGE" \
    --argjson file_operations "$FILE_OPERATIONS" \
    --argjson ai_agents "$AI_AGENTS" \
    --arg is_mixed "$IS_MIXED_REPO" \
'{
    commit_hash: $commit_hash,
    commit_message: $commit_message,
    commit_time: $commit_time,
    branch: $branch,
    author: {
        name: $author_name,
        email: $author_email
    },
    file_changes: {
        summary: {
            files_changed: $files_changed,
            insertions: $insertions,
            deletions: $deletions
        },
        added: $added,
        modified: $modified,
        deleted: $deleted
    },
    claude_code: {
        version: $claude_version,
        model: $model,
        session_id: $session_id,
        permission_mode: $permission_mode
    },
    tool_usage: $tool_usage,
    file_operations: $file_operations,
    repo_context: {
        ai_agents_detected: $ai_agents,
        is_mixed_repo: ($is_mixed == "true")
    }
}')

# Create output directory and save JSON
CODEBLEND_DIR="$CWD/.codeblend/commits"
mkdir -p "$CODEBLEND_DIR"

SHORT_HASH="${COMMIT_HASH:0:12}"
OUTPUT_FILE="$CODEBLEND_DIR/$SHORT_HASH.json"
echo "$OUTPUT" > "$OUTPUT_FILE"

# ============================================
# Generate commit message summary
# ============================================

# Build tools summary (e.g., "Read(10), Edit(3), Bash(5)")
TOOLS_SUMMARY=$(echo "$TOOL_USAGE" | "$JQ" -r '
    .builtin_tools | to_entries | map(select(.value.count > 0)) |
    sort_by(-.value.count) |
    map("\(.key)(\(.value.count))") |
    join(", ")
')

# Build subagents summary if any
SUBAGENTS_SUMMARY=$(echo "$TOOL_USAGE" | "$JQ" -r '
    .subagents | map(select(.count > 0)) |
    map("\(.type)(\(.count))") |
    join(", ")
')

# Build MCP tools summary if any
MCP_SUMMARY=$(echo "$TOOL_USAGE" | "$JQ" -r '
    .mcp_tools | map(select(.count > 0)) |
    map("\(.server)/\(.tool)(\(.count))") |
    join(", ")
')

# Build skills summary if any
SKILLS_SUMMARY=$(echo "$TOOL_USAGE" | "$JQ" -r '
    .skills | map(select(.count > 0)) |
    map("\(.name)(\(.count))") |
    join(", ")
')

# Format model name (extract short name)
MODEL_SHORT=$(echo "$MODEL" | sed -E 's/^(claude-[a-z0-9-]+).*/\1/')

# Build the commit message trailer
TRAILER="
---
Generated with [CodeBlend](https://github.com/anthropics/claude-code)
Model: $MODEL_SHORT"

# Add tools if any
if [ -n "$TOOLS_SUMMARY" ]; then
    TRAILER="$TRAILER
Tools: $TOOLS_SUMMARY"
fi

# Add subagents if any
if [ -n "$SUBAGENTS_SUMMARY" ]; then
    TRAILER="$TRAILER
Agents: $SUBAGENTS_SUMMARY"
fi

# Add MCP tools if any
if [ -n "$MCP_SUMMARY" ]; then
    TRAILER="$TRAILER
MCP: $MCP_SUMMARY"
fi

# Add skills if any
if [ -n "$SKILLS_SUMMARY" ]; then
    TRAILER="$TRAILER
Skills: $SKILLS_SUMMARY"
fi

# Add file stats
TRAILER="$TRAILER
Files: $FILES_CHANGED changed (+$TOTAL_INSERTIONS -$TOTAL_DELETIONS)"

# Combine original message with trailer
NEW_MESSAGE="${ORIGINAL_MESSAGE}${TRAILER}"

# Amend the commit with new message
git commit --amend --no-verify -m "$NEW_MESSAGE" 2>/dev/null || true

exit 0
