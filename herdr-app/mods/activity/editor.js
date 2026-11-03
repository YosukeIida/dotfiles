// The editor pane: one per tab, beside the terminal, like VS Code's preview
// editor. Shows what the sidebar opened (shared "activity.editor"[tab]):
// a file (editable, Ctrl+S saves, here or on an ssh machine), a viewer for
// images / PDFs / media / binary files, or a git diff.
import { div, image } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState, Scrollbar, v_virtual_list, TextView, h_resizable, resizable_panel } from "gpui-base";
import { exec, readTextFile, writeTextFile, watchFolder, theme, settings, shared, setShared, props, run, panes, nextCommand, home } from "herdr";
import { iconButton, icon, READ, AREA, editorKey, setEditorSpec, fileImage, segmented } from "./common.js";
import { Viewer, viewerKind, human, openExternally } from "./viewer.js";
import { writeRemoteText, stat } from "./io.js";
import { splitMath, drawn, draw } from "./math.js";
import { inlineMath } from "./tex.js";

const MD = /\.(md|markdown|mdx)$/i;
// TextView.html() は CSS を扱わず、mod には web view も無いので、HTML は中で描かずに既定のブラウザへ渡す。
const HTML = /\.html?$/i;
// Markdown files cycle preview → split (live preview on the right) → edit.
const MD_MODES = { preview: ["split", "eye", "Preview"], split: ["edit", "split", "Side by side"], edit: ["preview", "pencil", "Edit"] };

const LANG = { ts: "js", tsx: "js", mts: "js", cts: "js", jsx: "js", mjs: "js", cjs: "js", toml: "yaml", yml: "yaml", jsonc: "json", svelte: "html", vue: "html", htm: "html", md: "markdown", py: "python", rs: "rust", sh: "bash", zsh: "bash" };
const MAX_EDIT = 400000;

function diffRows(lines) {
  let old = 0, next = 0;
  return lines.map((line) => {
    const m = /^@@ -(\d+)(?:,\d+)? \+(\d+)/.exec(line);
    if (m) { old = +m[1]; next = +m[2]; return { kind: "@", text: line }; }
    const kind = line[0];
    if (kind === "-") return { kind, a: old++, text: line.slice(1) || " " };
    if (kind === "+") return { kind, b: next++, text: line.slice(1) || " " };
    if (kind === " ") return { kind, a: old++, b: next++, text: line.slice(1) || " " };
    return { kind: "", text: line };
  });
}

const tilde = (p) => { const h = home(); return p?.startsWith(h + "/") ? "~" + p.slice(h.length) : p; };

