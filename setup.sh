#!/usr/bin/env bash

# OpenCode Graphify + CRG Setup — Init Script
# Bootstraps an AI-agent-friendly dev environment for the current repo.
#
# Usage: curl -fsSL "https://raw.githubusercontent.com/.../setup.sh" | bash

set -euo pipefail

# Source shared utilities (local if cloned, otherwise fetch from GitHub)
_TMP_UTILS=$(mktemp)
if ! curl -fsSL "https://raw.githubusercontent.com/DuckKota/OpenCode-Graphify-CRG-Setup/refs/heads/main/scripts/install/_utils.sh" -o "$_TMP_UTILS"
then
    echo "Failed to source _utils.sh."
    rm -f "$_TMP_UTILS"
    exit 1
fi
source "$_TMP_UTILS"
rm -f "$_TMP_UTILS"

function build_ignore_files
{
    _print "Creating .graphifyignore & .code-review-graphignore..."
    cat << 'EOF' | tee "$_INSTALL_DIR/.graphifyignore" "$_INSTALL_DIR/.code-review-graphignore" >/dev/null
node_modules/
dist/
build/
.pnpm-store/
coverage/
*.min.js
*.min.css
*.map
pnpm-lock.yaml
yarn.lock
*.lock
*.log
.env*
graphify-out/
.code-review-graph/
*.example.*
EOF

    _print "Updating the .gitignore..."
    echo "" >> "$_INSTALL_DIR/.gitignore"
    echo "# Ignore OpenCode tooling" >> "$_INSTALL_DIR/.gitignore"
    echo "graphify-out/" >> "$_INSTALL_DIR/.gitignore"
    echo ".code-review-graph/" >> "$_INSTALL_DIR/.gitignore"
    echo ".opencode/" >> "$_INSTALL_DIR/.gitignore"
}

function setup_agents_and_knowledge_graph
{
    _print "Writing knowledge-graph.md..."
    _write_script_to_file "agent_instructions/knowledge-graph.md" "$_INSTALL_DIR/docs/agents/knowledge-graph.md" --overwrite

    _print "Updating AGENTS.md..."
    if [[ -f "$_INSTALL_DIR/AGENTS.md" ]]
    then
        _write_script_to_file "agent_instructions/AGENTS.md" "$_INSTALL_DIR/AGENTS_MD_INSTRUCTIONS" --overwrite
        cat "$_INSTALL_DIR/AGENTS_MD_INSTRUCTIONS" "$_INSTALL_DIR/AGENTS.md" > "$_INSTALL_DIR/AGENTS.md.TMP"
        mv "$_INSTALL_DIR/AGENTS.md.TMP" "$_INSTALL_DIR/AGENTS.md"
        rm "$_INSTALL_DIR/AGENTS_MD_INSTRUCTIONS"
    else
        _write_script_to_file "agent_instructions/AGENTS.md" "$_INSTALL_DIR/AGENTS.md" --overwrite
    fi
}

function write_bootstrap_script
{
    _print "Writing setup bootstrap script..."
    mkdir -p "$_INSTALL_DIR/scripts"
    _write_script_to_file "install/setup-opencode-graphs.sh" "$_INSTALL_DIR/setup-opencode-graphs.sh" --overwrite
    chmod +x "$_INSTALL_DIR/setup-opencode-graphs.sh"
}

# --------
# Main processing

_setup_environment

build_ignore_files
setup_agents_and_knowledge_graph
write_bootstrap_script

if ! curl -fsSL "https://raw.githubusercontent.com/DuckKota/OpenCode-Graphify-CRG-Setup/refs/heads/main/scripts/install/common.sh" | bash
then
    echo "Failed to run common.sh."
    exit 1
fi

echo
_print_box "✓ Setup Complete!" \
  "" \
  "What was installed in the repository:" \
  "  • .graphifyignore & .code-review-graphignore — tool ignore files" \
  "  • AGENTS.md & docs/agents/knowledge-graph.md — agent instructions" \
  "  • setup-opencode-graphs.sh — bootstrap script for fresh clones" \
  "  • .gitignore entries for graph output and .opencode/ directories" \
  "" \
  "Next steps:" \
  "  1. Commit the new/modified files to share AI tooling with your team" \
  "  2. Anyone who clones the repo can run:" \
  "       ./setup-opencode-graphs.sh" \
  "     to set up their local AI tooling."
