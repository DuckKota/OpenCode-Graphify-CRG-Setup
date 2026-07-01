#!/usr/bin/env bash

# Adaptive graph-first grep interceptor — CRG (SQLite FTS5) + graphify (JSON)
# Decision ladder (first match wins):
#   1. Not a search command              → pass silently
#   2. --graph-tried override            → pass silently
#   3. Non-code target (.md/.json/…)     → pass silently
#   4. Cross-repo abs path:
#      a. Target has CRG or graphify     → query both, show context, allow grep
#      b. No graph in target             → pass silently
#   5. No local graph of either type:
#      a. CRG registered repo match     → show context, allow grep
#      b. Global merged graphify match  → show context, allow grep
#      c. No match                      → pass silently
#   6. Local graph(s) present — session-aware gating:
#      a. First grep + hit              → show result, allow (one-shot lesson)
#      b. First grep + miss             → allow, suggest tool for next time
#      c. Subsequent + hit              → answering deny (result inline, no retry)
#      d. Subsequent + miss             → pass silently
set -uo pipefail

# Accept command as CLI argument
CMD="$1"

function _write_debug
{
    if [ -f "$HOME/.opencode-smart-grep.log" ]
    then
        printf '[%s] smart-grep: %s\n' "$(date '+%H:%M:%S')" "$*" >> "$HOME/.opencode-smart-grep.log"
    fi
}
[ -f "$HOME/.opencode-smart-grep.log" ] && echo "" >> "$HOME/.opencode-smart-grep.log"
_write_debug "Command: $CMD"
_write_debug "Started in $PWD — watching for grep/rg calls"

_PYTHON_EXE=""
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
    elif command -v python >/dev/null 2>&1 && python -c "import json" 2>/devstalled
    then
        _PYTHON_EXE="python"
    fi
fi

_write_debug "Using Python: ${_PYTHON_EXE:-none found} (via ${GRAPHIFY_BIN:-system fallback})"

# ── Tier 1-3: fast exits ──────────────────────────────────────────────────────
case "$CMD" in
    # Search and find tools
    *grep*|*" rg "*|*"   rg "*|*ripgrep*|*" fd "*|*" ack "*|*" ag "*)
        _write_debug "✓ This is a search command — checking further"
        ;;
    *find\ *)
        _write_debug "✓ This is a find command — checking further"
        ;;

    # If it's not a search/find command, exit early
    *)
        _write_debug "✗ Not a search or find command — passing through"
        exit 0
        ;;
esac

case "$CMD" in
    # Skip if already processed
    *--graph-tried*|*"# graph-checked"*|*"GRAPH_TRIED=1"*)
        _write_debug "✗ Already checked (--graph-tried flag set) — passing through"
        exit 0
        ;;
esac

