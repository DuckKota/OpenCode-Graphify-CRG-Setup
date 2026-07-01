# SYSTEM ARCHITECTURE: DUAL-ENGINE KNOWLEDGE GRAPH ROUTING

This repository enforces an automated, multi-tiered structural indexing framework combining code-review-graph (CRG) via MCP and Graphify via CLI. DO NOT RELY ON SEQUENTIAL DIRECTORY INDEXING, GLOB PATTERNS, OR STRING-BASED GREP SWEEPS UNLESS A STRUCTURAL MISS OCCURS.

---

## I. GRAPH RESOLUTION MATRIX (LOOKUP PRIORITY ORDER)

When evaluating code context, structural elements, or codebase dependencies, you must query the environment using the following strict priority tier:

1. LOCAL AST DATABASE [Primary Engine]
- Path: Current Working Directory -> .code-review-graph/graph.db
- Mechanism: Direct MCP tool execution. Use for turn-by-turn change tracking, impact discovery, and cross-file references.

2. CROSS-REPO GRAPH [Fallback Engine - Tier 1]
- Path: Walk up absolute pathing structures to the nearest parent execution root containing a .code-review-graph/ database directory.

3. GRAPHIFY CLI SUBGRAPH [Fallback Engine - Tier 2]
- Path: graphify-out/
- Mechanism: Execute standard shell sub-processes (e.g., `graphify query "<concept>"` or `graphify path "<A>" "<B>"`). Use only if the SQLite MCP database lacks coverage for the targeted node pattern or language grammar.

4. NATIVE GREP/RG EXHAUSTION PROTOCOL [Absolute Last Resort]
- Execute standard line-scanning tools (grep, rg, glob) ONLY if Tiers 1 through 3 fail to resolve structural coordinates. A PreToolUse hook (`smart-grep-hook.sh`) intercepts explicit grep calls to prioritize graph-routing logic.

---

## II. OPERATIONAL COMMAND MAPPING

| Query Type / Task Intent        | Target Engine  | Specified Operational Tool / Command     |
| :------------------------------ | :------------- | :--------------------------------------- |
| Find function/class X           | CRG (MCP)      | `semantic_search_nodes_tool`             |
| Who calls X?                    | CRG (MCP).     | `query_graph_tool(pattern="callers_of")` |
| What imports file X?            | CRG (MCP).     | `query_graph_tool(pattern="importers")`  |
| Concept graph traversal         | CRG (MCP)      | `traverse_graph_tool(query=X)`           |
| Pre-refactor impact check       | CRG (MCP)      | `get_impact_radius_tool`                 |
| Code review / PR impact         | CRG (MCP)      | `get_review_context_tool`                |
| Module/behavioral clusters      | CRG (MCP)      | `list_communities_tool`                  |
| CRG miss / neighborhood explore | Graphify (CLI) | `graphify query '<term>'`                |
| Exact path A→B hop-by-hop       | Graphify (CLI) | `graphify path '<A>' '<B>'`              |
| String/regex in code body       | Native Shell   | `grep` (Append `--graph-tried`)          |
| Config/JSON/log values          | Native Shell   | `grep`                                   |

---

## III. ASYNC AUTOMATION & PROCESS CONSTRAINTS

All graph updates are detached from individual agent turns and managed strictly via standard Git hooks (`.git/hooks/post-commit` and `.git/hooks/post-checkout`). To maintain local system performance and prevent execution lockups during high-frequency edits, automation is restricted by the following constraints:

- DECOUPLED LIFECYCLE LANES: Graph updates never run synchronously inside your prompt loop. Both `code-review-graph` and `Graphify` compilation loops execute strictly out-of-band as detached, non-blocking background `nohup` processes immediately following a Git commit or branch checkout.
- RESOURCE-GUARDED EXECUTION: Background updates are wrapped in a resource-threshold validation step (`_resources_ok()`). A build will silently skip and queue if the host machine's CPU load exceeds 50% or available system memory drops below 2 GB. This completely prevents background process duplication or system slowdown during rapid-fire commits.
- DE-DUPLICATION & TIMEOUTS: Process-level deduplication (`pgrep` / PID guards) ensures that if a previous graph build is actively running, subsequent hook triggers are discarded to prevent pile-up. All background sync jobs carry a strict 300-second timeout.