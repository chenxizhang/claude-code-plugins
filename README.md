# Claude Code Plugins Marketplace

A curated collection of plugins for [Claude Code](https://claude.ai/code), Anthropic's official CLI for Claude.

## Installation

Install the entire marketplace with a single command:

```bash
/plugin marketplace add chenxizhang/claude-code-plugins
```

Or install the codeblend plugin directly:

```bash
/plugin add chenxizhang/claude-code-plugins/plugins/codeblend
```

Or install individual plugins locally:

```bash
claude --plugin-dir ./plugins/<plugin-name>
```

## Available Plugins

### codeblend

**Automatically records Claude Code usage metrics when git commits are made.**

This plugin tracks your Claude Code sessions and enriches commit messages with useful metadata about how the code was created.

#### Features

- **Session Tracking**: Records tool usage, file operations, and search patterns during your Claude Code session
- **Commit Enhancement**: Automatically appends usage summaries to your git commit messages
- **Metrics Storage**: Saves detailed JSON metrics in `.codeblend/commits/` for analysis
- **AI Agent Detection**: Identifies other AI coding assistants configured in your repo (Cursor, Copilot, Aider, etc.)

#### What Gets Tracked

| Category | Details |
|----------|---------|
| Tool Usage | Count of each built-in tool (Read, Edit, Bash, Glob, Grep, etc.) |
| File Operations | Files read, created, and modified |
| Search Patterns | Glob and grep patterns used |
| Subagents | Task agents spawned (Explore, Plan, etc.) |
| MCP Tools | Any MCP server tools invoked |
| Skills | Slash command skills used |

#### Example Commit Message

After the plugin is installed, your commits will include a footer like:

```
Fix authentication bug in login flow

---
Generated with [CodeBlend](https://github.com/anthropics/claude-code)
Model: claude-opus-4-5
Tools: Read(12), Edit(5), Bash(3), Grep(2)
Agents: Explore(1)
Files: 4 changed (+127 -23)
```

#### Privacy

All data is stored locally in your repository. No data is sent externally. The `.codeblend/` directory can be added to `.gitignore` if you prefer not to commit the detailed metrics.

## Repository Structure

```
claude-code-plugins/
├── .claude-plugin/
│   └── marketplace.json      # Marketplace definition
├── plugins/
│   └── codeblend/            # CodeBlend plugin
│       ├── .claude-plugin/
│       │   └── plugin.json   # Plugin manifest
│       ├── hooks/
│       │   └── hooks.json    # Hook definitions
│       └── scripts/          # Hook implementation scripts
├── CLAUDE.md                 # Development guidance
└── README.md                 # This file
```

## Creating Your Own Plugin

This repository follows the Claude Code plugin architecture. Each plugin is self-contained under `plugins/` with:

- **`.claude-plugin/plugin.json`** - Plugin manifest (name, version, description)
- **`commands/`** - Slash commands (Markdown files)
- **`agents/`** - Custom agents (Markdown files)
- **`skills/`** - Interactive skills (subdirectories with SKILL.md)
- **`hooks/`** - Event hooks (JSON configuration)
- **`.mcp.json`** - MCP server definitions (optional)

See [CLAUDE.md](./CLAUDE.md) for detailed development guidance.

## Testing Locally

```bash
# Test a specific plugin
claude --plugin-dir ./plugins/codeblend

# Validate plugin structure
claude plugin validate ./plugins/codeblend
```

## License

MIT
