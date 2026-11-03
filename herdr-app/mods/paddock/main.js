// Modified from Herdr 0.1.11's shipped "spaces" mod (Apache-2.0, github.com/herdrdev/herdr-app):
// spaces grouped by project (a folder on a machine, a git repo or not), as Orca does,
// with their agents under them. See projects.js and agents.js.
//
// From the shipped mod: worktrees found from git, spaces grouped by machine when
// more than one is known, and after a space's name the repo its first terminal is
// in now, only where unusual: branch, ahead/behind. Click to switch, right-click for
// Herdr's space menu, drag to reorder.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, machines, panes, agents, terminals, run, openOverlay, exec, hc, theme, shared, setShared, watchFolder, window, layout, props, home, readTextFile } from "herdr";
import { agentRow, subRow, tree, byParent } from "./agents.js";
import { groupRows, reposToAdd, projectList, addProject, urgent, fromSpaceFolders, placedOf, placeSpace, reorderProject, naturalProject, prunePlaced } from "./projects.js";
import { Overlay, STORE, store, openMenu, openAdd, newSpaceIn } from "./overlay.js";

// A short stable id for an element from any string (a project's key).
const hash = (s) => [...String(s)].reduce((h, c) => (Math.imul(h, 31) + c.charCodeAt(0)) >>> 0, 2166136261).toString(36);

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

// Where a space is now: its first terminal's live folder, else where it was made.
// `ps`: panes(), read once by the caller (each read copies every pane).
function place(s, ps) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}
const rowHeight = ({ tree }) => (tree ? 28 : 30);
const where = (s, ps) => JSON.stringify([s.machine ?? null, place(s, ps)]);
const base = (path) => path.replace(/\/+$/, "").split("/").pop();
// Changes made outside Herdr (an editor's save, a commit in another app): looked
// for this often, in repos the list shows, while the window is in front.
const FALLBACK = 60000;

// What a stored color name looks like on an avatar (the same in every mod
// that draws space avatars): one strong color per hue, light and dark alike.
const MARK = { ansi6: "#22a99a", ansi3: "#e3814f", ansi4: "#5b8def", ansi5: "#8b7cf6", ansi2: "#3fae6a", ansi1: "#d9649a" };

// A space speaks up only when something in it needs you.
export function glyph(status) {
  return status === "blocked" || status === "done" ? "●" : "·";
}

export function tone(t, status) {
  return t[status] ?? t.unknown;
}

export default class Spaces extends View {
  init(_props, cx) {
    // The same mod draws its popups (a project's menu, its dialogs): see overlay.js.
    if (props()?.role) { this.part = new Overlay(); this.part.init(cx); return; }
    // On first start (no projects kept yet): the folders of the space-folders mod, if it
    // was used here, become projects.
    if (!localStorage.getItem("imported") && !shared(STORE)) {
      localStorage.setItem("imported", "1");
      cx.spawn(async (cx) => {
        const text = await readTextFile(`${home()}/.config/herdr-space-folders.json`).catch(() => null);
        const found = text ? fromSpaceFolders(text, home()) : [];
        if (found.length) setShared(STORE, found.reduce((s, f) => addProject(s, null, f.root, { name: f.name }), store()));
        cx.notify();
      });
    }
    this.git = {}; // where() -> { name, branch, ahead, behind, repo, linked }, null: not a repo
    this.checked = {}; // where() -> when it was last looked at
    this.unsure = new Set(); // where()s git couldn't answer for (a machine away)
    this.pending = new Set(); // where()s to look at next
    this.busy = {}; // pane -> an agent working or a program in front of its shell
    this.ready = {}; // machine -> its layout was readable at the last look
    this.at = {}; // space -> its where() at the last look
    this.watching = new Set(); // local repos' git folders
    // Spaces made while this runs wait (at most a moment) for their git, so a
    // worktree appears under its repo instead of jumping there.
    this.shown = new Set(spaces().map((s) => s.id));
    this.born = {};
    this.pressed = null;
    this.over = null;
    this.machines = [];
    this.folded = new Set(JSON.parse(localStorage.getItem("machines.folded") ?? "[]"));
    this.closed = new Set(JSON.parse(localStorage.getItem("projects.folded") ?? "[]"));
    // A space's agents show under it unless folded here; when each last changed state.
    this.shut = new Set(JSON.parse(localStorage.getItem("agents.folded") ?? "[]"));
    // Spaces pinned to the top of their project (of the loose spaces, out of one).
    this.pins = new Set(JSON.parse(localStorage.getItem("pins") ?? "[]"));
    this.changed = JSON.parse(localStorage.getItem("changed") ?? "{}");
    this.byspace = {};
    this.repoOf = {}; // JSON [machine, project folder] -> { v: in a git repo (null: unknown), at, busy }
    this.repoAsk = new Set();
    // The agents' times, while any is shown.
    cx.timer.every(30000, (cx) => { if (Object.keys(this.byspace).length) cx.notify(); });
    this.projectOf = {}; // space index -> its project's id, or null
    this.naturalOf = {}; // space index -> the project its folder or repo puts it in
    this.overProject = null; // a project (or "out") a dragged space is over
    this.moving = null; // a project being dragged: { key, id, machine, n }
    this.overMove = null;
    this.refreshMachines(cx);
    cx.timer.every(15000, cx => this.refreshMachines(cx));
    // `git status` walks the whole tree, on another machine a process there:
    // only when its answer could have changed (see `due`).
    cx.timer.every(250, (cx) => this.checkNew(cx));
  }

