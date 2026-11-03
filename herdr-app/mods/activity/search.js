// Search: text search across the focused terminal's repo (or folder), with
// ripgrep when it's installed, else git grep, else grep. Results by file;
// clicking one opens the file in the editor pane.
import { div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { exec, theme, focused, shared } from "herdr";
import { editorSpec, location, locationKey, openInEditor, iconButton, viewHeader, icon, fileImage } from "./common.js";

const MAX_LINES = 2000;

function toggle(id, label, tip, on, action, t) {
  return div().id(id).h(20).px(5).flex_none().flex().items_center().rounded(4).text_size(11).cursor_pointer().tooltip(tip)
    .border_1().border_color(on ? t.accent : "#00000000").bg(on ? t.selected : "#00000000").text_color(on ? t.foreground : t.dim)
    .hover((s) => s.text_color(t.foreground))
    .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click((_e, cx) => action(cx)).child(label);
}

export default class Search {
  init(_props, cx) {
    this.results = []; this.fold = {}; this.case = false; this.regex = false; this.word = false;
    this.input = InputState.new({ placeholder: "Search (Enter)" });
    this.input.on("submit", (_e, cx) => this.search(cx));
    this.input.on("focus", (_e, cx) => { this.typing = true; cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.typing = false; cx.notify(); });
  }

  async tool(on) {
    const key = on ?? "";
    this.tools ??= {};
    if (!(key in this.tools)) {
      const r = await exec("sh", ["-c", "command -v rg >/dev/null && echo rg || echo grep"], { on }).catch(() => null);
      this.tools[key] = r?.stdout.trim() || "grep";
    }
    return this.tools[key];
  }

  search(cx) {
    const query = this.input.value();
    if (!query) { this.results = []; this.summary = null; cx.notify(); return; }
    const { cwd, on } = location(), key = locationKey(), seq = (this.seq = (this.seq ?? 0) + 1);
    if (!cwd) { this.summary = "Focus a terminal to search its folder"; cx.notify(); return; }
    this.loading = true; this.summary = null;
    cx.spawn(async (cx) => {
      try {
        const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on }).catch(() => null);
        const repo = top?.code === 0 ? top.stdout.trim() : null, root = repo ?? cwd;
        const tool = await this.tool(on);
        let r;
        if (tool === "rg") {
          r = await exec("rg", ["--line-number", "--no-heading", "--color", "never", "--max-columns", "300", "--max-count", "100",
            this.case ? "--case-sensitive" : "--ignore-case", ...(this.regex ? [] : ["--fixed-strings"]), ...(this.word ? ["--word-regexp"] : []), "-e", query, "--", "."], { cwd: root, on });
        } else if (repo) {
          r = await exec("git", ["-c", "core.quotePath=false", "grep", "-n", "-I", "--untracked", ...(this.case ? [] : ["-i"]), this.regex ? "-E" : "-F", ...(this.word ? ["-w"] : []), "-e", query], { cwd: root, on });
        } else {
          r = await exec("grep", ["-rnI", "--exclude-dir=.git", "--exclude-dir=node_modules", ...(this.case ? [] : ["-i"]), this.regex ? "-E" : "-F", ...(this.word ? ["-w"] : []), "-e", query, "."], { cwd: root, on });
        }
        if (seq !== this.seq) return;
        // 1 = no match for all three tools.
        if (r.code > 1) throw new Error(r.stderr.trim() || `${tool} exited with ${r.code}`);
        const lines = r.stdout.split("\n").filter(Boolean), byFile = new Map();
        for (const line of lines.slice(0, MAX_LINES)) {
          const m = /^(.*?):(\d+):(.*)$/.exec(line);
          if (!m) continue;
          const rel = m[1].replace(/^\.\//, "");
          if (!byFile.has(rel)) byFile.set(rel, []);
          byFile.get(rel).push({ line: Number(m[2]), text: m[3].trim().slice(0, 300) });
        }
        this.root = root; this.on = on; this.key = key; this.fold = {};
        this.results = [...byFile.entries()].map(([rel, hits]) => ({ rel, hits }));
        const n = this.results.reduce((s, f) => s + f.hits.length, 0);
        this.summary = n ? `${n}${lines.length > MAX_LINES ? "+" : ""} results in ${this.results.length} files` : "No results found";
      } catch (e) { if (seq === this.seq) { this.results = []; this.summary = String(e.message ?? e); } }
      finally { if (seq === this.seq) { this.loading = false; cx.notify(); } }
    });
    cx.notify();
  }

  render() {
    const t = theme();
    const openSpec = editorSpec();
    const rows = [];
    for (const f of this.results) {
      const open = !this.fold[f.rel], parts = f.rel.split("/"), name = parts.pop();
      rows.push(h_flex().id(`sf-${f.rel}`).h(22).flex_none().pl(6).pr(10).gap(5).items_center().cursor_pointer().hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => { this.fold[f.rel] = open; cx.notify(); })
        .child(icon(`chevron-${open ? "down" : "right"}`, 12).text_color(t.dim))
        .child(fileImage(f.rel, false, false, 14))
        .child(div().flex_none().max_w(160).truncate().child(name))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(parts.join("/")))
        .child(div().px(5).rounded_full().bg(t.raised).text_size(10).text_color(t.muted).child(String(f.hits.length))));
      if (open) for (const h of f.hits) {
        const abs = `${this.root}/${f.rel}`, selected = openSpec?.path === abs && openSpec?.line === h.line;
        rows.push(h_flex().id(`sh-${f.rel}:${h.line}`).h(22).flex_none().pl(36).pr(10).gap(6).items_center().cursor_pointer()
          .when(selected, (el) => el.bg(t.selected)).hover((s) => s.bg(t.hover))
          .on_click(() => openInEditor({ kind: "file", path: abs, root: this.root, rel: f.rel, on: this.on, line: h.line }))
          .child(div().flex_none().w(30).text_right().text_size(10).text_color(t.dim).child(String(h.line)))
          .child(div().flex_1().min_w(0).truncate().text_size(12).text_color(t.muted).child(h.text)));
      }
    }
    return v_flex().id("activity-search").size_full().min_h(0).bg(t.chrome).text_color(t.foreground).text_size(13)
      .child(viewHeader("Search", [
        iconButton("search-clear", "x", "Clear results", (_e, cx) => { this.input.set_value(""); this.results = []; this.summary = null; cx.notify(); }),
      ]))
      .child(v_flex().flex_none().px(10).pb(6).gap(6)
        .child(h_flex().id("search-box").w_full().h(28).pl(8).pr(4).gap(2).items_center().rounded(5).bg(t.background).border_1()
          .border_color(this.typing ? t.accent : t.border).cursor_text().on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .child(Input.new(this.input).flex_1().min_w(0).h_full().text_size(12).text_color(t.foreground))
          .child(toggle("s-case", "Aa", "Match case", this.case, (cx) => { this.case = !this.case; this.search(cx); }, t))
          .child(toggle("s-word", "ab", "Whole word", this.word, (cx) => { this.word = !this.word; this.search(cx); }, t))
          .child(toggle("s-regex", ".*", "Regular expression", this.regex, (cx) => { this.regex = !this.regex; this.search(cx); }, t)))
        .when(Boolean(this.summary) || this.loading, (el) => el.child(div().text_size(11).text_color(t.dim).child(this.loading ? "Searching…" : this.summary))))
      .child(v_flex().id("search-results").flex_1().min_h(0).overflow_y_scrollbar().pb(8).children(rows));
  }
}
