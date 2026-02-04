#!/usr/bin/env bash
# on-tool-use.sh
# Tracks tool usage during Claude Code session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
INPUT_JSON=$(cat)

if [ -z "$INPUT_JSON" ]; then
    exit 0
fi

# Ensure jq is available
JQ=$("$SCRIPT_DIR/ensure-jq.sh" 2>/dev/null) || exit 0

# Extract information
SESSION_ID=$(echo "$INPUT_JSON" | "$JQ" -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT_JSON" | "$JQ" -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT_JSON" | "$JQ" -c '.tool_input // {}')

if [ -z "$SESSION_ID" ] || [ -z "$TOOL_NAME" ]; then
    exit 0
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

if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

# Load current state
STATE=$(cat "$STATE_FILE")

# Known builtin tools
BUILTIN_TOOLS="Bash Read Write Edit Glob Grep WebFetch WebSearch NotebookEdit Task Skill AskUserQuestion EnterPlanMode ExitPlanMode TaskCreate TaskUpdate TaskGet TaskList TaskOutput TaskStop"

# Process based on tool type
if [ "$TOOL_NAME" = "Skill" ]; then
    # Skill invocation
    SKILL_NAME=$(echo "$TOOL_INPUT" | "$JQ" -r '.skill // empty')
    if [ -n "$SKILL_NAME" ]; then
        STATE=$(echo "$STATE" | "$JQ" --arg name "$SKILL_NAME" '
            if (.tool_usage.skills | map(select(.name == $name)) | length) > 0 then
                .tool_usage.skills = (.tool_usage.skills | map(if .name == $name then .count += 1 else . end))
            else
                .tool_usage.skills += [{"name": $name, "count": 1}]
            end
        ')
    fi

elif [ "$TOOL_NAME" = "Task" ]; then
    # Subagent invocation
    AGENT_TYPE=$(echo "$TOOL_INPUT" | "$JQ" -r '.subagent_type // empty')
    DESCRIPTION=$(echo "$TOOL_INPUT" | "$JQ" -r '.description // empty')
    if [ -n "$AGENT_TYPE" ]; then
        STATE=$(echo "$STATE" | "$JQ" --arg type "$AGENT_TYPE" --arg desc "$DESCRIPTION" '
            if (.tool_usage.subagents | map(select(.type == $type)) | length) > 0 then
                .tool_usage.subagents = (.tool_usage.subagents | map(
                    if .type == $type then
                        .count += 1 |
                        if $desc != "" and (.prompts | index($desc) | not) then
                            .prompts += [$desc]
                        else
                            .
                        end
                    else
                        .
                    end
                ))
            else
                .tool_usage.subagents += [{"type": $type, "count": 1, "prompts": (if $desc != "" then [$desc] else [] end)}]
            end
        ')
    fi

elif [[ "$TOOL_NAME" == mcp__* ]]; then
    # MCP tool invocation - parse mcp__<server>__<tool>
    MCP_SERVER=$(echo "$TOOL_NAME" | cut -d'_' -f3)
    MCP_TOOL=$(echo "$TOOL_NAME" | cut -d'_' -f4-)
    if [ -n "$MCP_SERVER" ] && [ -n "$MCP_TOOL" ]; then
        STATE=$(echo "$STATE" | "$JQ" --arg server "$MCP_SERVER" --arg tool "$MCP_TOOL" '
            if (.tool_usage.mcp_tools | map(select(.server == $server and .tool == $tool)) | length) > 0 then
                .tool_usage.mcp_tools = (.tool_usage.mcp_tools | map(
                    if .server == $server and .tool == $tool then .count += 1 else . end
                ))
            else
                .tool_usage.mcp_tools += [{"server": $server, "tool": $tool, "count": 1}]
            end
        ')
    fi

elif echo "$BUILTIN_TOOLS" | grep -qw "$TOOL_NAME"; then
    # Builtin tool
    STATE=$(echo "$STATE" | "$JQ" --arg tool "$TOOL_NAME" '
        if .tool_usage.builtin_tools[$tool] then
            .tool_usage.builtin_tools[$tool].count += 1
        else
            .tool_usage.builtin_tools[$tool] = {"count": 1}
        end
    ')

    # Track specific data based on tool type
    case "$TOOL_NAME" in
        "Bash")
            COMMAND=$(echo "$TOOL_INPUT" | "$JQ" -r '.command // empty')
            if [ -n "$COMMAND" ]; then
                # Truncate command to 100 chars
                SHORT_CMD=$(echo "$COMMAND" | cut -c1-100)
                if [ ${#COMMAND} -gt 100 ]; then
                    SHORT_CMD="${SHORT_CMD}..."
                fi
                STATE=$(echo "$STATE" | "$JQ" --arg cmd "$SHORT_CMD" '
                    .tool_usage.builtin_tools.Bash.commands = ((.tool_usage.builtin_tools.Bash.commands // []) + [$cmd])
                ')
            fi
            ;;
        "Read")
            FILE_PATH=$(echo "$TOOL_INPUT" | "$JQ" -r '.file_path // empty')
            if [ -n "$FILE_PATH" ]; then
                STATE=$(echo "$STATE" | "$JQ" --arg path "$FILE_PATH" '
                    if (.file_operations.files_read | index($path) | not) then
                        .file_operations.files_read += [$path]
                    else
                        .
                    end
                ')
            fi
            ;;
        "Write")
            FILE_PATH=$(echo "$TOOL_INPUT" | "$JQ" -r '.file_path // empty')
            if [ -n "$FILE_PATH" ]; then
                STATE=$(echo "$STATE" | "$JQ" --arg path "$FILE_PATH" '
                    (if (.file_operations.files_created | index($path) | not) then
                        .file_operations.files_created += [$path]
                    else
                        .
                    end) |
                    .tool_usage.builtin_tools.Write.files = ((.tool_usage.builtin_tools.Write.files // []) | if index($path) | not then . + [$path] else . end)
                ')
            fi
            ;;
        "Edit")
            FILE_PATH=$(echo "$TOOL_INPUT" | "$JQ" -r '.file_path // empty')
            if [ -n "$FILE_PATH" ]; then
                STATE=$(echo "$STATE" | "$JQ" --arg path "$FILE_PATH" '
                    (if (.file_operations.files_modified | index($path) | not) then
                        .file_operations.files_modified += [$path]
                    else
                        .
                    end) |
                    .tool_usage.builtin_tools.Edit.files = ((.tool_usage.builtin_tools.Edit.files // []) | if index($path) | not then . + [$path] else . end)
                ')
            fi
            ;;
        "Glob")
            PATTERN=$(echo "$TOOL_INPUT" | "$JQ" -r '.pattern // empty')
            if [ -n "$PATTERN" ]; then
                STATE=$(echo "$STATE" | "$JQ" --arg pat "$PATTERN" '
                    (if (.file_operations.search_patterns.glob | index($pat) | not) then
                        .file_operations.search_patterns.glob += [$pat]
                    else
                        .
                    end) |
                    .tool_usage.builtin_tools.Glob.patterns = ((.tool_usage.builtin_tools.Glob.patterns // []) | if index($pat) | not then . + [$pat] else . end)
                ')
            fi
            ;;
        "Grep")
            PATTERN=$(echo "$TOOL_INPUT" | "$JQ" -r '.pattern // empty')
            if [ -n "$PATTERN" ]; then
                STATE=$(echo "$STATE" | "$JQ" --arg pat "$PATTERN" '
                    (if (.file_operations.search_patterns.grep | index($pat) | not) then
                        .file_operations.search_patterns.grep += [$pat]
                    else
                        .
                    end) |
                    .tool_usage.builtin_tools.Grep.patterns = ((.tool_usage.builtin_tools.Grep.patterns // []) | if index($pat) | not then . + [$pat] else . end)
                ')
            fi
            ;;
    esac
fi

# Save updated state
echo "$STATE" > "$STATE_FILE"

exit 0