  checkNew(cx) {
    const now = Date.now();
    const sp = spaces();
    for (const s of sp) if (!this.shown.has(s.id)) this.born[s.id] ??= now;
    const due = this.due(now, sp, panes());
    if (due.size) this.refreshGit(due, cx);
    if (sp.some((s) => !this.shown.has(s.id))) cx.notify();
    if (this.repoAsk.size) this.askRepos(cx);
  }

  // Projects' folders: in a git work tree or not ("true" from git). Each folder on
  // its own, so a slow machine doesn't hold up the rest.
  askRepos(cx) {
    const keys = [...this.repoAsk];
    this.repoAsk.clear();
    for (const key of keys) {
      const [on, root] = JSON.parse(key);
      cx.spawn(async (cx) => {
        const r = await exec("git", ["-C", root, "rev-parse", "--is-inside-work-tree"], { on }).catch(() => null);
        const was = this.repoOf[key]?.v ?? null;
        // Unreachable (a machine away): keep what it knew; asked again in a minute.
        this.repoOf[key] = { v: r ? r.code === 0 && r.stdout.trim() === "true" : was, at: Date.now(), failed: !r, busy: false };
        if (!r || this.repoOf[key].v !== was) cx.notify();
      });
    }
  }

  // Places whose git could have changed: new ones (a new space, a cd), where a
  // command or an agent's turn just ended (a checkout, a commit, edits), those on
  // a machine that is back, and repos in view whose fallback is due.
  due(now, sp, ps) {
    // Moved there: what it knew of that place may be old.
    const at = {};
    for (const s of sp) at[s.id] = where(s, ps);
    const keys = new Set(Object.values(at).filter((k) => JSON.parse(k)[1]));
    const due = new Set([...keys].filter((k) => !(k in this.git)));
    for (const [id, k] of Object.entries(at)) if (this.at[id] && this.at[id] !== k && keys.has(k)) due.add(k);
    this.at = at;
    const spaceOf = {};
    for (const s of sp) for (const t of s.tabs ?? []) spaceOf[t.id] = s;
    const busy = {};
    for (const p of ps) {
      if (!p.terminal || !spaceOf[p.tab]) continue;
      busy[p.pane] = p.status === "working" || !(p.program?.shell || p.program?.agent);
      if (this.busy[p.pane] && !busy[p.pane]) this.sameRepo(at[spaceOf[p.tab].id], keys).forEach((k) => due.add(k));
    }
    this.busy = busy;
    for (const m of machines()) {
      const ready = m.layout === "ready";
      if (ready && this.ready[m.name] === false) for (const k of keys) if (JSON.parse(k)[0] === m.name) due.add(k);
      this.ready[m.name] = ready;
    }
    if (window().active) {
      for (const k of keys) {
        const asks = this.git[k] || this.unsure.has(k);
        if (asks && !this.folded.has(JSON.parse(k)[0]) && now - (this.checked[k] ?? 0) > FALLBACK) due.add(k);
      }
    }
    return due;
  }

  // `key` and the other places in its repo (a commit there moves their ahead/behind).
  sameRepo(key, keys) {
    const repo = this.git[key]?.repo;
    return [key, ...(repo ? [...keys].filter((k) => this.git[k]?.repo === repo) : [])];
  }

  refreshMachines(cx) {
    cx.spawn(async cx => {
      try { const r = await hc(["machine", "ls", "--json"]); if (r.code === 0) this.machines = (JSON.parse(r.stdout).machines ?? []).filter((m) => !m.temporary); } catch {}
      cx.notify();
    });
  }

