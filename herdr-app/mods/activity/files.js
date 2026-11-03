// Explorer: a lazy file tree of the focused terminal's repo (or folder), with git
// marks. Clicking a file opens it in the editor pane beside the terminal.
// File actions like VS Code's: right-click menu, Ctrl+C / Ctrl+X / Ctrl+V (also
// files copied in a file manager), Delete, F2, drag files in from the desktop.
// They work the same on remote machines (see io.js).
// Built from Herdr's shipped `files` mod, reshaped for the sidebar.
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, watchFolder, theme, focused, shared, setShared, window, openOverlay, run, notify, home } from "herdr";
import { MOD, editorSpec, location, locationKey, basename, openInEditor, iconButton, viewHeader, icon, statusColor, fileImage } from "./common.js";

import { OP, CLIP, request, openDialog, menuHeight } from "./fileops.js";
import { transfer, pasteImage, remove, rename, create, copyFilesToSystem, readSystemClipboard, sameMachine, sh, SEP } from "./io.js";
import { openExternally } from "./viewer.js";

const PER_FOLDER = 500, TOTAL = 5000;
const STATUS = ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=normal"];
// Lists a folder as kind\0name\0 pairs (d: folder, f: anything else), at most 501.
const LIST = 'list() { n=0; for p in "$1"/* "$1"/.[!.]* "$1"/..?*; do [ -e "$p" ] || [ -L "$p" ] || continue; name=${p##*/}; [ "$name" = .git ] && continue; if [ -d "$p" ] && [ ! -L "$p" ]; then kind=d; else kind=f; fi; printf "%s\\0%s\\0" "$kind" "$name"; n=$((n+1)); [ "$n" -gt 500 ] && break; done; test -d "$1"; }';
// The whole Explorer in one go: repo top, then each open folder, then git status, split by SEP.
const REFRESH = `${LIST}
cwd=$1; shift
top=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
root=\${top:-$cwd}
printf '%s' "$top"
for f in "" "$@"; do
  printf '\\n@@HERDR-SEP@@\\n'
  if [ -z "$f" ]; then d=$root; else d=$root/$f; fi
  list "$d" || printf '@@ERR'
done
printf '\\n@@HERDR-SEP@@\\n'
[ -n "$top" ] && git -C "$top" ${STATUS.join(" ")} 2>/dev/null
exit 0`;
const parentOf = (p) => p.replace(/\/[^/]*$/, "");

async function directory(path, on) {
  if (!on && window()?.platform === "windows") {
    const r = await exec("powershell", ["-NoProfile", "-Command", "& { param($p) @(Get-ChildItem -LiteralPath $p -Force -ErrorAction Stop | Where-Object Name -ne '.git' | Select-Object -First 501 | ForEach-Object { @{ name=$_.Name; dir=($_.PSIsContainer -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)) } }) | ConvertTo-Json -Compress } '" + path.replaceAll("'", "''") + "'"]);
    if (r.code !== 0) throw new Error(r.stderr || "Cannot list this folder");
    const result = JSON.parse(r.stdout || "[]");
    return Array.isArray(result) ? result : [result];
  }
  const r = await sh(`${LIST}\nlist "$1"`, [path], { on });
  if (r.code !== 0) throw new Error(r.stderr || "Cannot list this folder");
  return parseList(r.stdout);
}

function parseList(text) {
  const fields = text.split("\0"), out = [];
  for (let i = 0; i + 1 < fields.length; i += 2) out.push({ name: fields[i + 1], dir: fields[i] === "d" });
  return out;
}

export default class Files {
  init(_props, cx) {
    this.saved = new Map();
    this.entries = new Map(); this.folders = new Set(); this.pending = new Set(); this.marks = {}; this.dirty = new Set();
    this.sel = new Set(); this.anchor = null; this.flat = []; this.busy = null; this.note = null;
    this.focus = cx.focus_handle();
    // Requests posted before this view started (shared is persisted) are old news.
    this.opSeen = shared(OP)?.seq ?? null;
    this.refresh(cx);
    // Remote folders can't be watched: asked every 4 s instead (one round trip).
    this.ticks = 0;
    cx.timer.every(4000, (cx) => { if (this.context?.on || ++this.ticks % 3 === 0) this.refresh(cx); });
  }

