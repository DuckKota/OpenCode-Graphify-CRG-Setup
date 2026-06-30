# OpenCode Graphify + CRG Setup

Bootstraps a Git project by setting up knowledge graphs and supporting configuration.

## Overview

This setup script configures your repository to work optimally with AI coding assistants by:

1. **Building Knowledge Graphs** - Creates structured indexing of your codebase using:
   - [Graphify](https://github.com/safishamsi/graphify) - CLI-based code knowledge graph
   - [Code Review Graph](https://github.com/tirth8205/code-review-graph) - MCP-based code review knowledge graph

2. **Configuring Agent Instructions** - Creates `AGENTS.md` and `docs/agents/knowledge-graph.md` with routing instructions for AI agents to use the knowledge graphs effectively

3. **Setting Up MCP Server** - Configures Code Review Graph as a Model Context Protocol server for OpenCode

4. **Automating Updates** - Installs git hooks that automatically update knowledge graphs on commit/checkout

5. **Enhancing Code Search** - Deploys a "Smart Grep" plugin that routes search queries through the knowledge graphs before falling back to traditional text search

## Prerequisites

Before running the setup script, ensure you have the following installed:

- [Graphify](https://graphifylabs.ai/)
- [Code Review Graph](https://code-review-graph.com/)

> [!NOTE]
> While this project doesn't require you to have [OpenCode](https://opencode.ai/) installed, it's an assumed dependency.

## Installation

1. Make sure you're in your Git repository:
   ```bash
   curl -fsSL "https://raw.githubusercontent.com/DuckKota/OpenCode-Graphify-CRG-Setup/refs/heads/main/setup.sh" | bash
   ```
   Fission-AI/OpenSpec/refs/heads/main/AGENTS.md

The script will:
- Validate that all prerequisites are installed
- Build initial knowledge graphs for your codebase
- Create necessary configuration files
- Set up git hooks for automatic updates
- Install the Smart Grep plugin

## How It Works

The system creates a dual-layer knowledge architecture:

1. **Primary Layer** - Fast, structured access via MCP (code-review-graph)
2. **Secondary Layer** - Flexible, file-based access via Graphify (Graphify)
3. **Fallback Layer** - Traditional text search (grep/rg) when graph-based lookup fails

AI agents following the instructions in `AGENTS.md` will:
1. First check the MCP-based Code Review Graph for structural/code relationships
2. Then check the Graphify output for broader code understanding
3. Finally fall back to traditional search methods if needed

## Inspiration

This setup was inspired by the article: 
[Graphify + Code Review Graph: Build a Self-Updating Knowledge Graph for Claude Code and Other AI](https://dev.to/mir_mursalin_ankur/graphify-code-review-graph-build-a-self-updating-knowledge-graph-for-claude-code-and-other-ai-j1m)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.