  // One look at a time, each place once however often it was asked for meanwhile.
  refreshGit(keys, cx) {
    for (const k of keys) this.pending.add(k);
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size) {
        const keys = [...this.pending];
        this.pending.clear();
        for (const key of keys) await this.check(key, cx);
      }
      const used = new Set(Object.values(this.git).filter(Boolean).map((g) => JSON.parse(g.repo)).filter(([on]) => !on).map(([, repo]) => repo));
      for (const repo of this.watching) if (!used.has(repo)) this.watching.delete(repo);
      this.refreshing = false;
      cx.notify();
    });
  }

  // One place's git: branch, ahead/behind, its repo.
  async check(key, cx) {
    const [on, cwd] = JSON.parse(key);
    this.checked[key] = Date.now();
    this.unsure.delete(key);
    try {
      // No optional locks: a status that touched the index would wake the watch again.
      // Writes nothing under .git (index lock, fsmonitor cookie): watch() would wake on it.
      const r = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v2", "--branch"], { cwd, on });
      if (r.code !== 0) {
        // Only git's own "no" is remembered as no repo; anything else is asked again.
        if (!/not a git repository/i.test(r.stderr)) this.unsure.add(key);
        this.git[key] = null;
        return;
      }
      // The repo's own .git folder names it; a worktree's top differs from it.
      const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on });
      const common = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on });
      const repo = common.stdout.trim();
      const name = repo.endsWith("/.git") ? base(repo.slice(0, -5)) : base(repo).replace(/\.git$/, "");
      const info = { name, branch: null, ahead: 0, behind: 0, repo: JSON.stringify([on, repo]), linked: repo !== `${top.stdout.trim()}/.git` };
      for (const line of r.stdout.split("\n")) {
        if (line.startsWith("# branch.head ")) info.branch = line.slice(14);
        else if (line.startsWith("# branch.ab ")) {
          const [a, b] = line.slice(12).split(" ");
          info.ahead = Math.abs(parseInt(a, 10)) || 0;
          info.behind = Math.abs(parseInt(b, 10)) || 0;
        }
      }
      this.git[key] = info;
      if (!on) this.watch(repo, cx);
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again later.
      this.git[key] ??= null;
      this.unsure.add(key);
    }
  }

  watch(repo, cx) {
    if (this.watching.has(repo)) return;
    this.watching.add(repo);
    cx.spawn(async (cx) => {
      try {
        while (this.watching.has(repo)) {
          await watchFolder(repo);
          const mine = JSON.stringify([null, repo]);
          if (this.watching.has(repo)) this.refreshGit(Object.keys(this.git).filter((k) => this.git[k]?.repo === mine), cx);
        }
      } catch { this.watching.delete(repo); }
    });
  }

  menu(w) {
    // A popup is as tall as its items; height is only the most.
    openOverlay({ mod: "menu", kind: "popup", width: 200, height: 260, props: { tab: "space", target: { id: w.id } } });
  }

  // Spaces in order, each worktree space moved under its main checkout's.
  ordered() {
    const sp = spaces(), ps = panes();
    const ready = (w) => this.shown.has(w.id) || where(w, ps) in this.git || Date.now() - (this.born[w.id] ??= Date.now()) > 1500;
    for (const w of sp) if (!this.shown.has(w.id) && ready(w)) this.shown.add(w.id);
    const list = sp.map((w, i) => ({ w, i, g: this.git[where(w, ps)] ?? null })).filter((r) => this.shown.has(r.w.id));
    const mains = new Set(list.filter((r) => r.g && !r.g.linked).map((r) => r.g.repo));
    const nested = (r) => r.g?.linked && mains.has(r.g.repo);
    const out = [];
    const placed = new Set(); // repos whose worktrees are listed (under the first of its spaces)
    for (const r of list) {
      if (nested(r)) continue;
      out.push({ ...r, tree: null });
      if (!r.g || r.g.linked || placed.has(r.g.repo)) continue;
      placed.add(r.g.repo);
      const kids = list.filter((k) => nested(k) && k.g.repo === r.g.repo);
      kids.forEach((k, n) => out.push({ ...k, tree: n === kids.length - 1 ? "└─" : "├─" }));
    }
    return out;
  }

  // The rows, under a header per machine once one isn't this computer.
  grouped(t, collapsed) {
    const rows = this.ordered();
    // A space's row, then its agents' (as many elements as that takes).
    const draw = (r) => (collapsed ? [this.compact(r, t)] : [this.row(r, t), ...this.agentRows(r, t)]);
    const remote = [...new Set([...rows.map(r => r.w.machine).filter(Boolean), ...this.machines.map(m => m.name)])].sort();
    const loading = m => {
      const layout = machines().find(k => k.name === m)?.layout;
      return layout === "loading" || (!layout && this.machines.some(k => k.name === m && k.state === "connected"))
        || spaces().some(s => (s.machine ?? null) === m && !this.shown.has(s.id));
    };
    const loadingRow = m => div().id(`machine-loading-${m ?? "local"}`).h(28).flex_none().px(8).text_size(12).text_color(t.dim).child(collapsed ? "…" : "Loading…");
    if (!remote.length) return loading(null) && !rows.length ? [loadingRow(null)] : this.section(rows, draw, t, collapsed, null);
    const machineNames = [null, ...remote];
    return machineNames.flatMap((m) => {
      const mine = rows.filter((r) => (r.w.machine ?? null) === m);
      const machine = this.machines.find(k => k.name === m);
      const connected = !m || machine?.state === "connected";
      const folded = this.folded.has(m);
      const head = h_flex().id(`machine-${m ?? "local"}`).h(26).flex_none().px(collapsed ? 2 : 8).gap(7).items_center().text_size(11).text_color(t.dim)
        .cursor_pointer().hover(s => s.bg(t.hover))
        .on_click((_e, cx) => {
          folded ? this.folded.delete(m) : this.folded.add(m);
          localStorage.setItem("machines.folded", JSON.stringify([...this.folded]));
          cx.notify();
        })
        .child(svg(`mods/workspace-chrome/${m ? "server" : "monitor"}.svg`).size(13).flex_none())
        .when(!collapsed, el => el.child(div().flex_1().truncate().child(m ?? "This computer"))
          .when(!connected, el => el.child(div().flex_none().child((machine?.state ?? "asleep").replace(/_/g, " "))))
          .when(connected, el => el.child(div().id(`machine-project-${m ?? "local"}`).flex_none().px(3).rounded(4).hover(s => s.bg(t.hover).text_color(t.foreground))
            .tooltip("New project")
            .on_click((_e, cx) => { cx.stop_propagation(); openAdd(m); })
            .child(svg("mods/workspace-chrome/folder-plus.svg").size(12))))
          .when(connected, el => el.child(div().id(`machine-add-${m ?? "local"}`).flex_none().px(4).rounded(4).hover(s => s.bg(t.hover).text_color(t.foreground))
            .on_click((_e, cx) => { cx.stop_propagation(); run("space.new", { machine: m ?? "" }); }).child("+")))
          .child(div().size(6).rounded(3).flex_none().bg(connected ? t.ansi2 : t.dim))
          .child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(11).flex_none()));
      const empty = h_flex().id(`machine-new-${m ?? "local"}`).h(28).flex_none().px(8).gap(7).items_center().rounded(7)
        .text_size(12).text_color(t.dim).hover(s => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => run("space.new", { machine: m ?? "" }))
        .child(svg("mods/workspace-chrome/plus.svg").size(12)).when(!collapsed, el => el.child("New space there"));
      const kept = projectList(store(), m).length > 0;
      return [head, ...(folded ? [] : mine.length || kept ? this.section(mine, draw, t, collapsed, m) : [loading(m) ? loadingRow(m) : empty])];
    });
  }

  // One machine's rows: its projects (a header, then their spaces; empty ones too),
  // then the spaces in none; or as Herdr lists them. On the narrow rail, a project
  // is its tile. A repo a space opens in joins the machine's projects by itself.
  section(rows, draw, t, collapsed, machine) {
    const ps = panes();
    const placed = rows.map((r) => ({ ...r, place: place(r.w, ps) }));
    let s = store();
    // Written only when a repo was found, never on a plain render.
    const repos = reposToAdd(s, machine, placed);
    if (repos.length) {
      for (const f of repos) s = addProject(s, machine, f.root, { name: f.name, auto: true });
      setShared(STORE, s);
    }
    const list = projectList(s, machine);
    const { projects, loose } = groupRows(list, placed, placedOf(s, machine));
    for (const r of placed) this.naturalOf[r.i] = naturalProject(list, r)?.id ?? null;
    for (const p of projects) for (const r of p.rows) this.projectOf[r.i] = p.id;
    for (const r of loose) this.projectOf[r.i] = null;
    const inset = (r) => draw({ ...r, tree: null, inset: true });
    const pinned = (list) => [...list.filter((r) => this.pins.has(r.w.id)), ...list.filter((r) => !this.pins.has(r.w.id))];
    return [
      ...projects.flatMap((p, n) => {
        const key = `${machine ?? ""}:${p.id}`;
        return [this.projectHead({ ...p, machine, key, n }, t, collapsed), ...(this.closed.has(key) ? [] : pinned(p.rows).flatMap(collapsed ? draw : inset))];
      }),
      ...pinned(loose).flatMap((r) => draw({ ...r, tree: null, worktree: Boolean(r.g?.linked) })),
    ];
  }

  // A project's tile: its color with a white mark, or plain; a branch for a repo, a folder otherwise.
  // Whether a project's folder is in a git repo, asked of git there once per folder
  // (see checkNew); until it answers, a project found from a repo, or holding a
  // space in one, is taken for one.
  isRepo(p) {
    const key = JSON.stringify([p.machine ?? null, p.root]), k = this.repoOf[key];
    // Asked once, again after 10 minutes (a git init), or a minute after it couldn't be.
    const age = k ? Date.now() - k.at : Infinity;
    if (!k?.busy && (!k || age > (k.failed ? 60000 : 600000))) { this.repoOf[key] = { ...(k ?? { v: null, at: 0 }), busy: true }; this.repoAsk.add(key); }
    return this.repoOf[key].v ?? (p.auto || p.rows.some((r) => r.g));
  }

  projectTile(p, t) {
    const repo = this.isRepo(p);
    return h_flex().size(18).flex_none().rounded(5).items_center().justify_center().bg(t.raised)
      .child(svg(`mods/workspace-chrome/${repo ? "git-branch" : "folder"}.svg`).size(12).text_color(t.muted));
  }

  // A project's row, Orca's way round: chevron, tile, name, then what's inside when
  // folded (a spinner, or a dot when something needs you), + on hover, the count.
  // Click folds it, right-click for its menu, drag it to reorder, drop a space on it
  // to put the space in it. With no space open it's dim.
  projectHead(p, t, collapsed) {
    const id = hash(p.key), closed = this.closed.has(p.key), empty = p.rows.length === 0;
    const status = closed ? urgent(p.rows.map((r) => r.w.status)) : null;
    const tell = status === "blocked" || status === "done";
    const target = this.pressed !== null && this.overProject === p.key;
    const moving = this.moving, aimed = moving && moving.key !== p.key && this.overMove === p.key;
    const head = h_flex().relative().id(`project-${id}`).h(28).flex_none().px(collapsed ? 2 : 8).gap(7).items_center().rounded(7)
      .text_color(t.foreground).cursor_pointer()
      .when(target, (el) => el.bg(t.selected).border_1().border_color(t.accent))
      .when(!target, (el) => el.hover((s) => s.bg(t.hover)))
      .when(Boolean(moving) && moving.key === p.key && this.overMove !== p.key, (el) => el.opacity(0.5))
      .when(Boolean(aimed), (el) => el.child(div().absolute().left(0).right(0).h(2).bg(t.accent)
        .when(moving.n < p.n, (line) => line.bottom(0)).when(moving.n > p.n, (line) => line.top(0))))
      .on_mouse_down("left", () => { this.moving = { key: p.key, id: p.id, machine: p.machine, n: p.n }; this.overMove = p.key; })
      .on_mouse_move((_e, cx) => {
        const space = this.pressed !== null ? spaces()[this.pressed] : null;
        const into = space && (space.machine ?? null) === (p.machine ?? null) ? p.key : null;
        if (this.pressed !== null && this.overProject !== into) { this.overProject = into; this.over = null; cx.notify(); }
        const over = this.moving && (this.moving.machine ?? null) === (p.machine ?? null) ? p.key : null;
        if (this.moving && this.overMove !== over) { this.overMove = over; cx.notify(); }
      })
      .on_mouse_up("left", (_e, cx) => {
        if (this.pressed !== null && this.overProject === p.key) this.place(this.pressed, p.id);
        else if (this.moving && this.moving.key !== p.key && this.overMove === p.key) setShared(STORE, reorderProject(store(), p.machine, this.moving.id, p.id));
        this.endDrag();
        cx.notify();
      })
      .on_click((_e, cx) => {
        closed ? this.closed.delete(p.key) : this.closed.add(p.key);
        localStorage.setItem("projects.folded", JSON.stringify([...this.closed]));
        cx.notify();
      })
      .on_hover((on, cx) => { this.hoveredProject = on ? p.key : this.hoveredProject === p.key ? null : this.hoveredProject; cx.notify(); })
      .on_mouse_down("right", () => openMenu(p.machine, p.id));
    if (collapsed) return head.justify_center().tooltip(p.name).child(this.projectTile(p, t));
    return head
      .child(svg(`mods/workspace-chrome/chevron-${closed ? "right" : "down"}.svg`).size(11).flex_none().text_color(t.dim))
      .child(this.projectTile(p, t))
      .child(div().flex_1().min_w(0).truncate().font_medium().text_color(empty ? t.muted : t.foreground).child(p.name))
      .when(closed && status === "working", (el) => el.child(svg("mods/workspace-chrome/spinner.svg").size(11).flex_none().text_color(t.working).spin(900)))
      .when(closed && tell, (el) => el.child(div().flex_none().text_color(tone(t, status)).child(glyph(status))))
      .when(this.hoveredProject === p.key, (el) => el.child(div().id(`project-add-${id}`).flex_none().px(4).rounded(4).text_color(t.dim)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .tooltip("New space here")
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => { cx.stop_propagation(); newSpaceIn(p, p.machine); })
        .child("+")))
      .child(div().flex_none().text_size(11.5).text_color(t.dim).child(String(p.rows.length)));
  }

  // A space dragged into a project (`id`), or out of its own (null).
  place(index, id) {
    const s = spaces()[index];
    if (!s) return;
    setShared(STORE, placeSpace(store(), s.machine ?? null, s.id, id, { natural: this.naturalOf[index] ?? null }));
  }

  endDrag() {
    this.pressed = null; this.over = null; this.overProject = null; this.moving = null; this.overMove = null;
  }

  // Only what's unusual, after the name: "herdr \u00b7 spike \u21912 \u21931". The repo or
  // branch goes when the name already says it (a worktree is named after its branch),
  // and master/main go: nearly every space is on one.
  gitTail(g, tree, name, t) {
    const raw = g.branch ?? "detached";
    const same = (a) => a.toLowerCase() === name.toLowerCase();
    const branch = same(raw) || raw === "master" || raw === "main" ? "" : raw;
    const repo = tree || same(g.name) ? "" : g.name;
    const where = [repo, branch].filter(Boolean).join(" \u00b7 ");
    return h_flex()
      .flex_1()
      .min_w(0)
      .gap(5)
      .justify_end()
      .items_center()
      .text_size(11.5)
      .text_color(t.dim)
      .when(Boolean(where), (el) => el.child(div().min_w(0).truncate().child(where)))
      .when(g.ahead > 0, (el) => el.child(div().flex_none().text_color(t.ansi2).child(`\u2191${g.ahead}`)))
      .when(g.behind > 0, (el) => el.child(div().flex_none().text_color(t.ansi1).child(`\u2193${g.behind}`)));
  }

  row({ w, i, g, tree, inset, worktree }, t) {
    const on = w.active;
    return v_flex()
      .relative()
      .id(`space-${w.id}`)
      .px(8)
      .h(rowHeight({ tree }))
      .flex_none()
      .justify_center()
      .rounded(8)
      .when(on, (el) => el.bg(t.selected))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .when(this.pressed === i && this.over !== i, (el) => el.opacity(0.5))
      .when(this.pressed !== null && this.over === i && this.pressed !== i, (el) => el.child(
        div().absolute().left(0).right(0).h(2).bg(t.accent)
          .when(this.pressed < i, line => line.bottom(0))
          .when(this.pressed > i, line => line.top(0)),
      ))
      .on_mouse_down("left", () => {
        this.moving = null;
        this.overMove = null;
        this.pressed = i;
        this.over = i;
      })
      .on_mouse_move((_e, cx) => {
        const source = spaces()[this.pressed];
        const over = source && (source.machine ?? null) === (w.machine ?? null) ? i : null;
        if (this.pressed !== null && (this.over !== over || this.overProject !== null)) {
          this.over = over;
          this.overProject = null;
          cx.notify();
        }
      })
      .on_mouse_up("left", (_e, cx) => {
        const from = this.pressed;
        const over = this.over;
        this.endDrag();
        if (from !== null && over === i && from !== i) {
          // Dropped on a space in another project (or in none): it joins that one too.
          if ((this.projectOf[from] ?? null) !== (this.projectOf[i] ?? null)) this.place(from, this.projectOf[i] ?? null);
          run("space.move", { id: spaces()[from].id, index: i + 1 });
        } else if (from === i) run("space.select", { id: w.id });
        cx.notify();
      })
      .on_hover((on, cx) => { this.hoveredSpace = on ? w.id : this.hoveredSpace === w.id ? null : this.hoveredSpace; cx.notify(); })
      .on_mouse_down("right", () => this.menu(w))
      .child(
        h_flex()
          .gap(9)
          .items_center()
          .when(Boolean(inset), el => el.pl(18))
          .when(Boolean(tree), el => el.pl(22))
          .child(this.agentChevron(w, t))
          .when(Boolean(tree), el => el.child(svg("mods/workspace-chrome/branch.svg").size(13).text_color(t.dim)))
          // A space's tile, as a project's: a window split in panes (Lucide's panels-top-left),
          // or a branch for a worktree.
          .when(!tree, el => el.child(h_flex().size(18).flex_none().rounded(5).bg(t.raised).items_center().justify_center()
            .child(svg(worktree ? "mods/workspace-chrome/git-branch.svg" : "mods/paddock/icons/panels-top-left.svg").size(12).text_color(t.muted))))
          .child(div().flex_shrink(0).max_w(150).truncate().text_color(t.foreground).child(w.name))
          .child(g ? this.gitTail(g, tree, w.name, t) : div().flex_1())
          .child(this.agentStatus(w, t))
          .child(this.pinButton(w, t)),
      );
  }

  // At a space row's right end: a pin, always when pinned, on hover otherwise.
  pinButton(w, t) {
    const on = this.pins.has(w.id);
    if (!on && this.hoveredSpace !== w.id) return div();
    return div().id(`space-pin-${w.id}`).flex_none().p(2).rounded(4).text_color(on ? t.muted : t.dim).cursor_pointer()
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .tooltip(on ? "Unpin" : "Pin to the top of its project")
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_mouse_up("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => {
        cx.stop_propagation();
        on ? this.pins.delete(w.id) : this.pins.add(w.id);
        localStorage.setItem("pins", JSON.stringify([...this.pins]));
        cx.notify();
      })
      .child(svg("mods/workspace-chrome/pin.svg").size(12));
  }

  // ---- agents under their space ----

  // Each space's agents, and when each last changed state (kept, as the Agents list does).
  readAgents() {
    const now = Date.now(), by = {}, list = agents();
    let dirty = false;
    // Live terminals by parent, for sub-agents.
    this.kids = byParent(terminals());
    this.listed = new Map(list.map((a) => [a.address, a.status]));
    for (const a of list) {
      (by[a.space] ??= []).push(a);
      const s = a.status === "done" ? "idle" : a.status;
      if (this.changed[a.address]?.s !== s) { this.changed[a.address] = { s, at: now }; dirty = true; }
    }
    // As the Agents list does: forget agents gone for 30 days.
    for (const [k, c] of Object.entries(this.changed)) if (!this.listed.has(k) && now - c.at > 30 * 86400000) { delete this.changed[k]; dirty = true; }
    if (dirty) localStorage.setItem("changed", JSON.stringify(this.changed));
    this.byspace = by;
    this.prune();
  }

  // Pins, folds and drags of spaces that are gone, as the Agents list prunes its pins:
  // only for a machine some of whose spaces are listed (so not while one is loading or
  // away), so a space id never inherits another's.
  prune() {
    const sp = spaces(), ids = new Set(sp.map((s) => s.id));
    const heard = new Set(sp.map((s) => s.machine ?? null));
    const machineOf = (id) => (id.includes("/") ? id.split("/")[0] : null);
    const gone = (id) => heard.has(machineOf(id)) && !ids.has(id);
    for (const [set, name] of [[this.pins, "pins"], [this.shut, "agents.folded"]]) {
      const old = [...set].filter(gone);
      if (old.length) { old.forEach((id) => set.delete(id)); localStorage.setItem(name, JSON.stringify([...set])); }
    }
    // prunePlaced hands back the same store when nothing goes: written only on a change.
    const before = store();
    let s = before;
    for (const m of heard) s = prunePlaced(s, m, ids);
    if (s !== before) setShared(STORE, s);
  }

  agentRows({ w, inset }, t) {
    const list = this.byspace[w.id] ?? [];
    if (!list.length || this.shut.has(w.id)) return [];
    const now = Date.now();
    // Each agent, then the sub-agents it started under it.
    return list.flatMap((a) => [
      agentRow(a, t, { inset, since: this.changed[a.address]?.at ?? 0, now }),
      ...tree(this.kids ?? new Map(), a.address).map((s) => subRow(s, t, { inset, listed: this.listed })),
    ]);
  }

  // Before a space's tile, as on a project's row: a chevron folding its agents (an
  // empty slot when it has none, so the rows line up).
  agentChevron(w, t) {
    const list = this.byspace[w.id] ?? [];
    if (!list.length) return div().w(11).flex_none();
    const shut = this.shut.has(w.id);
    return div().id(`space-agents-${w.id}`).flex_none().rounded(3).cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .tooltip(shut ? `Show its ${list.length > 1 ? `${list.length} agents` : "agent"}` : "Hide its agents")
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_mouse_up("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => {
        cx.stop_propagation();
        shut ? this.shut.delete(w.id) : this.shut.add(w.id);
        localStorage.setItem("agents.folded", JSON.stringify([...this.shut]));
        cx.notify();
      })
      .child(svg(`mods/workspace-chrome/chevron-${shut ? "right" : "down"}.svg`).size(11).text_color(t.dim));
  }

  // At a space row's right end while its agents are folded, as a folded project
  // shows it: a spinner while one works, a dot when one needs you or is done.
  agentStatus(w, t) {
    const list = this.byspace[w.id] ?? [];
    if (!list.length || !this.shut.has(w.id)) return div();
    const status = urgent(list.map((a) => a.status));
    if (status === "working") return svg("mods/workspace-chrome/spinner.svg").size(11).flex_none().text_color(t.working).spin(900);
    if (status === "blocked" || status === "done") return div().flex_none().text_color(tone(t, status)).child(glyph(status));
    return div();
  }

  compact({ w, i }, t) {
    return h_flex()
      .id(`space-${w.id}`)
      .h(26)
      .flex_none()
      .justify_center()
      .gap(4)
      .when(w.active, (el) => el.bg(t.raised))
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("space.select", { id: w.id }))
      .child(div().text_color(w.active ? t.foreground : t.muted).child(String(i + 1)))
      .child(div().text_color(tone(t, w.status)).child(glyph(w.status)));
  }

  render(cx) {
    if (this.part) return this.part.render(cx);
    this.readAgents();
    const t = theme();
    const collapsed = narrow();
    const palette = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];
    const sp = spaces();
    const ids = new Set(sp.map(p => p.id));
    const kept = Object.fromEntries(Object.entries(shared("space.colors") ?? {}).filter(([id]) => ids.has(id)));
    let changed = Object.keys(kept).length !== Object.keys(shared("space.colors") ?? {}).length;
    for (const p of sp) {
      if (kept[p.id] || p.name === "~") continue;
      const uses = c => Object.values(kept).filter(v => v === c).length;
      kept[p.id] = palette.reduce((best, c) => uses(c) < uses(best) ? c : best);
      changed = true;
    }
    if (changed) setShared("space.colors", kept);
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).pl(16).pr(10).items_center().justify_between().text_size(11.5).text_color(t.dim)
        .when(!collapsed, el => el.child("Spaces"))
        .child(h_flex().flex_none().items_center()
          .when(!collapsed, el => el.child(div().id("project-new").size(26).flex_none().flex().items_center().justify_center().rounded(6)
            .hover(s => s.bg(t.hover).text_color(t.foreground))
            .tooltip("New project: a folder on this computer")
            .on_click(() => openAdd(null))
            .child(svg("mods/workspace-chrome/folder-plus.svg").size(14))))
          .child(div().id("space-new").size(26).flex_none().flex().items_center().justify_center().rounded(6).hover(s => s.bg(t.hover).text_color(t.foreground))
            .on_click(() => run("space.new")).child(svg("mods/workspace-chrome/plus.svg").size(14)))))
      .child(v_flex().flex_1().min_h(0).px(8).pb(14).overflow_y_scrollbar().mode("always")
        // Released on the drop zone: out of its project. Anywhere else: nothing.
        .on_mouse_up("left", (_e, cx) => {
          if (this.pressed !== null && this.overProject === "out") this.place(this.pressed, null);
          this.endDrag();
          cx.notify();
        })
        .children(this.grouped(t, collapsed))
        .when(!collapsed && this.pressed !== null && Boolean(this.projectOf[this.pressed]), (el) => el.child(
          div().id("project-out").mt(6).h(34).flex_none().flex().items_center().justify_center().rounded(8).border_1().border_dashed()
            .border_color(this.overProject === "out" ? t.accent : t.border).text_size(12).text_color(this.overProject === "out" ? t.foreground : t.dim)
            .on_mouse_move((_e, cx) => { if (this.overProject !== "out") { this.overProject = "out"; this.over = null; cx.notify(); } })
            .child("Drop here to take it out of its project"))));
  }
}
