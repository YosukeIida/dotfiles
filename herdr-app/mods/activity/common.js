// Shared helpers for every view of the activity sidebar.
import { div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, focused, run, shared, setShared, layout, theme } from "herdr";

export const MOD = "activity";
export const STACK = "sidebar-views";
export const icon = (name, size = 16) => svg(`mods/${MOD}/icons/${name}.svg`).size(size).flex_none();

// Git reads that write nothing under .git, so a folder watch doesn't loop on our own refresh.
export const READ = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "diff.autoRefreshIndex=false"];

export function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The views of the sidebar stack, in bar order.
export const VIEWS = [
  { id: "view-herdr", icon: "layers", label: "Spaces" },
  { id: "view-agents", icon: "bot", label: "Agents" },
  { id: "view-files", icon: "files", label: "Explorer" },
  { id: "view-search", icon: "search", label: "Search" },
  { id: "view-git", icon: "git-branch", label: "Source Control" },
];

export const activeView = () => find(layout(), STACK)?.active ?? VIEWS[0].id;
export const sidebarWidth = () => find(layout(), "sidebar")?.size?.px ?? Infinity;
export const narrow = () => sidebarWidth() < 160;

export function showView(id) {
  run("layout.select", { stack: STACK, child: id });
  const sidebar = find(layout(), "sidebar");
  if (sidebar?.hidden) run("layout.show", { id: "sidebar" });
  if (narrow()) {
    setShared("sidebar.collapsed", false);
    run("layout.resize", { id: "sidebar", px: shared("sidebar.width") ?? 268 });
  }
}

// Where the sidebar views look: the focused terminal's folder (and its machine).
// A mod pane (our own editor, a viewer) has no folder, so focusing one keeps the
// last terminal's place instead of jumping to the space's first folder.
const last = {};
export function location() {
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  if (pane && pane.terminal === null) {
    if (last[space?.id]) return last[space.id];
    // A terminal beside it in the same tab gives the folder.
    const term = panes().find((p) => p.tab === pane.tab && p.terminal && p.cwd);
    if (term) return { cwd: term.cwd, on: space?.machine ?? null, space: space?.id ?? null };
  }
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  const loc = { cwd: pane?.cwd || f?.cwd || space?.folder || null, on, space: space?.id ?? null };
  if (space) last[space.id] = loc;
  return loc;
}
export const locationKey = () => JSON.stringify(location());

export const basename = (p) => (p ?? "").split(/[\\/]/).filter(Boolean).pop() ?? "";

// The workbench layout has a fixed editor area; other layouts get an editor pane.
export const AREA = "editor-area";
export const hasArea = () => Boolean(find(layout(), AREA));

// Where the shown editor's spec lives in shared "activity.editor": per space for
// the workbench's editor area, else per tab (one editor pane each).
export function editorKey() {
  if (hasArea()) { const s = spaces().find((x) => x.active); return s ? `@area:${s.id}` : null; }
  return focused()?.tab ?? null;
}
export const editorSpec = () => (shared("activity.editor") ?? {})[editorKey()] ?? null;

export function setEditorSpec(key, spec) {
  const all = { ...(shared("activity.editor") ?? {}) };
  if (spec) all[key] = { ...spec, at: Date.now() }; else delete all[key];
  // Keep only tabs and spaces that still exist.
  const live = new Set(spaces().flatMap((s) => [`@area:${s.id}`, ...s.tabs.map((t) => t.id)]));
  for (const k of Object.keys(all)) if (!live.has(k)) delete all[k];
  setShared("activity.editor", all);
}

// Opens a file (or a diff): in the workbench's editor area, else in the editor
// pane of the current tab (reused like VS Code's preview tab, else split in).
// spec: { kind: "file" | "diff", path (absolute), root, rel, on, staged?, line? }
export function openInEditor(spec) {
  const key = editorKey();
  if (!key) return;
  setEditorSpec(key, spec);
  if (hasArea()) {
    if (find(layout(), AREA)?.hidden) run("layout.show", { id: AREA });
    return;
  }
  const editor = panes().find((p) => p.tab === key && p.mod === MOD);
  if (editor) run("pane.focus", { pane: editor.pane });
  else run("pane.split", { direction: "right", mod: MOD, props: { view: "editor", tab: key } });
}

// A small square icon button.
export function iconButton(id, name, tip, action, opts = {}) {
  const t = theme();
  return div().id(id).size(opts.size ?? 22).flex_none().flex().items_center().justify_center().rounded(5)
    .text_color(opts.color ?? t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground)).cursor_pointer()
    .tooltip(tip)
    .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click((e, cx) => { cx.stop_propagation(); action(e, cx); })
    .child(icon(name, opts.icon ?? 14));
}

export function viewHeader(title, actions = []) {
  const t = theme();
  return h_flex().h(34).flex_none().pl(14).pr(8).gap(2).items_center()
    .child(div().flex_1().min_w(0).truncate().font_semibold().child(title))
    .children(actions);
}

// Material Icon Theme の色付きアイコン（upstream の ficons/）は使わない。
// 同梱の Files と同じ単色のアイコンにそろえる。
export const fileImage = (_path, dir = false, open = false, size = 16) =>
  icon(dir ? (open ? "folder-open" : "folder") : "file", size).text_color(theme().muted);

// Segmented control: one button per [value, icon, tip]; the current one is raised.
export function segmented(id, items, current, pick) {
  const t = theme();
  return h_flex().flex_none().p(2).gap(2).rounded(7).border_1().border_color(t.border)
    .children(items.map(([value, name, tip]) => div().id(`${id}-${value}`).w(26).h(20).flex().items_center().justify_center().rounded(5)
      .cursor_pointer().tooltip(tip)
      .when(value === current, (el) => el.bg(t.raised).text_color(t.foreground))
      .when(value !== current, (el) => el.text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground)))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); pick(value, cx); })
      .child(icon(name, 14))));
}

export const statusColor = (s, t) => s === "A" || s === "?" ? t.ansi2 : s === "D" || s === "U" ? t.ansi1 : s === "R" ? t.ansi4 : t.blocked;

// An agent status as Herdr's own lists draw it: a spinner while working, "!"
// when it needs you, a dot when done, a ring when idle, nothing otherwise.
export function statusMark(status, t) {
  if (status === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).mx(1).flex_none().text_color(t.working).spin(900);
  if (status === "blocked") return div().size(14).flex_none().rounded(4).bg(t.blocked + "26").text_size(10.5).font_bold().text_color(t.blocked).flex().items_center().justify_center().child("!");
  if (status === "done") return div().size(7).mx(3).flex_none().rounded(4).bg(t.done ?? t.ansi2);
  if (status === "idle") return div().size(7).mx(3).flex_none().rounded(4).border(1.5).border_color(t.idle ?? t.dim);
  return div().w(14).flex_none();
}

// A program's icon from Herdr's table: a tinted glyph or a full-color picture.
export const programIcon = (p, size, color) => !p?.icon ? null
  : p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
