// opencode に、Claude Code と同じ agent の文脈を足す。
// - 指示（~/.claude/CLAUDE.md）の `@` の参照先（experience の索引・phrasing）を、session の初回に作って system に足す
// - 送った文で knowledge のノートを引き（claude/hooks/knowledge-recall.py）、その session の system に足し続ける
// 指示の本文は足さない: opencode は ~/.config/opencode/AGENTS.md が無いと ~/.claude/CLAUDE.md を読む。
import { execFileSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dotfiles = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "..", "..");

function run(cmd, args, input = "") {
  try {
    return execFileSync(cmd, args, { input, encoding: "utf8", timeout: 10000, stdio: ["pipe", "pipe", "ignore"] });
  } catch {
    return "";
  }
}

const attachments = new Map();
const recalled = new Map();

export default {
  id: "agent-context",
  setup: async (ctx) => {
    await ctx.session.hook("prompt", async (event) => {
      const sessionID = event.sessionID;
      const prompt = event.prompt?.text;
      if (!sessionID || typeof prompt !== "string" || !prompt) return;
      const out = run(
        "uv",
        ["run", "--quiet", "--no-project", "--script", join(dotfiles, "claude/hooks/knowledge-recall.py")],
        JSON.stringify({ hook_event_name: "UserPromptSubmit", session_id: `opencode-${sessionID}`, prompt }),
      );
      let text = "";
      try {
        text = out ? JSON.parse(out).hookSpecificOutput?.additionalContext ?? "" : "";
      } catch {}
      if (text) recalled.set(sessionID, [...(recalled.get(sessionID) ?? []), text]);
    });

    await ctx.session.hook("context", async (event) => {
      const sessionID = event.sessionID;
      if (!attachments.has(sessionID)) {
        run("bash", [join(dotfiles, "claude/hooks/experience-inject.sh")]);
        attachments.set(
          sessionID,
          run("bash", [join(dotfiles, "agents/render-instructions.sh"), "--attachments-only", join(homedir(), ".claude/CLAUDE.md")]),
        );
      }
      for (const text of [attachments.get(sessionID), ...(recalled.get(sessionID) ?? [])]) {
        if (text) event.system.push({ type: "text", text });
      }
    });
  },
};
