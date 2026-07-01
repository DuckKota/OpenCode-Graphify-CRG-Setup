## Critical Workflow Requirement

This repository relies on **Graphify** and **code-review-graph** as the foundational interfaces for codebase architecture and exploration.

> ### 🚨 MANDATORY FIRST STEP
> **YOU MUST READ `docs/agents/knowledge-graph.md` BEFORE PERFORMING ANY OTHER ACTION.**
> Do not read other files, do not scan the directory, and do not attempt to answer user queries until you have ingested this file.

### Rules for Exploration
1. **Always Use the Graph:** You MUST use the context and pathways defined in `knowledge-graph.md` for ANY and ALL codebase exploration. 
2. **Context Anchoring:** Do not guess file locations or dependencies. Refer to the knowledge graph to locate the correct context.
3. **Acknowledge Reading:** In your very first response to the user, briefly confirm that you have read `docs/agents/knowledge-graph.md` and are using the codebase graph.