  current(context) { return this.context === context && locationKey() === context.key; }

  watch(root, cx) {
    if (this.context.on || this.watched === root) return;
    this.watched = root;
    const context = this.context;
    cx.spawn(async (cx) => {
      try { while (this.context === context) { await watchFolder(root); if (this.current(context)) this.refresh(cx); } }
      catch { if (this.context === context) this.watched = null; }
    });
  }

  async loadFolder(path, context) {
    const entries = await directory(path ? `${context.root}/${path}` : context.root, context.on);
    if (!this.current(context) || (path && !this.folders.has(path))) return;
    this.setEntries(path, entries);
  }

  setEntries(path, entries) {
    const used = [...this.entries.entries()].filter(([p]) => p !== path).reduce((n, [, e]) => n + e.length, 0);
    this.entries.set(path, entries.slice(0, Math.max(0, Math.min(PER_FOLDER, TOTAL - used)))
      .sort((a, b) => Number(b.dir) - Number(a.dir) || a.name.localeCompare(b.name)));
    if (entries.length > PER_FOLDER || used + entries.length > TOTAL) this.limited = true;
  }

  refresh(cx) {
    const { cwd, on } = location(), next = locationKey();
    if (next !== this.context?.key) {
      if (this.context) this.saved.set(this.context.key, this.folders);
      this.context = { key: next, cwd, on, root: null };
      this.entries = new Map(); this.folders = new Set(this.saved.get(next)); this.pending = new Set();
      this.marks = {}; this.dirty = new Set(); this.watched = null; this.error = null; this.limited = false; this.loading = false;
      this.sel = new Set(); this.anchor = null;
    }
    if (!cwd || this.loading) return;
    const context = this.context;
    this.loading = true; this.limited = false;
    cx.spawn(async (cx) => {
      try {
        const folders = ["", ...this.folders];
        let repo, lists, status;
        if (!on && window()?.platform === "windows") {
          const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd }).catch(() => null);
          repo = top?.code === 0 ? top.stdout.trim() : null;
          lists = [];
          for (const f of folders) lists.push(await directory(f ? `${repo ?? cwd}/${f}` : repo ?? cwd, null).catch(() => null));
          const st = repo ? await exec("git", [...STATUS], { cwd: repo }).catch(() => null) : null;
          status = st?.code === 0 ? st.stdout : "";
        } else {
          // One round trip for everything: what makes a remote Explorer quick.
          const r = await sh(REFRESH, [cwd, ...folders], { on });
          if (r.code !== 0 && !r.stdout) throw new Error(r.stderr.trim() || "Cannot read this folder");
          const parts = r.stdout.split(SEP);
          repo = parts[0].trim() || null;
          lists = folders.map((_, i) => parts[1 + i] === undefined || parts[1 + i].startsWith("@@ERR") ? null : parseList(parts[1 + i]));
          status = parts[1 + folders.length] ?? "";
        }
        if (!this.current(context)) return;
        context.root = repo ?? cwd; context.repo = repo;
        folders.forEach((f, i) => {
          if (lists[i] === null) { if (f) { this.folders.delete(f); this.entries.delete(f); } else this.entries.set("", []); return; }
          if (f && !this.folders.has(f)) return;
          this.setEntries(f, lists[i]);
        });
        const marks = {}, dirty = new Set();
        for (const entry of status.split("\0").filter(Boolean).slice(0, TOTAL)) {
          const xy = entry.slice(0, 2), rel = entry.slice(3).replace(/\/$/, "");
          marks[rel] = xy === "??" ? "U" : xy.includes("A") ? "A" : xy.includes("U") ? "!" : xy.includes("D") ? "D" : "M";
          const parts = rel.split("/");
          for (let i = 1; i < parts.length; i++) dirty.add(parts.slice(0, i).join("/"));
        }
        this.marks = marks; this.dirty = dirty; this.error = null; this.watch(context.root, cx);
      } catch (e) { if (this.current(context)) this.error = String(e.message ?? e); }
      finally { if (this.context === context) this.loading = false; cx.notify(); }
    });
  }

  toggle(path, cx) {
    if (this.folders.has(path)) {
      for (const folder of [...this.folders]) if (folder === path || folder.startsWith(path + "/")) {
        this.folders.delete(folder); this.entries.delete(folder);
      }
    } else {
      this.folders.add(path);
      if (!this.entries.has(path) && !this.pending.has(path)) {
        const context = this.context;
        this.pending.add(path);
        cx.spawn(async (cx) => {
          try { await this.loadFolder(path, context); }
          catch (e) { if (this.current(context)) this.error = String(e); }
          finally { if (this.context === context) this.pending.delete(path); cx.notify(); }
        });
      }
    }
    cx.notify();
  }

  collapseAll(cx) {
    for (const f of this.folders) this.entries.delete(f);
    this.folders.clear(); cx.notify();
  }

  // ---- File actions ------------------------------------------------------

  // What an action works on: the selection (or `path`), and where new things go.
  target(path) {
    const c = this.context, root = c?.root;
    if (!root) return null;
    const pick = path === undefined ? [...this.sel] : path === "" ? [] : this.sel.has(path) ? [...this.sel] : [path];
    const items = pick.map((rel) => ({ rel, path: `${root}/${rel}`, dir: this.isDir(rel) }));
    const first = path !== undefined && path !== "" ? path : pick.length === 1 ? pick[0] : null;
    const folder = first === null ? root : this.isDir(first) ? `${root}/${first}` : parentOf(`${root}/${first}`);
    return { root, on: c.on ?? null, folder, items };
  }

  isDir(rel) {
    const parent = rel.includes("/") ? rel.replace(/\/[^/]*$/, "") : "";
    return Boolean(this.entries.get(parent)?.find((e) => e.name === rel.split("/").pop())?.dir);
  }

  openMenu(path, cx) {
    if (path && !this.sel.has(path)) { this.sel = new Set([path]); this.anchor = path; }
    if (!path) this.sel = new Set();
    const target = this.target(path ?? "");
    if (!target) return;
    this.focus.focus();
    openOverlay({ mod: MOD, kind: "popup", width: 270, height: menuHeight(target), props: { view: "menu", target } });
    cx.notify();
  }

  // Runs the requests the menu and dialogs post (they close at once; this stays).
  takeRequest(cx) {
    const op = shared(OP);
    if (!op || op.seq === this.opSeen) return;
    this.opSeen = op.seq;
    if (Date.now() - (op.at ?? 0) > 15000) return;
    // Only the Explorer showing that folder does it.
    if (!this.context?.root || op.target?.root !== this.context.root || !sameMachine(op.target?.on, this.context.on)) return;
    // Not during render: perform() notifies.
    cx.timer.after(0, (cx) => this.perform(op, cx));
  }

  perform(op, cx) {
    const { target } = op, on = target.on ?? null;
    const paths = target.items.map((i) => i.path);
    const task = async (label, body) => {
      this.busy = label; this.note = null; cx.notify();
      cx.spawn(async (cx) => {
        try { await body(cx); }
        catch (e) { this.note = String(e.message ?? e); if (label) notify({ title: `${label.replace(/…$/, "")} failed`, body: this.note, level: "error" }); }
        finally { this.busy = null; this.refresh(cx); cx.notify(); }
      });
    };
    const reveal = (folder, names = []) => {
      const rel = folder === target.root ? "" : folder.slice(target.root.length + 1);
      if (rel) { const parts = rel.split("/"); for (let i = 1; i <= parts.length; i++) this.folders.add(parts.slice(0, i).join("/")); }
      if (names.length) { this.sel = new Set(names.map((n) => (rel ? `${rel}/${n}` : n))); this.anchor = [...this.sel][0]; }
    };
    switch (op.op) {
      case "copy": case "cut":
        if (!paths.length) return;
        setShared(CLIP, { items: paths.map((path) => ({ path, on })), cut: op.op === "cut", at: Date.now() });
        if (!on) copyFilesToSystem(paths);
        return cx.notify();
      case "paste": return task("Pasting…", async (cx) => {
        const sys = await readSystemClipboard(), clip = shared(CLIP);
        const ours = clip?.items?.length && clip.items.every((i) => !i.on) && sys.kind === "files"
          && sys.paths.length === clip.items.length && sys.paths.every((p, i) => p === clip.items[i].path);
        let items, cut;
        if (sys.kind === "files" && !ours) { items = sys.paths.map((path) => ({ path, on: null })); cut = sys.cut; }
        else if (clip?.items?.length) { items = clip.items; cut = clip.cut; }
        else if (sys.kind === "image") { const name = await pasteImage(target.folder, on); return reveal(target.folder, [name]); }
        else throw new Error("Nothing to paste: copy files first (here or in a file manager)");
        this.busy = `${cut ? "Moving" : "Copying"} ${items.length} item${items.length === 1 ? "" : "s"}…`; cx.notify();
        const names = await transfer(items, target.folder, on, cut);
        if (cut) setShared(CLIP, null);
        reveal(target.folder, names);
      });
      case "drop": return task(`Copying ${op.paths.length} item${op.paths.length === 1 ? "" : "s"}${on ? ` to ${on}` : ""}…`, async () => {
        const names = await transfer(op.paths.map((path) => ({ path, on: null })), target.folder, on, false);
        reveal(target.folder, names);
      });
      case "download": return task("Downloading…", async () => {
        const dl = `${home()}/Downloads`;
        await exec("mkdir", ["-p", dl]);
        const names = await transfer((paths.length ? paths : [target.folder]).map((path) => ({ path, on })), dl, null, false);
        notify({ title: "Downloaded", body: names.map((n) => `~/Downloads/${n}`).join("\n"), level: "success" });
      });
      case "delete": return task(on ? "Deleting…" : "Moving to the Trash…", async () => {
        await remove(paths, on);
        this.sel = new Set();
        const clip = shared(CLIP);
        if (clip?.items?.some((i) => paths.includes(i.path) && sameMachine(i.on, on))) setShared(CLIP, null);
      });
      case "rename": return task("Renaming…", async () => {
        const from = paths[0];
        await rename(from, op.to, on);
        reveal(parentOf(op.to), [op.to.split("/").pop()]);
        // An open file follows its new name.
        const spec = editorSpec();
        if (spec?.path === from || spec?.path?.startsWith(from + "/"))
          openInEditor({ ...spec, path: op.to + spec.path.slice(from.length), rel: (op.to + spec.path.slice(from.length)).slice(target.root.length + 1) });
      });
      case "new": return task(null, async () => {
        await create(op.path, op.dir, on);
        reveal(parentOf(op.path), [op.path.split("/").pop()]);
        if (!op.dir) openInEditor({ kind: "file", path: op.path, root: target.root, rel: op.path.slice(target.root.length + 1), on });
      });
      case "terminal":
        return run("tab.new", { folder: paths.length === 1 && target.items[0].dir ? paths[0] : target.folder });
      case "reveal": {
        const what = paths[0] ?? target.folder;
        const uri = "file://" + what.split("/").map(encodeURIComponent).join("/");
        sh('gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 --method org.freedesktop.FileManager1.ShowItems "[\'$1\']" "" >/dev/null 2>&1 || xdg-open "$2" >/dev/null 2>&1',
          [uri, parentOf(what)]).catch(() => {});
        return;
      }
      case "open-ext": return task(on ? "Downloading…" : null, () => openExternally(paths[0], on));
    }
  }

  // Keys while the tree has the keyboard (click it first), like VS Code's Explorer.
  key(e, cx) {
    const m = e.modifiers, k = e.key, ctrl = m.control || m.platform;
    const cur = this.anchor && this.flat.find((r) => r.path === this.anchor) ? this.anchor : null;
    const idx = cur ? this.flat.findIndex((r) => r.path === cur) : -1;
    const go = (i) => { const r = this.flat[Math.max(0, Math.min(this.flat.length - 1, i))]; if (r) { this.sel = new Set([r.path]); this.anchor = r.path; } };
    if (ctrl && !m.alt && k === "c") request({ op: "copy", target: this.target() });
    else if (ctrl && !m.alt && k === "x") request({ op: "cut", target: this.target() });
    else if (ctrl && k === "v") request({ op: "paste", target: this.target() });
    else if (ctrl && m.alt && k === "c") { const t = this.target(); cx.write_to_clipboard((t.items.length ? t.items.map((i) => m.shift ? i.rel : i.path) : [m.shift ? "." : t.root]).join("\n")); }
    else if (ctrl && k === "a") { this.sel = new Set(this.flat.map((r) => r.path)); }
    else if (k === "delete" && this.sel.size) openDialog("delete", this.target());
    else if (k === "f2" && this.sel.size === 1) openDialog("rename", this.target());
    else if (k === "down") go(idx + 1);
    else if (k === "up") go(idx < 0 ? this.flat.length - 1 : idx - 1);
    else if (k === "home") go(0);
    else if (k === "end") go(this.flat.length - 1);
    else if ((k === "right" || k === "left") && cur) {
      const r = this.flat[idx];
      if (r.dir && (k === "right") !== this.folders.has(cur)) this.toggle(cur, cx);
      else if (k === "left" && cur.includes("/")) go(this.flat.findIndex((x) => x.path === parentOf(cur)));
    }
    else if (k === "enter" && cur) { const r = this.flat[idx]; r.dir ? this.toggle(cur, cx) : this.open(cur); }
    else if (k === "escape") { this.sel = new Set(); this.anchor = null; }
    else return;
    cx.stop_propagation(); cx.notify();
  }

  open(rel) {
    const root = this.context.root;
    openInEditor({ kind: "file", path: `${root}/${rel}`, root, rel, on: this.context.on });
  }

  click(entry, path, e, cx) {
    this.focus.focus();
    const m = e.modifiers;
    if (m.control || m.platform) {
      const sel = new Set(this.sel);
      sel.has(path) ? sel.delete(path) : sel.add(path);
      this.sel = sel; this.anchor = path; return cx.notify();
    }
    if (m.shift && this.anchor) {
      const a = this.flat.findIndex((r) => r.path === this.anchor), b = this.flat.findIndex((r) => r.path === path);
      if (a >= 0 && b >= 0) { this.sel = new Set(this.flat.slice(Math.min(a, b), Math.max(a, b) + 1).map((r) => r.path)); return cx.notify(); }
    }
    this.sel = new Set([path]); this.anchor = path;
    entry.dir ? this.toggle(path, cx) : this.open(path);
    cx.notify();
  }

  // Files dropped from the desktop: into the folder (or the file's folder) they fell on.
  drop(paths, rel, cx) {
    const target = this.target(rel);
    if (!target || !paths?.length) return;
    this.perform({ op: "drop", target: { ...target, items: [] }, paths }, cx);
  }

  rows(prefix, depth, out, t, openPath) {
    if (out.length >= TOTAL || depth > 40) return out;
    for (const entry of this.entries.get(prefix) ?? []) {
      if (out.length >= TOTAL) break;
      const path = prefix ? `${prefix}/${entry.name}` : entry.name, open = this.folders.has(path);
      const mark = this.marks[path] ?? (entry.dir && this.marks[path] === undefined && this.dirty.has(path) ? "•" : null);
      const color = mark === "•" ? t.blocked : mark === "U" ? t.ansi2 : mark ? statusColor(mark === "!" ? "U" : mark, t) : null;
      const abs = `${this.context.root}/${path}`, chosen = this.sel.has(path), current = openPath === abs;
      const cut = this.cut.has(abs);
      this.flat.push({ path, dir: entry.dir });
      out.push(h_flex().id(`file-${path}`).h(24).flex_none().pl(6 + depth * 14).pr(10).gap(5).items_center().cursor_pointer()
        .when(chosen, (el) => el.bg(t.selected)).when(!chosen && current, (el) => el.bg(t.hover)).hover((s) => s.bg(t.hover))
        .when(cut, (el) => el.opacity(0.5))
        .on_click((e, cx) => this.click(entry, path, e, cx))
        .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(path, cx); })
        .on_drop((e, cx) => { cx.stop_propagation(); this.drop(e.paths, path, cx); })
        .child(entry.dir ? icon(`chevron-${open ? "down" : "right"}`, 12).text_color(t.dim) : div().w(12).flex_none())
        .child(fileImage(path, entry.dir, open))
        .child(div().flex_1().min_w(0).truncate().when(Boolean(color), (el) => el.text_color(color)).child(entry.name))
        .when(Boolean(mark), (el) => el.child(div().text_size(10).text_color(color).child(mark))));
      if (entry.dir && open) this.rows(path, depth + 1, out, t, openPath);
    }
    return out;
  }

  render(cx) {
    if (locationKey() !== this.context?.key) this.refresh(cx);
    this.takeRequest(cx);
    const clip = shared(CLIP);
    this.cut = new Set(clip?.cut && sameMachine(clip.items?.[0]?.on, this.context?.on) ? clip.items.map((i) => i.path) : []);
    this.flat = [];
    const t = theme();
    const openPath = editorSpec()?.path;
    const root = this.context?.root ?? this.context?.cwd;
    return v_flex().id("activity-files").size_full().min_h(0).bg(t.chrome).text_color(t.foreground).text_size(13)
      .child(viewHeader("Files", [
        iconButton("files-new", "file-plus", "New File…", () => { const t = this.target(); if (t) openDialog("new-file", t); }),
        iconButton("files-newdir", "folder-plus", "New Folder…", () => { const t = this.target(); if (t) openDialog("new-folder", t); }),
        iconButton("files-refresh", "refresh", "Refresh", (_e, cx) => this.refresh(cx)),
        iconButton("files-collapse", "collapse", "Collapse folders", (_e, cx) => this.collapseAll(cx)),
      ]))
      .child(h_flex().h(24).flex_none().px(8).gap(5).items_center()
        .child(icon("chevron-down", 12).text_color(t.dim))
        .child(div().flex_1().min_w(0).truncate().text_size(11).font_semibold().text_color(t.foreground)
          .child((this.context?.on ? `${this.context.on}: ` : "") + (basename(root) || "No folder"))))
      .child(v_flex().id("files-tree").flex_1().min_h(0).overflow_y_scrollbar().pb(8)
        .track_focus(this.focus).on_key_down((e, cx) => this.key(e, cx))
        .on_mouse_down("left", () => this.focus.focus())
        .on_mouse_down("right", (_e, cx) => this.openMenu(null, cx))
        .on_drop((e, cx) => this.drop(e.paths, "", cx))
        .children(this.rows("", 0, [], t, openPath))
        .when(Boolean(this.error) || !this.entries.get("")?.length, (el) => el.child(div().px(14).py(8).text_size(12).text_color(t.dim)
          .child(this.error || (this.loading ? "Loading files…" : root ? "Empty folder" : "Focus a terminal to browse its folder"))))
        // Room below the rows to right-click or drop on the folder itself.
        .child(div().h(48).flex_none())
        .when(this.limited, (el) => el.child(div().px(14).py(8).text_size(11).text_color(t.dim).child("Limited to 500 entries per folder, 5,000 total"))))
      .when(Boolean(this.busy || this.note), (el) => el.child(h_flex().flex_none().px(12).py(6).gap(6).items_center().border_t(1).border_color(t.border).text_size(11.5)
        .text_color(this.busy ? t.muted : t.ansi1)
        .child(div().flex_1().min_w(0).child(this.busy ?? this.note))
        .when(!this.busy, (el) => el.child(iconButton("files-note-x", "x", "Dismiss", (_e, cx) => { this.note = null; cx.notify(); }, { size: 18, icon: 11 })))));
  }
}
