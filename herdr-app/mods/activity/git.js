// Source Control: branch, sync, commit box, staged and unstaged changes with
// stage / unstage / discard, and recent commits. Clicking a change opens its diff
// in the editor pane. Reads are from Herdr's shipped `changes` mod.
import { div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { exec, watchFolder, theme, focused, shared, setShared } from "herdr";
import { sh, SEP } from "./io.js";
import { location, locationKey, basename, openInEditor, iconButton, viewHeader, icon, statusColor, READ, editorSpec, fileImage } from "./common.js";

const LIMIT = 1000;
// Every read of a refresh as one script (one round trip on a remote machine):
// top, status, branch, ahead/behind, log, separated by SEP; status's exit code last.
const G = READ.join(" ");
const REFRESH = `cd "$1" 2>/dev/null || { echo "No such folder: $1" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is not installed on this machine" >&2; exit 4; }
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not a git repository" >&2; exit 3; }
cd "$top" || exit 2
s='\n@@HERDR-SEP@@\n'
printf '%s' "$top"; printf "$s"
git ${G} status --porcelain=v1 -z --no-renames --untracked-files=all; c=$?; printf "$s"
git ${G} rev-parse --abbrev-ref HEAD 2>/dev/null; printf "$s"
git ${G} rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || printf none; printf "$s"
git ${G} log -n 30 --format='%h%x09%s%x09%an%x09%cr' 2>/dev/null; printf "$s"
printf '%s' "$c"`;

function parseStatus(out) {
  // porcelain v1 -z: "XY path\0" (renames are off).
  const staged = [], unstaged = [];
  const entries = out.split("\0").filter(Boolean);
  for (const entry of entries.slice(0, LIMIT)) {
    const x = entry[0], y = entry[1], path = entry.slice(3);
    if (x === "?" && y === "?") { unstaged.push({ path, status: "U", untracked: true }); continue; }
    const conflict = x === "U" || y === "U" || (x === "A" && y === "A") || (x === "D" && y === "D");
    if (conflict) { unstaged.push({ path, status: "!", conflict: true }); continue; }
    if (x !== " ") staged.push({ path, status: x === "R" || x === "C" ? "A" : x });
    if (y !== " ") unstaged.push({ path, status: y });
  }
  return { staged, unstaged, limited: entries.length > LIMIT };
}

export default class Git {
  init(_props, cx) {
    this.staged = []; this.unstaged = []; this.commits = []; this.message = ""; this.fold = {};
    this.input = InputState.new({ placeholder: "Message (Enter to commit)" });
    this.input.on("change", (_e, cx) => {
      const had = Boolean(this.message.trim());
      this.message = this.input.value();
      if (had !== Boolean(this.message.trim())) cx.notify();
    });
    this.input.on("submit", (_e, cx) => this.commit(cx));
    this.input.on("focus", (_e, cx) => { this.typing = true; cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.typing = false; cx.notify(); });
    this.refresh(cx);
    // Remote repos can't be watched: asked every 5 s (one round trip); local ones are watched.
    this.ticks = 0;
    cx.timer.every(5000, (cx) => { if (location().on || ++this.ticks % 2 === 0) this.refresh(cx); });
  }

  watch(root, cx) {
    if (this.on || this.watched === root) return;
    this.watched = root;
    cx.spawn(async (cx) => {
      try { while (this.watched === root) { await watchFolder(root); if (this.watched === root) this.refresh(cx); } }
      catch { this.watched = null; }
    });
  }

  git(args, read = true) {
    return exec("git", read ? [...READ, ...args] : args, { cwd: this.root, on: this.on });
  }

  publishCount() {
    const n = this.staged.length + this.unstaged.length;
    if (shared("activity.git.count") !== n) setShared("activity.git.count", n);
  }

  refresh(cx) {
    if (this.loading || this.busy) return;
    const { cwd, on } = location(), context = locationKey();
    if (context !== this.context) {
      this.context = context; this.root = null; this.staged = []; this.unstaged = []; this.commits = [];
      this.branch = null; this.ahead = 0; this.behind = 0; this.upstream = null; this.error = null; this.note = null;
      this.watched = null; this.confirm = null; this.limited = false;
      this.message = ""; this.input.set_value("");
    }
    if (!cwd) { this.publishCount(); return; }
    this.loading = true;
    cx.spawn(async (cx) => {
      try {
        const r = await sh(REFRESH, [cwd], { on });
        if (locationKey() !== context) return;
        if (r.code !== 0) {
          this.root = null; this.staged = []; this.unstaged = []; this.commits = [];
          this.error = r.code === 3 ? "Not a git repository" : r.stderr.trim() || "Cannot read this folder"; return;
        }
        const [top, status, branch, sync, log, code] = r.stdout.split(SEP);
        if (code?.trim() !== "0") throw new Error(r.stderr.trim() || "git status failed");
        this.root = top.trim(); this.on = on;
        Object.assign(this, parseStatus(status));
        this.branch = branch.trim() || null;
        if (sync.trim() !== "none") { const [a, b] = sync.trim().split(/\s+/).map(Number); this.ahead = a; this.behind = b; this.upstream = true; }
        else { this.ahead = 0; this.behind = 0; this.upstream = false; }
        this.commits = log.split("\n").filter(Boolean).map((l) => { const [hash, subject, author, when] = l.split("\t"); return { hash, subject, author, when }; });
        this.error = null;
        this.watch(this.root, cx);
      } catch (e) { if (locationKey() === context) this.error = String(e); }
      finally { this.loading = false; this.publishCount(); cx.notify(); }
    });
  }

  // Runs a writing git command, then refreshes.
  act(args, cx, label) {
    if (!this.root || this.busy) return;
    this.busy = label ?? true; this.note = null;
    cx.spawn(async (cx) => {
      try {
        for (const a of Array.isArray(args[0]) ? args : [args]) {
          const r = await this.git(a, false);
          if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
        }
      } catch (e) { this.note = String(e.message ?? e); }
      finally { this.busy = false; this.refresh(cx); cx.notify(); }
    });
    cx.notify();
  }

  stage(f, cx) { this.act(f.status === "D" ? ["rm", "--cached", "--quiet", "--", f.path] : ["add", "--", f.path], cx); }
  unstage(f, cx) { this.act(["restore", "--staged", "--", f.path], cx); }
  discard(f, cx) {
    this.confirm = null;
    if (f.untracked) this.act(["clean", "-f", "-q", "--", f.path], cx);
    else this.act(["restore", "--worktree", "--", f.path], cx);
  }

  commit(cx) {
    const message = this.message.trim();
    if (!message || !this.root || this.busy || this.loading) return;
    // Like VS Code's smart commit: staged changes if any, else everything.
    const steps = this.staged.length ? [["commit", "-m", message]] : [["add", "-A"], ["commit", "-m", message]];
    this.busy = "Committing…"; this.note = null;
    cx.spawn(async (cx) => {
      try {
        for (const a of steps) {
          const r = await this.git(a, false);
          if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
        }
        this.message = ""; this.input.set_value("");
      } catch (e) { this.note = `Commit failed: ${e.message ?? e}`; }
      finally { this.busy = false; this.refresh(cx); cx.notify(); }
    });
    cx.notify();
  }

  openDiff(f, staged) {
    openInEditor({ kind: "diff", path: `${this.root}/${f.path}`, root: this.root, rel: f.path, on: this.on, staged, untracked: Boolean(f.untracked) });
  }

  fileRow(f, staged, t, openSpec) {
    const parts = f.path.split("/"), name = parts.pop(), id = `${staged ? "s" : "w"}-${f.path}`;
    const selected = openSpec?.kind === "diff" && openSpec.rel === f.path && Boolean(openSpec.staged) === staged && openSpec.root === this.root;
    const confirming = this.confirm === id;
    const color = f.status === "U" ? t.ansi2 : statusColor(f.status === "!" ? "U" : f.status, t);
    const hot = this.hovered === id;
    return h_flex().id(`git-${id}`).on_hover((h, cx) => this.hover(id, h, cx)).h(24).flex_none().pl(20).pr(8).gap(6).items_center().cursor_pointer()
      .when(selected, (el) => el.bg(t.selected)).hover((s) => s.bg(t.hover))
      .on_click(() => this.openDiff(f, staged))
      .child(fileImage(f.path, false, false, 14))
      .child(h_flex().flex_1().min_w(0).gap(6).items_baseline()
        .child(div().flex_none().max_w(180).truncate().text_color(f.status === "D" ? t.dim : color).when(f.status === "D", (el) => el.line_through()).child(name))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(parts.join("/"))))
      .when(confirming, (el) => el
        .child(div().text_size(11).text_color(t.ansi1).child("Discard?"))
        .child(iconButton(`yes-${id}`, "check", "Discard changes", (_e, cx) => this.discard(f, cx), { size: 20, color: t.ansi1 }))
        .child(iconButton(`no-${id}`, "x", "Keep", (_e, cx) => { this.confirm = null; cx.notify(); }, { size: 20 })))
      .when(!confirming, (el) => el
        .when(hot, (el) => el.child(h_flex().gap(1)
          .when(!staged, (el) => el
            .child(iconButton(`discard-${id}`, "undo", f.untracked ? "Delete untracked file" : "Discard changes", (_e, cx) => { this.confirm = id; cx.notify(); }, { size: 20 }))
            .child(iconButton(`stage-${id}`, "plus", "Stage", (_e, cx) => this.stage(f, cx), { size: 20 })))
          .when(staged, (el) => el.child(iconButton(`unstage-${id}`, "minus", "Unstage", (_e, cx) => this.unstage(f, cx), { size: 20 })))))
        .child(div().w(12).text_size(11).text_color(color).child(f.status)));
  }

  hover(id, on, cx) {
    if (on) this.hovered = id; else if (this.hovered === id) this.hovered = null; else return;
    cx.notify();
  }

  section(key, title, count, actions, body, t) {
    const open = !this.fold[key];
    return v_flex().flex_none()
      .child(h_flex().id(`sec-${key}`).on_hover((h, cx) => this.hover(`sec-${key}`, h, cx)).h(24).flex_none().pl(6).pr(8).gap(4).items_center().cursor_pointer().hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => { this.fold[key] = open; cx.notify(); })
        .child(icon(`chevron-${open ? "down" : "right"}`, 12).text_color(t.dim))
        .child(div().flex_1().text_size(11).font_semibold().child(title))
        .when(this.hovered === `sec-${key}`, (el) => el.child(h_flex().gap(1).children(actions)))
        .when(count !== null, (el) => el.child(div().px(6).rounded_full().bg(t.raised).text_size(10).text_color(t.muted).child(String(count)))))
      .when(open, (el) => el.children(body));
  }

  render(cx) {
    if (locationKey() !== this.context) this.refresh(cx);
    const t = theme();
    const openSpec = editorSpec();
    const canCommit = Boolean(this.message.trim() && this.root && !this.busy && !this.loading && (this.staged.length || this.unstaged.length));
    const header = viewHeader("Source Control", this.root ? [
      iconButton("git-pull", "arrow-down", this.upstream ? `Pull (${this.behind} behind)` : "Pull", (_e, cx) => this.act(["pull", "--ff-only"], cx, "Pulling…")),
      iconButton("git-push", "arrow-up", this.upstream ? `Push (${this.ahead} ahead)` : "Push (sets upstream)", (_e, cx) =>
        this.act(this.upstream ? ["push"] : ["push", "-u", "origin", this.branch ?? "HEAD"], cx, "Pushing…")),
      iconButton("git-refresh", "refresh", "Refresh", (_e, cx) => this.refresh(cx)),
    ] : []);
    if (!this.root) {
      return v_flex().id("activity-git").size_full().bg(t.chrome).text_color(t.foreground).text_size(13).child(header)
        .child(div().px(14).py(8).text_size(12).text_color(t.dim).child(this.error || (this.loading ? "Loading…" : "Focus a terminal inside a git repository")));
    }
    const sync = this.upstream && (this.ahead || this.behind) ? `  ↓${this.behind} ↑${this.ahead}` : "";
    return v_flex().id("activity-git").size_full().min_h(0).bg(t.chrome).text_color(t.foreground).text_size(13)
      .child(header)
      .child(h_flex().h(22).flex_none().px(14).gap(6).items_center().text_size(11).text_color(t.muted)
        .child(icon("git-branch", 12))
        .child(div().flex_1().min_w(0).truncate().child(`${basename(this.root)} · ${this.branch ?? "?"}${sync}`)))
      .child(v_flex().flex_none().px(10).pt(4).pb(8).gap(6)
        .child(div().id("commit-message").w_full().h(28).px(8).flex().items_center().rounded(5).bg(t.background).border_1()
          .border_color(this.typing ? t.accent : t.border).cursor_text().on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .child(Input.new(this.input).w_full().h_full().text_size(12).text_color(t.foreground)))
        .child(h_flex().id("commit").w_full().h(28).gap(6).justify_center().items_center().rounded(5)
          .bg(canCommit ? t.solid : t.raised).text_color(canCommit ? t.solid_foreground : t.dim).text_size(12)
          .when(canCommit, (el) => el.cursor_pointer().hover((s) => s.opacity(0.9)))
          .on_click((_e, cx) => this.commit(cx))
          .child(icon("check", 13))
          .child(typeof this.busy === "string" ? this.busy : this.staged.length || !this.unstaged.length ? "Commit" : "Commit All")))
      .when(Boolean(this.note), (el) => el.child(div().px(14).pb(6).text_size(11).text_color(t.ansi1).child(this.note)))
      .child(v_flex().id("git-scroll").flex_1().min_h(0).overflow_y_scrollbar().pb(8)
        .when(this.staged.length > 0, (el) => el.child(this.section("staged", "Staged Changes", this.staged.length,
          [iconButton("unstage-all", "minus", "Unstage all", (_e, cx) => this.act(["reset", "-q"], cx), { size: 20 })],
          this.staged.map((f) => this.fileRow(f, true, t, openSpec)), t)))
        .child(this.section("changes", "Changes", this.unstaged.length,
          [iconButton("stage-all", "plus", "Stage all", (_e, cx) => this.act(["add", "-A"], cx), { size: 20 })],
          this.unstaged.length ? this.unstaged.map((f) => this.fileRow(f, false, t, openSpec))
            : [div().pl(26).py(4).text_size(12).text_color(t.dim).child(this.loading ? "Loading…" : "No changes")], t))
        .when(this.limited, (el) => el.child(div().px(14).py(4).text_size(11).text_color(t.dim).child("Showing the first 1,000 changes")))
        .child(this.section("commits", "Commits", null, [],
          this.commits.map((c) => h_flex().id(`c-${c.hash}`).h(22).flex_none().pl(20).pr(10).gap(6).items_center().tooltip(`${c.hash} · ${c.author} · ${c.when}`)
            .child(icon("commit", 12).text_color(t.dim))
            .child(div().flex_1().min_w(0).truncate().text_size(12).child(c.subject))
            .child(div().flex_none().text_size(10).text_color(t.dim).child(c.when.replace(/ ago$/, "")))), t)));
  }
}
