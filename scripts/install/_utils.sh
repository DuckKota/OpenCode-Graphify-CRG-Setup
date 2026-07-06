#!/usr/bin/env bash

# Shared utilities for OpenCode Graphify + CRG Setup
# Sourced by setup.sh and setup-ai-common.sh

function _print
{
    printf '\n\e[1m[%s] OpenCode Graphify + CRG Setup >> %s\e[0m\n' "$(date '+%H:%M:%S')" "$*"
}

function _print_box
{
    (( $# == 0 )) && return

    local max_len=0
    local line

    for line in "$@"
    do
        if (( ${#line} > $max_len ))
        then
            max_len=${#line}
        fi
    done

    local border_len=$((max_len + 4))
    local top_border="╔$(printf '═%.0s' $(seq 1 $((border_len - 2))))╗"
    local bottom_border="╚$(printf '═%.0s' $(seq 1 $((border_len - 2))))╝"

    echo "$top_border"
    for line in "$@"
    do
        local pad_len=$((max_len - ${#line}))
        local padding=$(printf '%*s' $pad_len "")
        echo "║ ${line}${padding} ║"
    done
    echo "$bottom_border"
}

function _is_git_project
{
    local target_dir="$1"

    if command -v git >/dev/null 2>&1
    then
        git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
        return $?
    fi

    return 1
}

# Fetch script content (local file preferred, fall back to GitHub)
function _get_script_content
{
    local relative_path="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local local_path="$script_dir/../$relative_path"

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
    fi

    echo "Error: Failed to download script '$relative_path'." >&2
    return 1
}

function _write_script_to_file
{
    if (( $# < 2 ))
    then
        echo "Error: Missing arguments." >&2
        exit 1
    fi

    local relative_path="$1"
    local target_path="$2"
    local mode="${3:-'--overwrite'}"

    local content
    if ! content=$(_get_script_content "$relative_path")
    then
        exit 1
    fi

    local target_dir
    target_dir="$(dirname $target_path)"
    if [[ ! -d "$target_dir" ]]
    then
        mkdir -p "$target_dir"
    fi

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

function _set_python_exe
{
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
        case "$_PYTHON_EXE" in
            *[!a-zA-Z0-9/_.@-]*) _PYTHON_EXE="" ;;
        esac
        if [ -n "$_PYTHON_EXE" ] && ! "$_PYTHON_EXE" -c "import json" 2>/dev/null
        then
            _PYTHON_EXE=""
        fi
    fi

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

function _setup_environment
{
    _set_python_exe

    if ! command -v graphify >/dev/null 2>&1
    then
        echo "Error: 'graphify' is not installed or not in your PATH." >&2
        echo "See information:"
        echo "    Website: https://graphifylabs.ai/"
        echo "    GitHub: https://github.com/safishamsi/graphify"
        exit 1
    fi

    if ! command -v code-review-graph >/dev/null 2>&1
    then
        echo "Error: 'code-review-graph' is not installed or not in your PATH." >&2
        echo "See information:"
        echo "    Website: https://code-review-graph.com/"
        echo "    GitHub: https://github.com/tirth8205/code-review-graph"
        exit 1
    fi

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

    local cwd
    cwd=$(pwd -P)

    if _is_git_project "$cwd"
    then
        _INSTALL_DIR=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
        _INSTALL_DIR=$(cd "$_INSTALL_DIR" && pwd -P)
    else
        echo "Error: This script must be run from within a Git repository." >&2
        echo "Current directory '$cwd' is not part of a Git project." >&2
        exit 1
    fi

    if [[ -z "$_PYTHON_EXE" ]]
    then
        echo "Error: Python is not installed or not in your PATH." >&2
        exit 1
    fi
}
