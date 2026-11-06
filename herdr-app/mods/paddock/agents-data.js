// The agent rows' data, apart from drawing: no herdr imports, so node can test it.

export function duration(ms) {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

// Terminals an agent started (`hc run`) have no pane, so agents() leaves them out;
// terminals() names their `parent`. As Herdr's Agents list does: an error counts as
// needing you, and a sub-agent is never done (it reports to its parent).
export function kidStatus(k, listed) {
  const s = listed.get(k.address) ?? k.status;
  return s === "error" ? "blocked" : s === "done" ? "idle" : s;
}

// Live terminals by their parent's address.
export function byParent(all) {
  const kids = new Map();
  for (const k of all) {
    if (!k.parent || k.state !== "live") continue;
    if (!kids.has(k.parent)) kids.set(k.parent, []);
    kids.get(k.parent).push(k);
  }
  return kids;
}

// Sub-agents an agent runs inside itself (Claude Code's, Codex's, Pi's), which have no
// terminal: its hooks put each on the agent's own terminal as a label
// `paddock.sub.<app>.<id>` = {"app", "type", "at", "s"}. Oldest first; a label that
// isn't that shape is skipped, and so is one older than 12 hours (its hooks never saw
// it end: the agent was killed mid-run) when `now` is given.
export const HOOK_MAX_AGE = 12 * 3600000;
export function hookSubs(labels, now = null) {
  const out = [];
  for (const [k, v] of Object.entries(labels ?? {})) {
    const m = /^paddock\.sub\.([a-z0-9-]+)\.(.+)$/.exec(k);
    if (!m || !v) continue;
    let d;
    try { d = JSON.parse(v); } catch { continue; }
    if (!d || typeof d !== "object") continue;
    const h = { id: m[2], app: typeof d.app === "string" ? d.app : m[1], type: typeof d.type === "string" ? d.type : "", at: Number.isFinite(d.at) ? d.at : 0 };
    if (now !== null && h.at && now - h.at >= HOOK_MAX_AGE) continue;
    out.push(h);
  }
  return out.sort((a, b) => a.at - b.at || a.id.localeCompare(b.id));
}

// Whether a hook sub-agent's app is its parent agent's: "claude" under Claude Code
// ("claude-code"), "codex" under Codex. Another app's leftover label (an earlier agent in
// the same terminal) doesn't show under this one.
export const sameApp = (parentApp, app) => {
  const p = String(parentApp ?? "").toLowerCase(), a = String(app ?? "").toLowerCase();
  return Boolean(p && a) && (p === a || p.startsWith(`${a}-`) || p.startsWith(a));
};

// One tree under an agent: its terminal sub-agents (tree()), then its hook sub-agents
// (hookSubs()), with the lines redrawn so only the very last top-level row ends it.
export function joinSubs(treeItems, hooks) {
  const items = treeItems.map((s) => ({ ...s, lines: [...s.lines] }));
  if (hooks.length) {
    for (const s of items) {
      if (s.lines[0] === "└") s.lines[0] = "├";
      else if (s.lines.length > 1 && s.lines[0] === "") s.lines[0] = "│";
    }
  }
  return [...items, ...hooks.map((h, i) => ({ hook: h, lines: [i === hooks.length - 1 ? "└" : "├"] }))];
}

// The sub-agents of `addr`, depth first, each with the tree lines before it.
// `kids`: byParent's map. A terminal seen twice (a loop) isn't followed again.
export function tree(kids, addr, lead = [], seen = new Set([addr])) {
  const mine = (kids.get(addr) ?? []).filter((k) => !seen.has(k.address));
  return mine.flatMap((k, i) => {
    const last = i === mine.length - 1;
    seen.add(k.address);
    return [{ k, lines: [...lead, last ? "└" : "├"] }, ...tree(kids, k.address, [...lead, last ? "" : "│"], seen)];
  });
}

// An agent started by another agent that also has a pane: drawn under that parent
// with the tree lines, not on its own as well. `parentOf`: address → parent address.
export function nested(a, parentOf, listed) {
  return listed.has(parentOf.get(a.address));
}

// What a named terminal is for: the role a herdr-agent-team seat carries
// (label `herdr-team.role`), else its name.
export function role(term) {
  return term?.labels?.["herdr-team.role"] || term?.name || "";
}
