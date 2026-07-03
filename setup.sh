#!/usr/bin/env bash

# OpenCode Graphify + CRG Setup
# Bootstraps an AI-agent-friendly dev environment for the current repo.
# It validates prerequisites, builds Graphify + code-review-graph (CRG) knowledge graphs,
# writes AGENTS.md instructions, configures CRG as an OpenCode MCP server, installs git
# hooks for automatic graph updates on commit/checkout, and deploys a Smart Grep plugin
# that routes grep calls through graph tools before falling back to line scanning.

# Known bugs...
# I'm not convinced that we're correctly capturing the grep/glob commands.
#   I'll just need to track the log file ~/.opencode-smart-grep.log to monitor for odd behavior

set -euo pipefail

function _get_script_content
{
    local relative_path="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local local_path="$script_dir/scripts/$relative_path"

    if [[ -f "$local_path" ]]
    then
        cat "$local_path"
        return 0
    fi

    # If not found locally, try to fetch from GitHub
    local github_url="https://raw.githubusercontent.com/DuckKota/OpenCode-Graphify-CRG-Setup/refs/heads/main/scripts/$relative_path"
    local content
    if content=$(curl -fsSL "$github_url")
    then
        echo "$content"
        return 0
    else
        echo "Error: Failed to download script '$relative_path' from GitHub." >&2
        return 1
    fi
}

function _write_script_to_file
{
    if (( $# < 2 ))
    then
        echo "Error: Missing arguments." >&2
        echo "Usage: _write_script_to_file <relative_script_path> <target_file_path> [--append|--overwrite]" >&2
        exit 1
    fi

    # Read in user inputs
    local relative_path="$1"
    local target_path="$2"
    local mode="${3:-'--overwrite'}"

    # Get script content
    local content
    if ! content=$(_get_script_content "$relative_path")
    then
        # Error is printed by _get_script_content
        exit 1
    fi
    # Ensure the target file directory exists
    local target_dir
    target_dir="$(dirname $target_path)"
    if [[ ! -d "$target_dir" ]]
    then
        mkdir -p "$target_dir"
    fi

    # Write based on the mode
    case "$mode" in
        --append|-a)
            echo "$content" >> "$target_path"
            ;;
        --overwrite|-o)
            echo "$content" > "$target_path"
            ;;
        *)
            echo "Error: Invalid mode '$mode'. Use '--overwrite' (-o) or '--append' (-a)." >&2
            exit 1
            ;;
    esac
}

function _print
{
    printf '\n\e[1m[%s] OpenCode Graphify + CRG Setup >> %s\e[0m\n' "$(date '+%H:%M:%S')" "$*"
}

