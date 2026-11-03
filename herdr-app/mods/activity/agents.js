// Agents: the coding agents running now, then the sessions they left behind.
//
// RUNNING: Herdr's live agents (agents()) with their status (and for how long),
// the conversation's title and model when the session file is found (same agent,
// same folder, the newest one), and where they run. Click: focus its pane.
//
// HISTORY: the sessions of the open workspace only: Claude Code, Codex, pi, omp
// and opencode sessions whose folder is inside the active space's folder, read on
// the space's machine (see sessions.js), newest first. Each shows its title (or
// first prompt), age, agent, model, branch. Click: resume it in a new tab of the
// space, in the session's folder; Shift+click: fork it (when the agent can). A
// session that is running now focuses its pane instead.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, panes, spaces, terminals, run, theme } from "herdr";
import { iconButton, viewHeader, icon, basename, statusMark, programIcon, location } from "./common.js";
import { loadSessions, AGENTS, ago } from "./sessions.js";

const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").trim();
// Which session store a live agent writes to, from its app / program names.
const kindOf = (a) => {
  const words = `${a.app ?? ""} ${a.program?.key ?? ""} ${a.program?.name ?? ""}`.toLowerCase().split(/[^a-z0-9]+/);
  return ["claude", "codex", "opencode", "omp", "pi"].find((k) => words.includes(k)) ?? (words.some((w) => w.startsWith("claude")) ? "claude" : null);
};
const shortModel = (m) => (m ?? "").replace(/^claude-/, "");
const plural = (n, w) => `${n} ${w}${n === 1 ? "" : "s"}`;

export default class Agents {
  init(_p, cx) {
    this.cache = new Map(); // machine ("" = this one) -> { key, list, at, loading, error }
    cx.timer.every(5000, (cx) => this.refresh(cx, false));
  }

  // The folder whose history is shown: the active space's, else the focused one.
  folder() { return spaces().find((s) => s.active)?.folder || location()?.cwd || null; }

  // Reads sessions on the machines in view: the workspace folder on its machine,
  // plus the folders live agents run in (for their titles). Every 20 s here, 45 s
  // over ssh, and at once when the folder (or the set of agent folders) changes.
  refresh(cx, force) {
    const want = new Map([[this.machine() ?? "", { folder: this.folder(), extra: new Set() }]]);
    const ps = panes();
    for (const a of agents()) {
      const cwd = kindOf(a) && ps.find((p) => p.pane === a.pane)?.cwd;
      if (!cwd) continue;
      const m = this.machineOf(a) ?? "";
      if (!want.has(m)) want.set(m, { folder: null, extra: new Set() });
      want.get(m).extra.add(cwd);
    }
    for (const [m, { folder, extra }] of want) {
      const ex = [...extra].sort(), key = JSON.stringify([folder, ex]);
      const c = this.cache.get(m) ?? { key: null, list: [], at: 0, loading: false, error: null };
      this.cache.set(m, c);
      if (c.loading || (!force && c.key === key && Date.now() - c.at < (m ? 45000 : 20000))) continue;
      c.loading = true;
      cx.spawn(async (cx) => {
        await cx.sleep(0);
        try { c.list = await loadSessions(m || null, folder, ex, 60); c.error = null; }
        catch (e) { c.error = String(e?.message ?? e); }
        c.loading = false; c.at = Date.now(); c.key = key;
        cx.notify();
      });
    }
  }

  machine() { return spaces().find((s) => s.active)?.machine ?? null; }
  machineOf(a) {
    const s = spaces().find((x) => x.id === a.space);
    return s?.machine ?? (a.address.includes("/") ? a.address.split("/")[0] : null);
  }

  // Live agents, each with the session it's most likely running (or null).
  live() {
    const ps = panes(), kids = new Set(terminals().filter((k) => k.parent).map((k) => k.address));
    const taken = new Set();
    return agents().filter((a) => !kids.has(a.address)).map((a) => {
      const pane = ps.find((p) => p.pane === a.pane), kind = kindOf(a), on = this.machineOf(a);
      let session = null;
      if (kind && pane?.cwd) {
        const list = this.cache.get(on ?? "")?.list ?? [];
        session = list.find((s) => s.agent === kind && s.cwd === pane.cwd && !taken.has(s.id)) ?? null;
        if (session) taken.add(session.id);
      }
      return { a, pane, kind, on, session };
    });
  }

  resume(s, fork) {
    const space = spaces().find((x) => x.active);
    if (!space) return;
    const info = AGENTS[s.agent];
    const argv = (fork && info.fork ? info.fork : info.resume)(s.id);
    const name = (s.title || s.preview || "").slice(0, 28) || undefined;
    run("tab.new", { space: space.id, folder: s.cwd, argv, ...(name ? { name } : {}) });
  }

