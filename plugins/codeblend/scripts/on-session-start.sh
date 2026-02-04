#!/usr/bin/env bash
# on-session-start.sh
# Initializes session state when Claude Code session starts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
INPUT_JSON=$(cat)

if [ -z "$INPUT_JSON" ]; then
    exit 0
fi

# Ensure jq is available
JQ=$("$SCRIPT_DIR/ensure-jq.sh" 2>/dev/null) || {
    echo "Warning: Failed to ensure jq for codeblend plugin" >&2
    exit 0
}

# Extract session information
SESSION_ID=$(echo "$INPUT_JSON" | "$JQ" -r '.session_id // empty')
MODEL=$(echo "$INPUT_JSON" | "$JQ" -r '.model // "unknown"')
PERMISSION_MODE=$(echo "$INPUT_JSON" | "$JQ" -r '.permission_mode // "unknown"')
CWD=$(echo "$INPUT_JSON" | "$JQ" -r '.cwd // empty')

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# Get Claude Code version
CLAUDE_VERSION="unknown"
if command -v claude &> /dev/null; then
    VERSION_OUTPUT=$(claude --version 2>/dev/null || true)
    if [[ "$VERSION_OUTPUT" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        CLAUDE_VERSION="${BASH_REMATCH[1]}"
    elif [ -n "$VERSION_OUTPUT" ]; then
        CLAUDE_VERSION=$(echo "$VERSION_OUTPUT" | tr -d '[:space:]')
    fi
fi

# Determine state file location (cross-platform temp directory)
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
mkdir -p "$STATE_DIR"

STATE_FILE="$STATE_DIR/$SESSION_ID.json"

# Get current timestamp in ISO format
START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Initialize session state
cat > "$STATE_FILE" << EOF
{
  "session_id": "$SESSION_ID",
  "model": "$MODEL",
  "permission_mode": "$PERMISSION_MODE",
  "claude_version": "$CLAUDE_VERSION",
  "cwd": "$CWD",
  "start_time": "$START_TIME",
  "tool_usage": {
    "builtin_tools": {},
    "skills": [],
    "mcp_tools": [],
    "subagents": []
  },
  "file_operations": {
    "files_read": [],
    "files_created": [],
    "files_modified": [],
    "search_patterns": {
      "glob": [],
      "grep": []
    }
  }
}
EOF

exit 0