function _print_box
{
    # If no arguments are provided, do nothing
    (( $# == 0 )) && return

    local max_len=0
    local line

    # First pass: Find the longest line to determine the box width
    for line in "$@"
    do
        if (( ${#line} > $max_len ))
        then
            max_len=${#line}
        fi
    done

    # Create the top and bottom borders based on the max length
    # Adding 4 to account for the padding and side borders
    local border_len=$((max_len + 4))
    local top_border="╔$(printf '═%.0s' $(seq 1 $((border_len - 2))))╗"
    local bottom_border="╚$(printf '═%.0s' $(seq 1 $((border_len - 2))))╝"

    # Print the box
    echo "$top_border"
    for line in "$@"
    do
        # Calculate how much padding this specific line needs to align right
        local pad_len=$((max_len - ${#line}))
        local padding=$(printf '%*s' $pad_len "")
        echo "║ ${line}${padding} ║"
    done
    echo "$bottom_border"
}

# Hardened function to determine if the target directory is inside a Git repository
function _is_git_project
{
    local target_dir="$1"
    
    if command -v git >/dev/null 2>&1
    then
        # Run git from the perspective of the target directory
        git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
        return $?
    fi
    
    return 1
}

function _set_python_exe
{
    # Resolve via the graphify launcher on PATH (shebang probe).
    GRAPHIFY_BIN=$(command -v graphify 2>/dev/null)
    if [ -n "$GRAPHIFY_BIN" ]
    then
        case "$GRAPHIFY_BIN" in
            *.exe) _SHEBANG="" ;;
            *)     _SHEBANG=$(head -1 "$GRAPHIFY_BIN" | sed 's/^#![[:space:]]*//') ;;
        esac
        case "$_SHEBANG" in
            */env\ *) _PYTHON_EXE="${_SHEBANG#*/env }" ;;
            *)        _PYTHON_EXE="$_SHEBANG" ;;
        esac
        # Allowlist: only keep characters valid in a filesystem path to prevent
        # injection if the shebang contains shell metacharacters.
        case "$_PYTHON_EXE" in
            *[!a-zA-Z0-9/_.@-]*) _PYTHON_EXE="" ;;
        esac
        if [ -n "$_PYTHON_EXE" ] && ! "$_PYTHON_EXE" -c "import json" 2>/dev/null
        then
            _PYTHON_EXE=""
        fi
    fi

    # Last resort: try python3 / python (works for system/venv installs on PATH).
    if [ -z "$_PYTHON_EXE" ]
    then
        if command -v python3 >/dev/null 2>&1 && python3 -c "import json" 2>/dev/null
        then
            _PYTHON_EXE="python3"
        elif command -v python >/dev/null 2>&1 && python -c "import json" 2>/dev/null
        then
            _PYTHON_EXE="python"
        fi
    fi
}

# Function to validate prerequisites
function validate_prerequisites
{
    # Ensure that Graphify is installed
    if ! command -v graphify >/dev/null 2>&1
    then
        echo "Error: 'graphify' is not installed or not in your PATH." >&2
        echo "See information:"
        echo "    Website: https://graphifylabs.ai/"
        echo "    GitHub: https://github.com/safishamsi/graphify"
        exit 1
    fi

    # Ensure that code-review-graph is installed
    if ! command -v code-review-graph >/dev/null 2>&1
    then
        echo "Error: 'code-review-graph' is not installed or not in your PATH." >&2
        echo "See information:"
        echo "    Website: https://code-review-graph.com/"
        echo "    GitHub: https://github.com/tirth8205/code-review-graph"
        exit 1
    fi

    # Ensure that Python is installed
    if [[ -z "$_PYTHON_EXE" ]]
    then
        echo "Error: Python is not installed or not in your PATH." >&2
        echo "See information:"
        echo "    Website: https://www.python.org/"
        exit 1
    fi

    # Ensure that OpenCode is installed (warning only)
    if ! command -v opencode >/dev/null 2>&1
    then
        echo "Warning: 'opencode' is not installed or not in your PATH."
        echo "See information:"
        echo "    Website: https://opencode.ai/"
        echo "    GitHub: https://github.com/anomalyco/opencode"
        read -p "Do you want to continue anyway? (y/n): " yn
        if [[ ! "$yn" =~ ^[Yy] ]]
        then
            echo "Exiting..."
            exit 0
        fi
    fi

    # Get the installation root directory.
    # The user must be running in a git project.
    _INSTALL_DIR=$(pwd -P)

    if _is_git_project "$_INSTALL_DIR"
    then
        # Get the absolute, physical path of the Git repository root
        _INSTALL_DIR=$(git -C "$_INSTALL_DIR" rev-parse --show-toplevel 2>/dev/null)
        _INSTALL_DIR=$(cd "$_INSTALL_DIR" && pwd -P)
    else
        echo "Error: This script must be run from within a Git repository." >&2
        echo "Current directory '$(pwd)' is not part of a Git project." >&2
        exit 1
    fi
}

# Function definitions for setup steps
function build_graphs
{
    _print "Building the Graphify graph..."
    graphify update "$_INSTALL_DIR"

    _print "Building the CRG graph..."
    code-review-graph build --repo "$_INSTALL_DIR"
}

# Function to set up AGENTS.md and knowledge-graph.md
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

# Function to update .opencode/opencode.json for CRG MCP
function update_opencode_json
{
    _print "Updating .opencode/opencode.json to use CRG MCP..."
    mkdir -p "$_INSTALL_DIR/.opencode"
    export _CRG_GIT_ROOT=$_INSTALL_DIR
    (cd $_INSTALL_DIR && "$_PYTHON_EXE" -c "import json, os

file_path = '.opencode/opencode.json'

if not os.path.exists(file_path):
    # Seed with an empty JSON object so json.load() works seamlessly
    with open(file_path, 'w') as f:
        f.write('{}')

try:
    with open(file_path, 'r+') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = {}

        # Define the payload safely inside python
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

        # Handle insertion logic
        if 'mcp' not in data:
            data['mcp'] = payload
        else:
            # If mcp exists but code-review-graph doesn't, insert it
            if 'code-review-graph' not in data['mcp']:
                data['mcp']['code-review-graph'] = payload['code-review-graph']
            else:
                # Both exist, do nothing
                sys.exit(0) if 'sys' in locals() else None

        # Rewind and save changes
        f.seek(0)
        json.dump(data, f, indent=4)
        f.truncate()
        print('Successfully updated .opencode/opencode.json config.')
except Exception as e:
    print(f'Error updating file: {e}')
")
}

# Function to set up git hooks for automatic graph updates
function setup_git_hooks
{
    # Create the hook files, starting with a shebang, if they don't exist
    if [[ ! -f "$_INSTALL_DIR/.git/hooks/post-commit" ]]
    then
        echo "#!/bin/sh" > "$_INSTALL_DIR/.git/hooks/post-commit"
    fi
    if [[ ! -f "$_INSTALL_DIR/.git/hooks/post-checkout" ]]
    then
        echo "#!/bin/sh" > "$_INSTALL_DIR/.git/hooks/post-checkout"
    fi

    # Install Graphify hooks
    _print "Setting up automatic Graphify updates..."
    (cd $_INSTALL_DIR && graphify hook install)

    # Install CRG hooks
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

    # Set the hook files to be executable
    chmod 755 "$_INSTALL_DIR/.git/hooks/post-commit"
    chmod 755 "$_INSTALL_DIR/.git/hooks/post-checkout"
}

# Function to install the Smart Grep plugin
function install_smart_grep_plugin
{
    _print "Installing Smart Grep plugin..."
    # This creates a multi-layered approach to tell the agent to use the graph tools.
    #   Layer 1: The AGENTS.md & knowledge-graph.md files
    #   Layer 2: The Smart Grep plugin

    # Update the .opencode/opencode.json plugins array
    (cd $_INSTALL_DIR && "$_PYTHON_EXE" -c "import json, os

file_path = '.opencode/opencode.json'

try:
    with open(file_path, 'r+') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = {}
        
        # This ensures 'plugins' exists as a list, then appends to it
        data.setdefault('plugin', []).append('.opencode/plugins/smart-grep.js')

        # Rewind and save changes
        f.seek(0)
        json.dump(data, f, indent=4)
        f.truncate()
        print('Successfully updated .opencode/opencode.json config.')
except Exception as e:
    print(f'Error updating file: {e}')
")

    # Write the OpenCode plugin files
    _write_script_to_file "smart-grep-plugin/smart-grep.js" "$_INSTALL_DIR/.opencode/plugins/smart-grep.js" --overwrite
    _write_script_to_file "smart-grep-plugin/smart-grep.sh" "$_INSTALL_DIR/.opencode/scripts/smart-grep.sh" --overwrite
    chmod +x "$_INSTALL_DIR/.opencode/scripts/smart-grep.sh"
}

function build_ignore_files
{
    # Create the tool ignore files for Graphify and CRG
    # Creates the files .graphifyignore & .code-review-graphignore
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
    echo "# Inserted by Graphify/CRG setup" >> "$_INSTALL_DIR/.gitignore"
    echo "graphify-out/" >> "$_INSTALL_DIR/.gitignore"
    echo ".code-review-graph/" >> "$_INSTALL_DIR/.gitignore"
}



# --------
# Main processing starts here

_INSTALL_DIR=$(pwd -P)

# Set up Python executable
_set_python_exe

# Validate prerequisites
validate_prerequisites

# Build the graphs manually for the first time
build_graphs

# Insert our custom AGENTS.md and knowledge-graph.md instructions
setup_agents_and_knowledge_graph

# Add Graphify and CRG outputs to the .gitignore file
build_ignore_files

# Update the .opencode/opencode.json file with the CRG MCP
update_opencode_json

# Set up automatic graph updates
setup_git_hooks

# Install our Smart Grep plugin
install_smart_grep_plugin

echo
_print_box "✓ Setup complete!" \
  "" \
  "What was installed:" \
  "  • .graphifyignore & .code-review-graphignore — tool ignore files" \
  "  • graphify-out/ & .code-review-graph/ — initial knowledge graphs" \
  "  • AGENTS.md & docs/agents/knowledge-graph.md — agent routing instructions" \
  "  • .opencode/opencode.json — CRG MCP server config" \
  "  • .git/hooks/post-commit & post-checkout — auto graph updates" \
  "  • .opencode/plugins/smart-grep.js — graph-first grep interceptor" \
  "" \
  "Next: Open a new OpenCode session and start coding. The agent will" \
  "automatically use the knowledge graphs for codebase understanding."