// Paddock's Pi extension: puts each subagent pi-subagents runs on Pi's own herdr-core
// terminal as a label, so the sidebar can list it under Pi, as subagents.sh does for
// Claude Code and Codex.
//   paddock.sub.pi.<run>[-<n>] = {"app":"pi","type":<agent>,"at":<ms>,"s":<session>,"r":<root run>}
// Background runs come from pi-subagents' events (subagent:async-started, a workflow's
// leaves each with their own; subagent:async-complete and subagent:process-terminal end
// them), foreground ones from the subagent tool's progress. A new session keeps only the
// labels of runs pi-subagents still reports running; quitting removes them all.
// It reads nothing else, uses no network, and runs `hc label` and `hc get`. Inside a
// subagent (PI_SUBAGENT_CHILD=1) or outside a Herdr terminal it does nothing.
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";

const PREFIX = "paddock.sub.pi.";
const word = (s: unknown, n: number) => String(s ?? "").replace(/[^A-Za-z0-9_-]/g, "").slice(0, n);
const typeOf = (s: unknown) => String(s ?? "").replace(/[^A-Za-z0-9_:. -]/g, "").slice(0, 48);

function hc(args: string[]): Promise<string> {
  return new Promise((resolve) => {
    execFile("hc", args, { timeout: 5000, windowsHide: true }, (err, out) => resolve(err ? "" : String(out)));
  });
}

export default function (pi: any) {
  const term = process.env.HC_TERMINAL_ID;
  if (!term || process.env.PI_SUBAGENT_CHILD === "1") return;

  let session = "";
  const rows = new Map<string, string>(); // label -> value we want
  let applied = new Map<string, string>(); // label -> value on the terminal
  const fg = new Map<string, Set<string>>(); // foreground tool call -> its labels
  const firstSeen = new Map<string, number>();

  // Writes the difference, one `hc label` at a time; a change meanwhile runs again.
  let running: Promise<void> | null = null, again = false;
  function flush(): Promise<void> {
    if (running) { again = true; return running; }
    running = (async () => {
      do {
        again = false;
        const pairs: string[] = [];
        for (const [k, v] of rows) if (applied.get(k) !== v) pairs.push(`${k}=${v}`);
        for (const k of applied.keys()) if (!rows.has(k)) pairs.push(`${k}=`);
        if (!pairs.length) continue;
        const next = new Map(rows);
        await hc(["label", term!, ...pairs]);
        applied = next;
      } while (again);
    })().finally(() => { running = null; });
    return running;
  }

  const value = (type: unknown, at: number, root: string) =>
    JSON.stringify({ app: "pi", type: typeOf(type), at, s: session, r: root });
  const ofRun = (k: string, run: string) => k === PREFIX + run || k.startsWith(`${PREFIX}${run}-`);
  function end(run: string) {
    if (!run) return;
    for (const [k, v] of [...rows]) {
      let root = "";
      try { root = String(JSON.parse(v).r ?? ""); } catch {}
      if (ofRun(k, run) || root === run) rows.delete(k);
    }
    void flush();
  }

  // Asks pi-subagents for its status; null when it doesn't answer. It answers only after
  // its own session_start, so ask again each second for up to 20 seconds.
  async function status(): Promise<any> {
    for (let i = 0; i < 20; i++) {
      const data = await ask(1000);
      if (data) return data;
      await new Promise((r) => setTimeout(r, 1000));
    }
    return null;
  }
  function ask(ms: number): Promise<any> {
    return new Promise((resolve) => {
      const requestId = randomUUID();
      let off: any;
      const timer = setTimeout(() => { if (typeof off === "function") off(); resolve(null); }, ms);
      off = pi.events.on(`subagents:rpc:v1:reply:${requestId}`, (reply: any) => {
        clearTimeout(timer);
        if (typeof off === "function") off();
        resolve(reply?.success ? reply.data : null);
      });
      pi.events.emit("subagents:rpc:v1:request", { version: 1, requestId, method: "status", params: {} });
    });
  }

  pi.events.on("subagent:async-started", (d: any) => {
    const id = word(d?.id, 40);
    if (!id || d?.mode === "workflow") return; // a workflow's leaves start on their own
    const root = word(d?.parentWorkflowRunId ?? d?.parentRunId, 40) || id;
    const agents: unknown[] = Array.isArray(d?.agents) && d.agents.length ? d.agents : [d?.agent];
    const now = Date.now();
    agents.forEach((a, i) => rows.set(PREFIX + (agents.length > 1 ? `${id}-${i}` : id), value(a, now, root)));
    void flush();
  });
  pi.events.on("subagent:async-complete", (d: any) => end(word(d?.runId ?? d?.id, 40)));
  pi.events.on("subagent:process-terminal", (d: any) => end(word(d?.runId, 40)));

  pi.on("tool_execution_update", (e: any) => {
    if (e?.toolName !== "subagent") return;
    const d = e.partialResult?.details;
    const run = word(d?.runId, 40);
    if (!run || !Array.isArray(d?.progress)) return;
    const keys = new Set<string>();
    for (const p of d.progress) {
      if (p?.status !== "running") continue;
      const k = `${PREFIX}${run}-${word(p.index, 8)}`;
      if (!firstSeen.has(k)) firstSeen.set(k, Date.now());
      keys.add(k);
      rows.set(k, value(p.agent, firstSeen.get(k)!, run));
    }
    for (const k of fg.get(e.toolCallId) ?? []) if (!keys.has(k)) { rows.delete(k); firstSeen.delete(k); }
    fg.set(e.toolCallId, keys);
    void flush();
  });
  pi.on("tool_execution_end", (e: any) => {
    const keys = fg.get(e?.toolCallId);
    if (!keys) return;
    for (const k of keys) { rows.delete(k); firstSeen.delete(k); }
    fg.delete(e.toolCallId);
    void flush();
  });

  pi.on("session_start", (_e: any, ctx: any) => {
    session = word(ctx?.sessionManager?.getSessionId?.(), 64);
    // Not awaited: Pi waits for each handler, and pi-subagents starts after this one.
    void tidy();
  });
  // What an earlier run left: keep only runs pi-subagents still reports running.
  async function tidy() {
    let labels: Record<string, string> = {};
    try { labels = JSON.parse(await hc(["get", term, "--json"])).labels ?? {}; } catch {}
    applied = new Map(Object.entries(labels).filter(([k]) => k.startsWith(PREFIX)));
    const data = await status();
    const live = new Set<string>(
      (data?.asyncSnapshot?.runs ?? []).filter((r: any) => ["running", "queued", "paused"].includes(r?.state)).map((r: any) => word(r.id, 40)),
    );
    for (const [k, v] of applied) {
      let root = "";
      try { root = String(JSON.parse(v).r ?? ""); } catch {}
      if (!rows.has(k) && root && live.has(root)) rows.set(k, v);
    }
    await flush();
  }
  pi.on("session_shutdown", async (e: any) => {
    if (e?.reason !== "quit") return; // a reload, new, resume or fork starts a session again
    rows.clear();
    fg.clear();
    await flush();
  });
}
