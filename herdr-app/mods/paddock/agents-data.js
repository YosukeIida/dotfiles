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
