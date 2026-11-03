// Files with a search bar on top: Names filters every file of the repo (or folder)
// by path, Contents is the Search view.
import { div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { exec, theme } from "herdr";
import { location, locationKey, openInEditor, editorSpec, fileImage } from "./common.js";
import Files from "./files.js";
import Search from "./search.js";

const MAX_FILES = 20000, MAX_SHOWN = 300;

export default class Browse {
  init(props, cx) {
    this.mode = "names";
    this.files = new Files(); this.files.init(props, cx);
    this.search = new Search(); this.search.init(props, cx);
    this.input = InputState.new({ placeholder: "Find files" });
    this.input.on("change", (_e, cx) => { this.load(cx, false); cx.notify(); });
    this.input.on("focus", (_e, cx) => { this.typing = true; this.load(cx, true); cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.typing = false; cx.notify(); });
  }

  release() { this.files.release?.(); this.search.release?.(); }

  // The path list is read once per folder, and again each time the box gets focus.
  load(cx, again) {
    const key = locationKey();
    if (this.loading || (!again && this.list && this.listKey === key)) return;
    const { cwd, on } = location();
    if (!cwd) return;
    this.loading = true;
    cx.spawn(async (cx) => {
      try {
        const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on }).catch(() => null);
        const repo = top?.code === 0 ? top.stdout.trim() : null, root = repo ?? cwd;
        const r = repo
          ? await exec("git", ["ls-files", "-z", "-co", "--exclude-standard"], { cwd: root, on })
          : await exec("sh", ["-c", 'find . -type d \\( -name .git -o -name node_modules \\) -prune -o -type f -print | head -n "$1"', "sh", String(MAX_FILES)], { cwd: root, on });
        this.list = r.stdout.split(repo ? "\0" : "\n").filter(Boolean).map((p) => p.replace(/^\.\//, "")).slice(0, MAX_FILES);
        this.root = root; this.on = on; this.listKey = key;
      } catch { this.list = []; }
      finally { this.loading = false; cx.notify(); }
    });
  }

  matches() {
    const words = this.input.value().toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length || !this.list) return [];
    const out = [];
    for (const p of this.list) {
      const l = p.toLowerCase();
      if (words.every((w) => l.includes(w))) out.push(p);
      if (out.length > MAX_SHOWN) break;
    }
    return out;
  }

  tab(id, label, t) {
    const on = this.mode === id;
    return div().id(`browse-${id}`).flex_1().h(24).flex().items_center().justify_center().rounded(5).cursor_pointer().text_size(12)
      .when(on, (el) => el.bg(t.raised).text_color(t.foreground))
      .when(!on, (el) => el.text_color(t.muted).hover((s) => s.text_color(t.foreground)))
      .on_click((_e, cx) => { this.mode = id; cx.notify(); })
      .child(label);
  }

  render(cx) {
    const t = theme();
    const tabs = h_flex().flex_none().mx(10).mt(8).mb(6).p(2).gap(2).rounded(7).bg(t.background).border_1().border_color(t.border)
      .child(this.tab("names", "Names", t)).child(this.tab("contents", "Contents", t));
    if (this.mode === "contents") return v_flex().size_full().min_h(0).bg(t.chrome).child(tabs).child(div().flex_1().min_h(0).child(this.search.render(cx)));

    const query = this.input.value(), found = this.matches(), open = editorSpec();
    const box = h_flex().id("browse-box").flex_none().mx(10).mb(6).h(28).px(8).items_center().rounded(5).bg(t.background).border_1()
      .border_color(this.typing ? t.accent : t.border).cursor_text().on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .child(Input.new(this.input).flex_1().min_w(0).h_full().text_size(12).text_color(t.foreground));
    const body = !query ? this.files.render(cx)
      : v_flex().id("browse-found").size_full().min_h(0).overflow_y_scrollbar().pb(8).text_color(t.foreground).text_size(13)
        .when(!found.length, (el) => el.child(div().p(10).text_size(12).text_color(t.dim).child(this.loading ? "Loading files…" : "No files")))
        .children(found.slice(0, MAX_SHOWN).map((rel) => {
          const parts = rel.split("/"), name = parts.pop(), abs = `${this.root}/${rel}`;
          return h_flex().id(`bf-${rel}`).h(24).flex_none().px(10).gap(6).items_center().cursor_pointer()
            .when(open?.path === abs, (el) => el.bg(t.selected)).hover((s) => s.bg(t.hover))
            .on_click(() => openInEditor({ kind: "file", path: abs, root: this.root, rel, on: this.on }))
            .child(fileImage(rel, false, false, 14))
            .child(div().flex_none().max_w(180).truncate().child(name))
            .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(parts.join("/")));
        }))
        .when(found.length > MAX_SHOWN, (el) => el.child(div().p(10).text_size(11).text_color(t.dim).child(`Showing the first ${MAX_SHOWN}; type more to narrow`)));
    return v_flex().size_full().min_h(0).bg(t.chrome).child(tabs).child(box).child(div().flex_1().min_h(0).child(body));
  }
}
