import { execFileSync } from "child_process";
import { join } from "path";

class SmartGrepBlock extends Error {}

function queryGraphHook(scriptPath, cmd) {
  try {
    const buf = execFileSync("bash", [scriptPath, cmd], {
      encoding: "utf-8",
      timeout: 6000,
      maxBuffer: 1024 * 1024,
    });
    const raw = buf?.trim();
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    return parsed.hookSpecificOutput || null;
  } catch {
    return null;
  }
}

function applyGraphResult(hook, inject) {
  if (!hook) return;
  if (hook.permissionDecision === "block")
    throw new SmartGrepBlock(hook.permissionDecisionReason || "Blocked");
  if (hook.additionalContext) inject(hook.additionalContext);
}

export const GraphifyPlugin = async ({ directory }) => {
  return {
    "tool.execute.before": async (input, output) => {
      const scriptPath = join(directory, ".opencode/scripts/smart-grep.sh");

      // ── Bash grep interceptor ──
      if (input.tool === "bash") {
        const cmd = output.args?.command || input.input?.command;
        if (!cmd) return;
        if (/--graph-tried|# graph-checked|GRAPH_TRIED=1/.test(cmd)) {
          output.args.command = cmd
            .replace(/--graph-tried\s*/g, "")
            .replace(/# graph-checked\s*/g, "")
            .replace(/GRAPH_TRIED=1\s*/g, "")
            .trim();
          return;
        }

        const hook = queryGraphHook(scriptPath, cmd);
        applyGraphResult(hook, (ctx) => {
          const marker = "SMARTGREP_CTX_" + Date.now();
          output.args.command =
            `cat <<'${marker}'\n${ctx}\n${marker}\n\n${cmd}`;
        });
        return;
      }

      // ── Built-in grep ──
      if (input.tool === "grep") {
        const pattern = output.args?.pattern || input.input?.pattern;
        if (!pattern) return;

        const fakeCmd = `grep -r '${pattern}' .`;
        const hook = queryGraphHook(scriptPath, fakeCmd);
        applyGraphResult(hook, (ctx) => {
          output.args.pattern = `${pattern}\n\n${ctx}`;
        });
        return;
      }
    },
  };
};