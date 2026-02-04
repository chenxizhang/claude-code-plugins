# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Claude Code plugins marketplace repository. It contains multiple plugins organized under a single marketplace definition that can be installed together or individually.

## Architecture

```
claude-code-plugins/
├── .claude-plugin/
│   └── marketplace.json      # Marketplace definition (plugins registry)
└── plugins/
    └── <plugin-name>/        # Each plugin is a self-contained directory
        ├── .claude-plugin/
        │   └── plugin.json   # Plugin manifest (ONLY this file here)
        ├── commands/         # Slash commands (*.md files)
        ├── agents/           # Custom agents (*.md files)
        ├── skills/           # Skills (subdirs with SKILL.md)
        ├── hooks/            # Hook configs (*.json files)
        └── .mcp.json         # MCP server definitions (optional)
```

## Key Rules

1. **`.claude-plugin/` contains ONLY manifests** - Never put commands, agents, skills, or hooks inside `.claude-plugin/`. They go at the plugin root level.

2. **Use `${CLAUDE_PLUGIN_ROOT}`** - In hooks and MCP configs, use this variable for portable paths that work after installation.

3. **Plugin naming** - Use kebab-case. The name becomes the namespace prefix (e.g., plugin `my-tool` → skill invoked as `/my-tool:command-name`).

4. **Marketplace registration** - After creating a plugin, add it to `.claude-plugin/marketplace.json`:
   ```json
   {
     "name": "plugin-name",
     "source": "./plugins/plugin-name",
     "description": "Brief description",
     "version": "1.0.0"
   }
   ```

## Creating a New Plugin

Use the available skills for guided workflows:
- `/plugin-dev:create-plugin` - End-to-end plugin creation
- `/plugin-dev:plugin-structure` - Architecture guidance
- `/plugin-dev:command-development` - Slash commands
- `/plugin-dev:agent-development` - Custom agents
- `/plugin-dev:skill-development` - Skills
- `/plugin-dev:hook-development` - Hooks
- `/plugin-dev:mcp-integration` - MCP servers

## Testing Plugins Locally

```bash
# Test a specific plugin
claude --plugin-dir ./plugins/my-plugin

# Validate plugin structure
claude plugin validate ./plugins/my-plugin
```

## Installing the Marketplace

Users install this marketplace with:
```bash
/plugin marketplace add <github-owner>/<repo-name>
```