export default class EditorPane {
  init(p, cx) {
    // In the workbench's editor area (props.slot) it follows the active space;
    // as a pane it belongs to its tab.
    this.slot = Boolean(p?.slot); this.tab = p?.tab;
    this.rows = []; this.width = 0; this.pending = null; this.mdMode = "preview";
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "save") this.save(cx);
        else if (c === "close") this.close();
        else if (c === "preview") this.mdMode = MD_MODES[this.mdMode][0];
        cx.notify();
      }
    });
  }

  slotKey() { return this.slot ? editorKey() : this.tab; }
  spec() { return (shared("activity.editor") ?? {})[this.slotKey()] ?? (this.slot ? null : props()?.spec ?? null); }

  // Loads what the sidebar asked for, unless unsaved edits are in the way.
  sync(cx) {
    const spec = this.spec();
    const key = spec ? JSON.stringify(spec) : null;
    if (key === this.key) return;
    if (this.dirty) { this.pending = spec; return; }
    this.pending = null; this.key = key; this.shown = spec;
    // load() は保存やファイルの変更でも呼ばれるので、ブラウザはここ（開くファイルが変わったとき）だけで開く。
    if (spec?.kind === "file" && HTML.test(spec.path)) openExternally(spec.path, spec.on).catch(() => {});
    this.load(spec, cx);
  }

  release() { this.code?.release(); this.code = null; }

  load(spec, cx) {
    const seq = (this.seq = (this.seq ?? 0) + 1);
    this.error = null; this.note = null; this.dirty = false; this.original = null; this.rows = []; this.viewer?.dispose(); this.viewer = null; this.release();
    if (!spec) return;
    this.loading = true;
    this.watch(spec, cx);
    cx.spawn(async (cx) => {
      try {
        const alive = () => seq === this.seq;
        const kind = spec.kind === "file" && !spec.asText ? viewerKind(spec.path) : null;
        if (spec.kind === "diff") await this.loadDiff(spec, seq);
        else if (kind) this.viewer = new Viewer(kind, spec);
        else await this.loadFile(spec, seq);
        // Images, PDFs, media and files that aren't text.
        if (this.viewer && alive()) await this.viewer.load(cx, alive);
      } catch (e) { if (seq === this.seq) this.error = String(e.message ?? e); }
      finally { if (seq === this.seq) { this.loading = false; cx.notify(); } }
    });
  }

  async loadFile(spec, seq) {
    const text = await readTextFile(spec.path, { on: spec.on }).catch(() => null);
    if (seq !== this.seq) return;
    if (text === null) {
      const info = await stat(spec.path, spec.on);
      if (!info) { this.error = "This file is no longer available"; return; }
      this.viewer = new Viewer("binary", spec, { reason: info.size > 1048576 ? `Too large to open as text (${human(info.size)}; the limit is 1 MB).` : "This file can't be read as text." });
      return;
    }
    if (text.includes("\0")) { this.viewer = new Viewer("binary", spec, { reason: "A binary file." }); return; }
    const t = theme(), name = spec.path.split("/").pop(), ext = name.includes(".") ? name.split(".").pop().toLowerCase() : "txt";
    this.readonly = text.length > MAX_EDIT;
    this.original = text;
    this.code = EditorState.new({
      language: LANG[ext] ?? ext, readonly: this.readonly,
      value: text.length > MAX_EDIT ? text.slice(0, MAX_EDIT) + "\n… (file truncated, read-only)" : text,
      font_family: settings().font_family, font_size: 13,
      syntax: { keyword: t.ansi5, string: t.ansi2, comment: t.dim, function: t.ansi4, type: t.ansi3, number: t.ansi1, constant: t.ansi6, boolean: t.ansi6 },
    });
    this.code.on("change", (_e, cx) => {
      const dirty = this.code.value() !== this.original;
      if (dirty !== this.dirty) { this.dirty = dirty; if (!dirty && this.pending !== null) this.sync(cx); cx.notify(); }
      else if (this.mdMode !== "edit" && MD.test(spec.path)) this.livePreview(cx);
    });
  }

  // The Markdown preview: text through TextView, display math as RaTeX images.
  markdown(text, t, cx) {
    const color = t.foreground;
    return splitMath(text).map((p, i) => {
      if (p.md !== undefined) return TextView.markdown(`ed-md-${i}`, inlineMath(p.md)).selectable();
      const m = drawn(p.tex, color);
      if (!m) cx.spawn(async (cx) => { await draw(p.tex, color); cx.notify(); });
      if (m?.src) return div().w_full().py(6).flex().justify_center().child(image(m.src).w(m.w).h(m.h).flex_none());
      return div().w_full().py(6).font_family(settings().font_family ?? "JetBrains Mono").text_size(12).text_color(t.dim)
        .child(m?.error ? `$$ ${p.tex} $$  (${m.error})` : `$$ ${p.tex} $$`);
    });
  }

  // Re-renders the Markdown preview while typing, at most every 150 ms.
  livePreview(cx) {
    if (this.previewTimer) return;
    this.previewTimer = cx.timer.after(150, (cx) => { this.previewTimer = null; cx.notify(); });
  }

  async loadDiff(spec, seq) {
    let lines;
    if (spec.untracked) {
      const text = await readTextFile(spec.path, { on: spec.on });
      if (text === null) lines = ["Cannot preview this file (binary, too large, or unreadable)"];
      else if (text.includes("\0")) lines = ["Binary file · no text diff"];
      else {
        const body = text.replace(/\n$/, "").split("\n").slice(0, 3000);
        lines = [`@@ -0,0 +1,${body.length} @@ new file`, ...body.map((l) => `+${l}`)];
      }
    } else {
      const r = await exec("git", [...READ, "diff", ...(spec.staged ? ["--cached"] : []), "--no-ext-diff", "--no-textconv", "--no-color", "--", spec.rel], { cwd: spec.root, on: spec.on });
      if (r.code !== 0) throw new Error(r.stderr.trim());
      const all = r.stdout.replace(/\n$/, "").split("\n"), first = all.findIndex((l) => l.startsWith("@@"));
      lines = first < 0 ? [/Binary files/.test(r.stdout) ? "Binary file changed" : "No changes"] : all.slice(first, first + 3000);
    }
    if (seq !== this.seq) return;
    lines = lines.map((l) => l.length > 2000 ? l.slice(0, 2000) + "…" : l);
    this.rows = diffRows(lines);
    this.width = Math.max(300, ...lines.map((l) => l.length * 7.5 + 90));
  }

  // Follows the file on disk (local only): reloads when it changes and isn't being edited.
  watch(spec, cx) {
    if (spec.on) return this.poll(spec, cx);
    const dir = spec.kind === "diff" ? spec.root : spec.path.replace(/\/[^/]*$/, "");
    const key = this.key;
    if (this.watched === key) return;
    this.watched = key;
    cx.spawn(async (cx) => {
      try {
        while (this.watched === key) {
          const changed = await watchFolder(dir);
          if (this.watched !== key || this.dirty || this.saving) continue;
          if (spec.kind === "diff" ? !changed.every((p) => p.includes("/.git/")) : changed.includes(spec.path)) {
            if (spec.kind === "file") {
              const text = await readTextFile(spec.path).catch(() => null);
              if (text === this.original || this.watched !== key || this.dirty) continue;
            }
            this.load(spec, cx); cx.notify();
          }
        }
      } catch { if (this.watched === key) this.watched = null; }
    });
  }

  // A remote file can't be watched: its change time is asked every 3 s while it's shown.
  poll(spec, cx) {
    if (spec.kind !== "file") return;
    const key = this.key;
    if (this.watched === key) return;
    this.watched = key;
    let seen = null;
    cx.spawn(async (cx) => {
      while (this.watched === key && this.key === key) {
        const info = await stat(spec.path, spec.on).catch(() => null);
        if (this.watched !== key || this.key !== key) break;
        const now = info ? `${info.mtime}:${info.size}` : "gone";
        if (seen !== null && now !== seen && !this.dirty && !this.saving) {
          if (this.code) {
            const text = await readTextFile(spec.path, { on: spec.on }).catch(() => null);
            if (text !== null && text !== this.original && !this.dirty && this.key === key) { this.load(spec, cx); this.watched = key; cx.notify(); }
          } else if (this.viewer) { this.load(spec, cx); this.watched = key; cx.notify(); }
        }
        seen = now;
        await cx.sleep(3000);
      }
    });
  }

  save(cx) {
    const spec = this.shown;
    if (!spec || spec.kind !== "file" || !this.code || this.readonly || !this.dirty || this.saving) return;
    const text = this.code.value();
    this.saving = true; this.note = null; this.closeArmed = false;
    cx.spawn(async (cx) => {
      try {
        if (spec.on) await writeRemoteText(spec.path, text, this.original, spec.on);
        else await writeTextFile(spec.path, text, this.original);
        this.original = text; this.dirty = false;
        if (this.pending !== null) this.sync(cx);
      } catch (e) { this.note = `Not saved: ${e.message ?? e}. Reopen the file to see the version on disk.`; }
      finally { this.saving = false; cx.notify(); }
    });
    cx.notify();
  }

  discard(cx) {
    this.dirty = false;
    if (this.pending !== null) this.sync(cx);
    else this.load(this.shown, cx);
    cx.notify();
  }

  close() {
    if (this.slot) {
      if (this.dirty && !this.closeArmed) { this.closeArmed = true; this.note = "Unsaved changes: save (Ctrl+S), or close again to discard them."; return; }
      this.closeArmed = false; this.dirty = false;
      setEditorSpec(this.slotKey(), null);
      run("layout.hide", { id: AREA });
      return;
    }
    const me = panes().find((p) => p.mod === "activity" && p.tab === this.tab);
    if (me) run("pane.close", { pane: me.pane });
  }

  diffRow(r, t) {
    if (r.kind === "@") return div().w_full().h(20).px(12).flex_none().truncate().bg(t.raised).text_color(t.dim).child(r.text);
    const num = (n) => div().w(36).flex_none().text_right().text_color(t.dim).child(n === undefined ? "" : String(n));
    return h_flex().w_full().h(20).flex_none().gap(8)
      .when(r.kind === "+", (e) => e.bg(t.ansi2 + "22")).when(r.kind === "-", (e) => e.bg(t.ansi1 + "22"))
      .child(num(r.a)).child(num(r.b))
      .child(div().w(10).flex_none().text_color(r.kind === "+" ? t.ansi2 : r.kind === "-" ? t.ansi1 : t.dim).child(r.kind === " " ? "" : r.kind))
      .child(div().flex_1().min_w(0).whitespace_nowrap().child(r.text));
  }

  render(cx) {
    this.sync(cx);
    const t = theme(), s = this.shown;
    const title = s ? s.rel ?? s.path.split("/").pop() : "No file";
    const sub = !s ? "" : s.kind === "diff" ? (s.untracked ? "Untracked" : s.staged ? "Staged changes" : "Working tree changes")
      : `${s.on ? `${s.on}: ` : ""}${tilde(s.path)}${s.line ? ` · line ${s.line}` : ""}${this.readonly ? " · read-only" : ""}${this.viewer?.subtitle() ? ` · ${this.viewer.subtitle()}` : ""}`;
    const header = h_flex().h(34).flex_none().pl(12).pr(6).gap(8).items_center().border_b(1).border_color(t.border).bg(t.chrome)
      .child(s?.kind === "file" ? fileImage(s.rel ?? s.path) : icon(s?.kind === "diff" ? "git-branch" : "file-text", 14).text_color(t.muted))
      .child(div().flex_none().max_w(320).truncate().font_semibold().child(title))
      .when(this.dirty, (el) => el.child(div().size(8).rounded_full().bg(t.foreground).tooltip("Unsaved changes")))
      .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(sub))
      .when(this.dirty, (el) => el.child(iconButton("ed-save", "save", "Save (Ctrl+S)", (_e, cx) => this.save(cx))))
      .when(Boolean(s) && s.kind === "diff", (el) => el.child(iconButton("ed-open", "file", "Open file", () => {
        setEditorSpec(this.slotKey(), { kind: "file", path: s.path, root: s.root, rel: s.rel, on: s.on });
      })))
      .when(Boolean(s) && s.kind === "file" && MD.test(s.path) && Boolean(this.code), (el) => el.child(segmented("ed-md",
        Object.entries(MD_MODES).map(([mode, [, name, tip]]) => [mode, name, `${tip} (Ctrl+Shift+V)`]), this.mdMode,
        (mode, cx) => { this.mdMode = mode; cx.notify(); })))
      .when(Boolean(s) && s.kind === "file" && HTML.test(s.path), (el) => el.child(iconButton("ed-browser", "external", "Open in browser",
        () => openExternally(s.path, s.on).catch(() => {}))))
      .when(Boolean(this.viewer) && !this.error, (el) => el.children(this.viewer.tools(cx, t)))
      .when(this.viewer?.kind === "binary" && !this.error, (el) => el.child(iconButton("ed-astext", "file-text", "Open as text anyway", () => {
        setEditorSpec(this.slotKey(), { ...s, asText: true });
      })))
      .child(iconButton("ed-close", "x", "Close editor", () => this.close()));
    let body;
    if (!s) body = div().p(16).text_color(t.dim).child("Open a file from the Explorer, Search or Source Control view.");
    else if (this.error) body = div().p(16).text_color(t.dim).child(this.error);
    else if (this.viewer) body = this.viewer.render(cx, t);
    else if (this.loading && !this.code && !this.rows.length) body = div().p(16).text_color(t.dim).child("Loading…");
    else if (s.kind === "file" && this.code && this.mdMode !== "edit" && MD.test(s.path)) {
      const preview = v_flex().id("ed-md").size_full().min_h(0).overflow_y_scrollbar().px(24).py(16).bg(t.background)
        .children(this.markdown(this.code.value(), t, cx));
      body = this.mdMode === "preview" ? div().flex_1().min_h(0).child(preview)
        : h_resizable("ed-md-split").flex_1().min_h(0)
          .child(resizable_panel().size_range(160).child(Editor.new(this.code).size_full()))
          .child(resizable_panel().size_range(160).child(div().size_full().border_l(1).border_color(t.border).child(preview)));
    }
    else if (s.kind === "file" && this.code) body = Editor.new(this.code).flex_1().min_h(0);
    else body = div().flex_1().min_h(0).relative().font_family(settings().font_family ?? "JetBrains Mono").text_size(12)
      .child(div().id("ed-diff-x").size_full().overflow_x_scrollbar()
        .child(div().w_full().min_w(this.width).h_full().child(v_virtual_list("ed-diff", this.rows.length, 20, (i) => String(i),
          (range) => this.rows.slice(range.start, range.end).map((r) => this.diffRow(r, t))).size_full())))
      .child(Scrollbar.vertical("ed-diff").viewport_from_layout().absolute().inset_0());
    return v_flex().id("activity-editor").size_full().min_h(0).bg(t.background).text_color(t.foreground).text_size(13)
      .child(header)
      .when(this.pending !== null && this.dirty, (el) => el.child(h_flex().flex_none().px(12).py(6).gap(8).items_center().bg(t.raised).text_size(12)
        .child(div().flex_1().child(`Unsaved changes in ${title}. Save before opening ${this.pending?.rel ?? "the next file"}?`))
        .child(div().id("ed-p-save").px(8).py(2).rounded(4).bg(t.solid).text_color(t.solid_foreground).cursor_pointer().on_click((_e, cx) => this.save(cx)).child("Save"))
        .child(div().id("ed-p-drop").px(8).py(2).rounded(4).border_1().border_color(t.border).cursor_pointer().on_click((_e, cx) => this.discard(cx)).child("Discard"))))
      .when(Boolean(this.note), (el) => el.child(div().flex_none().px(12).py(6).bg(t.raised).text_size(12).text_color(t.ansi1).child(this.note)))
      .child(body);
  }
}
