#!/usr/bin/env bash

# OpenCode AI Runtime Setup — Common Logic
# Configures local-only artifacts: .opencode/ config, git hooks, smart-grep plugin, graphs.
# Run via bootstrap script on every fresh clone, or called by setup.sh during init.

set -euo pipefail

# Source shared utilities (local if cloned, otherwise fetch from GitHub)
_TMP_UTILS=$(mktemp)
if ! curl -fsSL "https://raw.githubusercontent.com/DuckKota/OpenCode-Graphify-CRG-Setup/refs/heads/main/scripts/install/_utils.sh" -o "$_TMP_UTILS"
then
    echo "Failed to source _utils.sh."
    rm -f "$TEMP_UTILS"
    exit 1
fi
source "$_TMP_UTILS"
rm -f "$_TMP_UTILS"

function update_opencode_json
{
    _print "Updating .opencode/opencode.json to use CRG MCP..."
    mkdir -p "$_INSTALL_DIR/.opencode"
    export _CRG_GIT_ROOT=$_INSTALL_DIR
    (cd $_INSTALL_DIR && "$_PYTHON_EXE" -c "import json, os

file_path = '.opencode/opencode.json'

if not os.path.exists(file_path):
    with open(file_path, 'w') as f:
        f.write('{}')

try:
    with open(file_path, 'r+') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = {}

        payload = {
            'code-review-graph': {
                'type': 'local',
                'command': ['uvx', 'code-review-graph', 'serve'],
                'cwd': os.environ.get('_CRG_GIT_ROOT'),
                'enabled': True,
                'environment': {
                    'CRG_TOOLS': 'semantic_search_nodes_tool,query_graph_tool,get_impact_radius_tool,traverse_graph_tool,list_communities_tool,get_community_tool,get_review_context_tool,list_graph_stats_tool'
                }
            }
        }

        if 'mcp' not in data:
            data['mcp'] = payload
        else:
            if 'code-review-graph' not in data['mcp']:
                data['mcp']['code-review-graph'] = payload['code-review-graph']
            else:
                pass

        f.seek(0)
        json.dump(data, f, indent=4)
        f.truncate()
        print('Successfully updated .opencode/opencode.json config.')
except Exception as e:
    print(f'Error updating file: {e}')
")
}

function install_smart_grep_plugin
{
    _print "Installing Smart Grep plugin..."

    (cd $_INSTALL_DIR && "$_PYTHON_EXE" -c "import json, os

file_path = '.opencode/opencode.json'

try:
    with open(file_path, 'r+') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = {}

        data.setdefault('plugin', []).append('.opencode/plugins/smart-grep.js')

        f.seek(0)
        json.dump(data, f, indent=4)
        f.truncate()
        print('Successfully updated .opencode/opencode.json config.')
except Exception as e:
    print(f'Error updating file: {e}')
")

    _write_script_to_file "smart-grep-plugin/smart-grep.js" "$_INSTALL_DIR/.opencode/plugins/smart-grep.js" --overwrite
    _write_script_to_file "smart-grep-plugin/smart-grep.sh" "$_INSTALL_DIR/.opencode/scripts/smart-grep.sh" --overwrite
    chmod +x "$_INSTALL_DIR/.opencode/scripts/smart-grep.sh"
}

function setup_git_hooks
{
    if [[ ! -f "$_INSTALL_DIR/.git/hooks/post-commit" ]]
    then
        echo "#!/bin/sh" > "$_INSTALL_DIR/.git/hooks/post-commit"
    fi
    if [[ ! -f "$_INSTALL_DIR/.git/hooks/post-checkout" ]]
    then
        echo "#!/bin/sh" > "$_INSTALL_DIR/.git/hooks/post-checkout"
    fi

    _print "Setting up automatic Graphify updates..."
    (cd $_INSTALL_DIR && graphify hook install)

    _print "Setting up automatic CRG updates..."
    if grep -q "# code-review-graph-hook-start" "$_INSTALL_DIR/.git/hooks/post-commit"
    then
        echo "post-commit: already installed at $_INSTALL_DIR/.git/hooks/post-commit"
    else
        cat << 'EOF' >> $_INSTALL_DIR/.git/hooks/post-commit

# code-review-graph-hook-start
if command -v code-review-graph >/dev/null 2>&1
then
    _CRG_LOG="${HOME}/.cache/code-review-graph-update.log"
    mkdir -p "$(dirname "$_CRG_LOG")"
    echo "[CRG hook] launching background update (log: $_CRG_LOG)"
    nohup sh -c 'code-review-graph update' > "$_CRG_LOG" 2>&1 < /dev/null &
    disown 2>/dev/null || true
fi
# code-review-graph-hook-end
EOF
        echo "post-commit: appended to existing post-commit hook at $_INSTALL_DIR/.git/hooks/post-commit"
    fi

    if grep -q "# code-review-graph-hook-start" "$_INSTALL_DIR/.git/hooks/post-checkout"
    then
        echo "post-checkout: already installed at $_INSTALL_DIR/.git/hooks/post-checkout"
    else
        cat << 'EOF' >> $_INSTALL_DIR/.git/hooks/post-checkout

# code-review-graph-hook-start
if command -v code-review-graph >/dev/null 2>&1
then
    _CRG_LOG="${HOME}/.cache/code-review-graph-update.log"
    mkdir -p "$(dirname "$_CRG_LOG")"
    echo "[CRG hook] launching background build (log: $_CRG_LOG)"
    nohup sh -c 'code-review-graph build' > "$_CRG_LOG" 2>&1 < /dev/null &
    disown 2>/dev/null || true
fi
# code-review-graph-hook-end
EOF
        echo "post-checkout: appended to existing post-checkout hook at $_INSTALL_DIR/.git/hooks/post-checkout"
    fi

    chmod 755 "$_INSTALL_DIR/.git/hooks/post-commit"
    chmod 755 "$_INSTALL_DIR/.git/hooks/post-checkout"
}

function build_graphs
{
    _print "Building the Graphify graph..."
    graphify update "$_INSTALL_DIR"

    _print "Building the CRG graph..."
    code-review-graph build --repo "$_INSTALL_DIR"
}

# --------
# Main processing

_setup_environment

update_opencode_json
install_smart_grep_plugin
setup_git_hooks
build_graphs

echo
_print_box "✓ AI Runtime Configuration Complete!" \
    "" \
    "  • .opencode/opencode.json — CRG MCP server" \
    "  • .git/hooks — auto graph updates" \
    "  • .opencode/plugins/smart-grep.js — graph-first grep" \
    "  • graphify-out/ & .code-review-graph/ — knowledge graphs" \
    "" \
    "Your AI tooling is ready. Open an OpenCode session to start."