  liveRow(x, t) {
    const { a, session, on } = x;
    const tab = spaces().find((s) => s.id === a.space)?.tabs.find((tb) => tb.id === a.tab);
    const since = a.status === "working" && tab?.working_since ? ` ${ago(tab.working_since)}` : "";
    const state = a.status === "working" ? `working${since}` : a.status === "blocked" ? "needs you" : a.status === "done" ? "done" : "idle";
    const termTitle = clean(a.title);
    const title = session?.title || (termTitle && termTitle !== a.program?.name ? termTitle : "") || session?.last || session?.preview || a.program?.name || "Agent";
    const where = `${on ? `${on}: ` : ""}${a.space_name} › ${a.tab_name}`;
    const meta = [state, shortModel(session?.model), where].filter(Boolean).join(" · ");
    return v_flex().id(`al-${a.address}`).flex_none().mx(4).px(8).py(5).gap(1).rounded(7).cursor_pointer()
      .when(a.focused, (el) => el.bg(t.selected)).hover((s) => s.bg(t.hover))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .child(h_flex().gap(7).items_center()
        .child(programIcon(a.program, 14, t.muted) ?? icon("bot", 14).text_color(t.muted))
        .child(div().flex_1().min_w(0).truncate().child(title))
        .child(statusMark(a.status, t)))
      .child(div().pl(21).truncate().text_size(11).text_color(a.status === "blocked" ? t.blocked : t.dim).child(meta))
      .tooltip(session?.last ? `Last prompt: ${session.last}` : where);
  }

  historyRow(s, liveBy, folder, t, i) {
    const info = AGENTS[s.agent], running = liveBy.get(s.id);
    const title = s.title || s.preview || s.last || "(untitled)";
    const meta = [ago(s.updated), info.name, shortModel(s.model), s.branch].filter(Boolean).join(" · ");
    // A session started in a subfolder of the workspace names that subfolder.
    const sub = folder && s.cwd !== folder && s.cwd.startsWith(folder + "/") ? s.cwd.slice(folder.length + 1) : "";
    return v_flex().id(`ah-${s.agent}-${s.id}-${i}`).flex_none().mx(4).px(8).py(5).gap(1).rounded(7).cursor_pointer().hover((st) => st.bg(t.hover))
      .on_click((e) => running ? run("pane.focus", { pane: running.a.pane }) : this.resume(s, Boolean(e?.modifiers?.shift)))
      .child(h_flex().gap(7).items_center()
        .child(programIcon(info, 14, t.muted))
        .child(div().flex_1().min_w(0).truncate().child(title))
        .when(Boolean(running), (el) => el.child(statusMark(running.a.status, t))))
      .child(h_flex().pl(21).gap(4).min_w(0).text_size(11).text_color(t.dim)
        .child(div().min_w(0).truncate().child(meta))
        .when(sub, (el) => el.child(div().flex_none().text_color(t.muted).child(`· ${sub}`))))
      .tooltip(running ? "Running: click to go to it"
        : `${s.cwd}${s.last && s.last !== title ? `\nLast prompt: ${s.last}` : ""}\nClick: resume in a new tab${info.fork ? " · Shift+click: fork" : ""}`);
  }

  section(label, right, t) {
    return h_flex().h(26).flex_none().pl(14).pr(8).mt(4).gap(6).items_center()
      .child(div().flex_1().text_size(11).font_semibold().text_color(t.muted).child(label))
      .children(right);
  }

  render(cx) {
    this.refresh(cx, false);
    const t = theme(), live = this.live(), on = this.machine(), folder = this.folder();
    const cache = this.cache.get(on ?? "");
    const fresh = Boolean(cache?.key) && JSON.parse(cache.key)[0] === folder; // read for this folder
    const shown = fresh ? cache.list.filter((s) => s.here) : [];
    const liveBy = new Map(live.filter((x) => x.session && (x.on ?? null) === on).map((x) => [x.session.id, x]));
    const note = (text, color) => div().px(14).py(6).text_size(12).text_color(color ?? t.dim).child(text);
    const where = folder ? `${on ? `${on}: ` : ""}${folder}` : "";

    return v_flex().id("activity-agents").size_full().min_h(0).bg(t.chrome).text_color(t.foreground).text_size(12.5)
      .child(viewHeader("Agents", [
        iconButton("ag-refresh", "refresh", "Reload sessions", (_e, cx) => this.refresh(cx, true)),
      ]))
      .child(v_flex().id("agents-list").flex_1().min_h(0).overflow_y_scrollbar().pb(8)
        .child(this.section(`RUNNING · ${live.length}`, [], t))
        .children(live.map((x) => this.liveRow(x, t)))
        .when(!live.length, (el) => el.child(note("No agents running. Start one from a terminal (claude, codex, pi, opencode, …).")))
        .child(this.section(`HISTORY · ${folder ? (basename(folder) || folder).toUpperCase() : "NO FOLDER"}`, cache?.loading ? [div().text_size(10.5).text_color(t.dim).child("reading…")] : [], t)
          .id("ag-history-head").tooltip(where || "Open a folder in a space to see its sessions"))
        .children(shown.map((s, i) => this.historyRow(s, liveBy, folder, t, i)))
        .when(!folder, (el) => el.child(note("This space has no folder.")))
        .when(Boolean(folder) && !fresh, (el) => el.child(note("Loading…")))
        .when(Boolean(cache?.error), (el) => el.child(note(cache.error, t.blocked)))
        .when(Boolean(folder) && fresh && !cache.error && !shown.length, (el) => el.child(note(`No agent sessions in ${basename(folder) || folder} yet.`))))
      .child(div().flex_none().px(14).py(4).border_t(1).border_color(t.border).text_size(10.5).text_color(t.dim)
        .child(`${plural(shown.length, "session")} · click resumes in a new tab · Shift+click forks`));
  }
}
