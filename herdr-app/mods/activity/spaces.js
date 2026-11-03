// Spaces, grouped by machine: This Computer, then every ssh machine Herdr knows
// (`hc machine ls`). Each group lists its spaces (and their tabs, folded), the
// folders recently opened there, and has "Open Folder…" (browse the machine's
// folders and start a space there) and "New Terminal". Right-click a space or a
// tab for Herdr's own menu (rename, worktrees, close).
//
// Only a machine's name, host and state are read from `hc machine ls`: its
// target (the ssh command) can hold secrets and is never kept or shown.
import { div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { hc, run, theme, spaces, panes, shared, setShared, openOverlay } from "herdr";
import { iconButton, viewHeader, icon, basename, statusMark, programIcon } from "./common.js";
import { sh } from "./io.js";

const RECENT = "activity.remote.recent";
const FOLDED = "activity.spaces.folded";
const LOCAL = "@local";
const DIRS = 'cd "$1" 2>/dev/null || exit 2; pwd; for p in * .[!.]* ..?*; do [ -d "$p" ] && [ ! -L "$p" ] && printf "%s\\n" "$p"; done | head -n 1000';
// A tab as people know it: its name if someone gave one, else what runs in it
// (the agent first), like Herdr's tab bar.
function tabLabel(tab, all) {
  const mine = all.filter((p) => p.tab === tab.id && p.terminal);
  const lead = mine.find((p) => p.program?.agent) ?? mine.find((p) => p.focused) ?? mine[0];
  return { lead, name: tab.named || !lead ? tab.name : lead.program?.name || tab.name };
}
const tilde = (p) => (p ?? "").replace(/^\/home\/[^/]+(?=\/|$)/, "~").replace(/^\/root(?=\/|$)/, "~");

export default class Spaces {
  init(_p, cx) {
    this.list = []; this.error = null;
    this.tabsOpen = new Set();
    this.browse = null; // { on, path, dirs, loading, error }
    this.pathInput = InputState.new({ placeholder: "/path/to/folder" });
    this.pathInput.on("submit", (_e, cx) => this.go(this.pathInput.value().trim(), cx));
    this.load(cx);
    cx.timer.every(15000, (cx) => this.load(cx));
  }

  load(cx) {
    cx.spawn(async (cx) => {
      const r = await hc(["machine", "ls", "--json"]).catch(() => null);
      try {
        const all = JSON.parse(r?.stdout || "{}").machines ?? [];
        // Keep only what's shown.
        this.list = all.map((m) => ({ name: m.name, host: m.host ?? "", state: m.state ?? "unknown" }));
        this.error = null;
      } catch { this.error = r?.stderr?.trim() || "Cannot list the machines"; }
      cx.notify();
    });
  }

  folded() { return new Set(shared(FOLDED) ?? []); }
  toggleGroup(key) {
    const f = this.folded();
    f.has(key) ? f.delete(key) : f.add(key);
    setShared(FOLDED, [...f]);
  }

  // The folder browser: starts in the home folder there.
  startBrowse(on, cx) {
    this.browse = { on, path: null, dirs: [], loading: true };
    this.go("~", cx);
  }

  go(path, cx) {
    const b = this.browse;
    if (!b || !path) return;
    b.loading = true; b.error = null; cx.notify();
    cx.spawn(async (cx) => {
      const r = await sh(path === "~" ? `cd && ${DIRS.replace('cd "$1" 2>/dev/null || exit 2; ', "")}` : DIRS, [path], { on: b.on ?? undefined }).catch((e) => ({ code: 1, stderr: String(e) }));
      if (this.browse !== b) return;
      b.loading = false;
      if (r.code !== 0) { b.error = r.code === 2 ? `No such folder: ${path}` : r.stderr.trim() || "Cannot list this folder"; cx.notify(); return; }
      const [where, ...dirs] = r.stdout.split("\n").filter(Boolean);
      b.path = where; b.dirs = dirs.sort((x, y) => Number(x.startsWith(".")) - Number(y.startsWith(".")) || x.localeCompare(y));
      this.pathInput.set_value(where);
      cx.notify();
    });
  }

  openFolder(on, folder) {
    const recent = { ...(shared(RECENT) ?? {}) }, key = on ?? LOCAL;
    recent[key] = [folder, ...(recent[key] ?? []).filter((f) => f !== folder)].slice(0, 6);
    setShared(RECENT, recent);
    const existing = spaces().find((s) => (s.machine ?? null) === (on ?? null) && s.folder === folder);
    if (existing) run("space.select", { id: existing.id });
    else run("space.new", { ...(on ? { machine: on } : {}), folder, name: basename(folder) || folder });
    this.browse = null;
  }

  newTerminal(on) { run("space.new", on ? { machine: on, name: on } : {}); }

  // A group's header: This Computer or a machine.
  groupRow(key, m, count, t) {
    const open = !this.folded().has(key), on = m?.name ?? null;
    const color = !m ? null : m.state === "connected" ? t.ansi2 : m.state === "connecting" ? t.blocked : t.ansi1;
    return h_flex().id(`sg-${key}`).h(26).flex_none().pl(6).pr(6).gap(6).items_center().cursor_pointer().hover((s) => s.bg(t.hover))
      .on_click(() => this.toggleGroup(key))
      .child(icon(`chevron-${open ? "down" : "right"}`, 12).text_color(t.dim))
      .child(icon(m ? "server" : "layout-editor", 14).text_color(t.muted))
      .child(div().flex_none().max_w(130).truncate().font_medium().child(m ? m.name : "This Computer"))
      .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(m ? m.host : count ? String(count) : ""))
      .when(Boolean(color), (el) => el.child(div().size(7).rounded_full().flex_none().bg(color).tooltip(m.state)))
      .child(iconButton(`sg-open-${key}`, "folder-open", `Open Folder${m ? ` on ${m.name}` : ""}…`, (_e, cx) => this.startBrowse(on, cx), { size: 20, icon: 13 }))
      .child(iconButton(`sg-term-${key}`, "plus", `New Space${m ? ` on ${m.name}` : ""}`, () => this.newTerminal(on), { size: 20, icon: 13 }));
  }

  spaceRows(s, t) {
    const open = this.tabsOpen.has(s.id), where = s.machine ? null : tilde(s.folder);
    const row = h_flex().id(`ss-${s.id}`).h(26).flex_none().pl(18).pr(8).gap(6).items_center().cursor_pointer()
      .when(s.active, (el) => el.bg(t.selected)).hover((st) => st.bg(t.hover))
      .on_click(() => run("space.select", { id: s.id }))
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        openOverlay({ mod: "menu", kind: "popup", width: 200, height: 260, props: { tab: "space", target: { id: s.id } } });
      })
      .child(div().id(`ss-fold-${s.id}`).size(14).flex_none().flex().items_center().justify_center().rounded(3).hover((st) => st.bg(t.raised))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => { cx.stop_propagation(); open ? this.tabsOpen.delete(s.id) : this.tabsOpen.add(s.id); cx.notify(); })
        .child(icon(`chevron-${open ? "down" : "right"}`, 11).text_color(t.dim)))
      .child(icon(s.active ? "folder-open" : "folder", 13).text_color(s.active ? t.foreground : t.muted))
      .child(div().flex_none().max_w(140).truncate().when(s.active, (el) => el.font_medium()).child(s.name))
      .child(h_flex().flex_1().min_w(0).gap(4).items_center().text_size(11).text_color(t.dim)
        .when(Boolean(s.branch), (el) => el.child(icon("git-branch", 11)).child(div().flex_none().max_w(90).truncate().child(s.branch)))
        .child(div().flex_1().min_w(0).truncate().child(s.branch ? "" : s.folder ? (where ?? s.folder) : "")))
      .child(statusMark(s.status, t))
      .tooltip(`${s.machine ? `${s.machine}:` : ""}${s.folder || "~"} · ${s.tabs.length} tab${s.tabs.length === 1 ? "" : "s"} · right-click for more`);
    if (!open) return [row];
    const ps = panes();
    return [row, ...s.tabs.map((tab) => ({ tab, ...tabLabel(tab, ps) })).map(({ tab, lead, name }) => h_flex().id(`st-${tab.id}`).h(22).flex_none().pl(46).pr(8).gap(6).items_center().cursor_pointer()
      .text_size(12).text_color(tab.active && s.active ? t.foreground : t.muted).hover((st) => st.bg(t.hover))
      .on_click(() => { run("space.select", { id: s.id }); run("tab.select", { id: tab.id }); })
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        openOverlay({ mod: "menu", kind: "popup", width: 200, height: 120, props: { tab: "tab", target: { id: tab.id, space: s.id } } });
      })
      .child(programIcon(lead?.program, 12, t.dim) ?? icon("terminal", 12).text_color(t.dim))
      .child(div().flex_1().min_w(0).truncate().child(name))
      .when(tab.panes > 1, (el) => el.child(div().text_size(10.5).text_color(t.dim).child(`${tab.panes} panes`)))
      .child(statusMark(tab.status, t)))];
  }

  recentRow(on, folder, t) {
    return h_flex().id(`sr-${on ?? LOCAL}-${folder}`).h(22).flex_none().pl(38).pr(8).gap(6).items_center().cursor_pointer().text_color(t.dim)
      .hover((st) => st.bg(t.hover).text_color(t.foreground))
      .on_click(() => this.openFolder(on, folder))
      .child(icon("refresh", 11))
      .child(div().flex_1().min_w(0).truncate().text_size(11.5).child(tilde(folder)))
      .tooltip(`Open ${folder}${on ? ` on ${on}` : ""} again`);
  }

  group(key, m, all, recent, t) {
    const on = m?.name ?? null;
    const mine = all.filter((s) => (s.machine ?? null) === on);
    const rows = [this.groupRow(key, m, mine.length, t)];
    if (this.folded().has(key)) return rows;
    rows.push(...mine.flatMap((s) => this.spaceRows(s, t)));
    const used = new Set(mine.map((s) => s.folder));
    const again = (recent[key] ?? []).filter((f) => !used.has(f)).slice(0, 3);
    rows.push(...again.map((f) => this.recentRow(on, f, t)));
    if (!mine.length && !again.length)
      rows.push(div().pl(38).py(3).text_size(11.5).text_color(t.dim).child("No spaces yet: Open Folder… starts one"));
    return rows;
  }

  browser(t) {
    const b = this.browse;
    const row = (id, label, action, ico = "folder") => h_flex().id(id).h(24).flex_none().px(10).gap(6).items_center().cursor_pointer()
      .hover((s) => s.bg(t.hover)).on_click(action).child(icon(ico, 13).text_color(t.muted)).child(div().flex_1().min_w(0).truncate().child(label));
    const up = b.path && b.path !== "/" ? b.path.replace(/\/[^/]*$/, "") || "/" : null;
    return v_flex().flex_1().min_h(0)
      .child(h_flex().h(30).flex_none().px(10).gap(6).items_center()
        .child(div().flex_1().min_w(0).truncate().text_size(11).font_semibold().text_color(t.muted).child(`OPEN FOLDER ON ${(b.on ?? "this computer").toUpperCase()}`))
        .child(iconButton("rb-x", "x", "Cancel", (_e, cx) => { this.browse = null; cx.notify(); })))
      .child(div().px(10).pb(6).flex_none().child(Input.new(this.pathInput).h(28).px(8).rounded(6).border_1().border_color(t.input).bg(t.background).text_size(12)))
      .child(v_flex().id("rb-list").flex_1().min_h(0).overflow_y_scrollbar()
        .when(Boolean(up), (el) => el.child(row("rb-up", "..", (_e, cx) => this.go(up, cx), "arrow-up")))
        .children(b.dirs.map((d, i) => row(`rb-${i}`, d, (_e, cx) => this.go(`${b.path === "/" ? "" : b.path}/${d}`, cx))))
        .when(b.loading, (el) => el.child(div().px(12).py(6).text_size(12).text_color(t.dim).child("Loading…")))
        .when(Boolean(b.error), (el) => el.child(div().px(12).py(6).text_size(12).text_color(t.ansi1).child(b.error)))
        .when(!b.loading && !b.error && !b.dirs.length, (el) => el.child(div().px(12).py(6).text_size(12).text_color(t.dim).child("No folders inside"))))
      .child(h_flex().flex_none().p(10).gap(8).border_t(1).border_color(t.border)
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(b.path ?? ""))
        .child(div().id("rb-open").px(12).py(4).rounded(5).bg(t.solid).text_color(t.solid_foreground).text_size(12).cursor_pointer()
          .when(!b.path, (el) => el.opacity(0.5))
          .on_click(() => { if (b.path) this.openFolder(b.on, b.path); })
          .child("Open")));
  }

  render(cx) {
    const t = theme(), all = spaces(), recent = shared(RECENT) ?? {};
    // Machines with spaces but missing from the list (still loading) get a group too.
    const machines = [...this.list];
    for (const s of all) if (s.machine && !machines.some((m) => m.name === s.machine)) machines.push({ name: s.machine, host: "", state: "unknown" });
    const body = this.browse ? this.browser(t) : v_flex().id("spaces-list").flex_1().min_h(0).overflow_y_scrollbar().pb(8)
      .children(this.group(LOCAL, null, all, recent, t))
      .children(machines.flatMap((m) => [div().h(1).mx(8).my(4).flex_none().bg(t.border), ...this.group(m.name, m, all, recent, t)]))
      .when(Boolean(this.error), (el) => el.child(div().px(14).py(8).text_size(12).text_color(t.dim).child(this.error)));
    return v_flex().id("activity-spaces").size_full().min_h(0).bg(t.chrome).text_color(t.foreground).text_size(13)
      .child(viewHeader("Spaces", [
        iconButton("sp-new", "plus", "New Space", () => this.newTerminal(null)),
        iconButton("sp-add", "server", "Add Machine…", () => run("mod.open", { name: "machine-add" })),
        iconButton("sp-refresh", "refresh", "Refresh", (_e, cx) => this.load(cx)),
      ]))
      .child(body);
  }
}