case "$CMD" in
    # Ignored file extensions
    *.md*|*.json*|*.yml*|*.yaml*|*.log*|*.jsonl*|*.txt*|*.csv*)
        _write_debug "✗ Target is a non-code file (.md/.json/etc) — passing through"
        exit 0
        ;;
    # Ignored directories
    *node_modules*|*"/.git/"*|*/dist/*|*/build/*|*/.next/*|*/__pycache__/*)
        _write_debug "✗ Target is in an ignored directory (node_modules/.git/etc) — passing through"
        exit 0
        ;;
esac

function json_esc
{
    $_PYTHON_EXE -c "import json,sys; print(json.dumps(sys.stdin.read())[1:-1])"
}

# ── CRG: SQLite FTS5 query (sub-ms) ──────────────────────────────────────────
function query_crg
{
    local db="$1" pat="$2"
    $_PYTHON_EXE - "$pat" "$db" <<'PYEOF' 2>/dev/null
import sqlite3, sys, os
pat, db = sys.argv[1], sys.argv[2]
if not os.path.exists(db): sys.exit(0)
try:
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=3)
    rows = c.execute(
        "SELECT n.kind, n.name, n.file_path, n.line_start "
        "FROM nodes_fts f JOIN nodes n ON n.id=f.rowid WHERE nodes_fts MATCH ? LIMIT 5",
        (pat,)).fetchall()
    if not rows:
        rows = c.execute(
            "SELECT kind, name, file_path, line_start FROM nodes WHERE name LIKE ? LIMIT 5",
            (f'%{pat}%',)).fetchall()
    c.close()
    for kind, name, path, line in rows:
        print(f'[crg] {kind}  {name}  →  {path}:{line}')
except: pass
PYEOF
}

# ── graphify: JSON in-memory search (~5ms for 4k nodes) ──────────────────────
function query_graphify
{
    local json="$1" pat="$2"
    $_PYTHON_EXE - "$pat" "$json" <<'PYEOF' 2>/dev/null
import json, sys, os
pat_low, gfile = sys.argv[1].lower(), sys.argv[2]
if not os.path.exists(gfile): sys.exit(0)
try:
    g = json.load(open(gfile))
    results = []
    for n in g.get('nodes', []):
        label = n.get('label', '')
        if pat_low in label.lower() or pat_low in n.get('id', '').lower():
            src = n.get('source_file', '')
            loc = n.get('source_location', '') or n.get('line', '')
            kind = n.get('file_type', 'node')
            community = n.get('community', '')
            results.append(f'[graphify] {kind}  {label}  →  {src}:{loc}  (community {community})')
    for r in results[:5]: print(r)
except: pass
PYEOF
}

# ── Query both graphs at a given root ─────────────────────────────────────────
function query_at_root
{
    local root="$1" pat="$2"
    local out=""
    local crg_db="${root}/.code-review-graph/graph.db"
    local gfy_json="${root}/graphify-out/graph.json"
    if [[ -f "$crg_db" ]]
    then
        out+=$(query_crg "$crg_db" "$pat")$'\n'
    fi
    if [[ -f "$gfy_json" ]]
    then
        out+=$(query_graphify "$gfy_json" "$pat")$'\n'
    fi
    printf '%s' "$out" | sed '/^[[:space:]]*$/d'
}

# ── Walk up to nearest repo with any graph ────────────────────────────────────
function find_graph_root
{
    local d="$1"; [ ! -d "$d" ] && d=$(dirname "$d")
    while [ "$d" != "/" ] && [ "$d" != "$HOME" ]
    do
        if [[ -f "$d/.code-review-graph/graph.db" ]] || [[ -f "$d/graphify-out/graph.json" ]]
        then
            echo "$d"
            return
        fi
        d=$(dirname "$d")
    done
}

# ── Extract search pattern ────────────────────────────────────────────────────
PATTERN=$(printf '%s' "$CMD" | $_PYTHON_EXE -c "
import sys, shlex
cmd = sys.stdin.read().strip()
try: parts = shlex.split(cmd)
except: parts = cmd.split()
bases = {'grep','rg','ripgrep','egrep','fgrep','ag','ack','fd'}
idx = next((i for i,p in enumerate(parts) if p.rsplit('/',1)[-1] in bases), -1)
if idx < 0: sys.exit(0)
for p in parts[idx+1:]:
    if not p.startswith('-') and '/' not in p and len(p) > 2: print(p[:60]); break
" 2>/dev/null || echo "")
_write_debug "Searching the knowledge graph for '${PATTERN}'"

# ── Tier 4: cross-repo detection ──────────────────────────────────────────────
TARGET=$(printf '%s' "$CMD" | $_PYTHON_EXE -c "
import sys, shlex, os
try: parts = shlex.split(sys.stdin.read())
except: parts = sys.stdin.read().split()
cwd = os.getcwd()
for p in parts:
    if p.startswith('/') and not p.startswith('-') and not p.startswith(cwd): print(p); break
" 2>/dev/null || echo "")

if [[ -n "$TARGET" ]]
then
    _write_debug "Cross-repo grep targeting ${TARGET}"
    ROOT=$(find_graph_root "$TARGET")
    if [[ -n "$ROOT" ]] && [[ -n "$PATTERN" ]]
    then
      _write_debug "Found graph data in ${ROOT}"
      RESULT=$(query_at_root "$ROOT" "$PATTERN")
      if [[ -n "$RESULT" ]]
      then
        _write_debug "✓ Hit in cross-repo graph — showing result before letting grep through"
        MSG="Cross-repo graph hit (${ROOT##*/}) for '${PATTERN}':\n${RESULT}\n\nGrep proceeding — result shown as context. Open a session in that repo for deeper analysis."
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' \
          "$(printf '%s' "$MSG" | json_esc)"
      else
        _write_debug "No graph matches in the target repo — letting grep through"
      fi
    else
      _write_debug "No graph data found in target repo — letting grep through"
    fi
    exit 0  # always allow cross-repo grep
fi

# ── Local graph detection ─────────────────────────────────────────────────────
HAVE_CRG=0; HAVE_GFY=0
if [[ -f ".code-review-graph/graph.db" ]]
then
    HAVE_CRG=1
fi
if [[ -f "graphify-out/graph.json" ]]
then
    HAVE_GFY=1
fi

if [[ "$HAVE_CRG" = "1" ]] && [[ "$HAVE_GFY" = "1" ]]
then
  _write_debug "✓ Both CRG and graphify graphs are available here"
elif [[ "$HAVE_CRG" = "1" ]]
then
  _write_debug "✓ CRG graph is available here"
elif [[ "$HAVE_GFY" = "1" ]]
then
  _write_debug "✓ Graphify graph is available here"
else
  _write_debug "No local graph data found"
fi

# ── Tier 5: no local graph → registry + global merged graph ───────────────────
if [[ "$HAVE_CRG" = "0" ]] && [[ "$HAVE_GFY" = "0" ]]
then
    _write_debug "No local graph — checking if any other repo knows about this"
    EXTRA_RESULT=""

    # 5a: CRG multi-repo registry
    if command -v code-review-graph >/dev/null 2>&1 && [[ -n "$PATTERN" ]] && (( "${#PATTERN}" > 2 ))
    then
        REG=$(code-review-graph repos 2>/dev/null | $_PYTHON_EXE - "$PATTERN" <<'PYEOF' 2>/dev/null
import sys, os, sqlite3
pat = sys.argv[1]; results = []
for line in sys.stdin.read().strip().splitlines():
    for token in line.split():
        if not token.startswith('/'): continue
        db = f"{token}/.code-review-graph/graph.db"
        if not os.path.exists(db): continue
        try:
            c = sqlite3.connect(f'file:{db}?mode=ro', uri=True, timeout=2)
            rows = c.execute(
                'SELECT n.kind, n.name, n.file_path, n.line_start '
                'FROM nodes_fts f JOIN nodes n ON n.id=f.rowid WHERE nodes_fts MATCH ? LIMIT 3',
                (pat,)).fetchall()
            c.close()
            for kind, name, fp, ln in rows:
                results.append(f'[crg:{token}] {kind}  {name}  →  {fp}:{ln}')
        except: pass
for r in results[:5]: print(r)
PYEOF
        )
        if [[ -n "$REG" ]]
        then
            EXTRA_RESULT+="$REG"$'\n'
        fi
    fi

    # 5b: global merged graphify (~/obsidian-vault/merged-graph.json)
    GLOBAL_GFY="${HOME}/obsidian-vault/merged-graph.json"
    if [[ -f "$GLOBAL_GFY" ]] && [[ -n "$PATTERN" ]] && (( "${#PATTERN}" > 2 ))
    then
        GRESULT=$(query_graphify "$GLOBAL_GFY" "$PATTERN")
        if [[ -n "$GRESULT" ]]
        then
            EXTRA_RESULT+="$GRESULT"$'\n'
        fi
    fi

    if [[ -n "$EXTRA_RESULT" ]]
    then
        _write_debug "✓ Found matches in another repo's graph — showing before grep"
        CLEAN=$(printf '%s' "$EXTRA_RESULT" | sed '/^[[:space:]]*$/d')
        MSG="No local graph. Sibling/global graph hit for '${PATTERN}':\n${CLEAN}\n\nGrep proceeding. Open a session in the repo shown above for deeper analysis."
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' \
          "$(printf '%s' "$MSG" | json_esc)"
    else
        _write_debug "No matches anywhere — letting grep through"
    fi
    exit 0
fi

# ── Tier 6: local graph(s) — session-aware gating ─────────────────────────────
KEY=$(printf '%s' "${PWD}" | md5 2>/dev/null || printf '%s' "${PWD}" | md5sum 2>/dev/null | cut -c1-8)
DIR="${HOME}/.cache/opencode-graph-hook"; mkdir -p "$DIR"
SLOT="${DIR}/first-grep-${KEY}-$(date +%Y%m%d_%H)"
_write_debug "Session slot: first-grep-${KEY} (tracks whether this is a repeat grep in this hour)"

RESULT=""
if [[ -n "$PATTERN" ]] && (( "${#PATTERN}" > 2 ))
then
    RESULT=$(query_at_root "." "$PATTERN")
fi

# Adaptive tool hint — shows MCP tool (CRG) or graphify CLI or both
TOOL_HINT=""
if [[ "$HAVE_CRG" = "1" ]]
then
    TOOL_HINT="semantic_search_nodes_tool(query='${PATTERN}')"
fi
if [[ "$HAVE_GFY" = "1" ]]
then
    GFY_HINT="graphify query '${PATTERN}' --graph graphify-out/graph.json"
    TOOL_HINT="${TOOL_HINT:+${TOOL_HINT} or }${GFY_HINT}"
fi

if [[ ! -f "$SLOT" ]]
then
    _write_debug "First grep in this session hour — one-shot lesson mode"
    touch "$SLOT"
    if [[ -n "$RESULT" ]]
    then
        _write_debug "✓ Graph has answers — showing them now (one-shot, future greps for this will be blocked)"
        MSG="Graph pre-answer for '${PATTERN}':\n${RESULT}\n\nIf enough — skip the grep. Running this time (one-shot). Future code-path greps denied when graph answers. Override: --graph-tried."
    else
        _write_debug "✗ No graph answers — letting grep through and suggesting a tool for next time"
        MSG="No graph hit for '${PATTERN}' — grep proceeding (one-shot). Next time try: ${TOOL_HINT}. Append --graph-tried to bypass permanently."
    fi
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' \
      "$(printf '%s' "$MSG" | json_esc)"
    exit 0
fi

# Subsequent greps: answering deny if graph hits, else pass
if [[ -n "$RESULT" ]]
then
    _write_debug "✗ Already showed graph answers for this — blocking the repeat grep"
    MSG="Graph has this — no retry needed:\n\n${RESULT}\n\nUse: ${TOOL_HINT}. Append --graph-tried to override."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"%s"}}' \
      "$(printf '%s' "$MSG" | json_esc)"
    exit 0
fi

_write_debug "✗ No graph answers — passing through"
printf '[graph-hook] no result for "%s"\n' "$PATTERN" >> "${DIR}/bypass.log"
exit 0