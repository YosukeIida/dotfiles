// The sidebar's own popups, opened as overlays of this mod (props.role):
//   "project-menu"  a project's right-click menu: New space here, Edit project…,
//                   Remove project
//   "edit"          a project's name and folder
//   "add"           a new project: its name and folder (Choose… opens the system's
//                   folder picker on this computer; another machine's is typed)
// Styled like Herdr's menu and prompt.
import { div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { props, closeOverlay, openOverlay, run, theme, shared, setShared, exec, home, pickFolder } from "herdr";
import { projectList, addProject, removeProject, editProject, taken } from "./projects.js";

export const STORE = "paddock.projects";
export const store = () => shared(STORE) ?? {};
export const project = (machine, id) => projectList(store(), machine).find((p) => p.id === id);
export const newSpaceIn = (p, machine) => run("space.new", { folder: p.root, machine: machine ?? "" });

// A folder's real path on its machine, or null when there's none. There, the shell
// expands "~" and resolves the path. Here, a program can't start in a missing folder
// (exec rejects), whatever it would have said, in whatever language.
async function existing(path, machine) {
  if (machine) {
    const script = 'p=$1; case $p in "~"|"~/"*) p=$HOME${p#"~"};; esac; cd -- "$p" 2>/dev/null && pwd -P';
    const r = await exec("sh", ["-c", script, "sh", path], { on: machine }).catch(() => null);
    return r?.code === 0 ? r.stdout.trim() : null;
  }
  const full = path.replace(/^~(?=$|[\\/])/, home());
  const r = await exec("git", ["rev-parse", "--git-dir"], { cwd: full }).catch(() => null);
  return r ? full : null;
}

export class Overlay {
  init(cx) {
    const p = props();
    this.at = 0;
    this.error = null;
    this.handle = cx.focus_handle();
    if (p.role === "project-menu") { this.handle.focus(); return; }
    const was = p.role === "edit" ? project(p.machine, p.id) : null;
    const field = (value, placeholder) => {
      const input = InputState.new({ value, placeholder });
      input.on("change", (_e, cx) => { this.error = null; cx.notify(); });
      input.on("submit", (_e, cx) => this.submit(cx));
      input.on("focus", (_e, cx) => { this.focus = input; cx.notify(); });
      return input;
    };
    this.name = field(was?.name ?? "", "");
    this.path = field(was?.root ?? "", p.machine ? "~/code/app" : "");
    const first = this.name ?? this.path;
    const value = first.value();
    if (value) first.set_selected_range({ start: 0, end: value.length });
    this.focus = first;
    first.focus();
    cx.timer.after(600, () => first.focus());
  }

  items() {
    const { machine, id } = props();
    return [
      { label: "New space here", icon: "plus", run: () => { const p = project(machine, id); if (p) newSpaceIn(p, machine); } },
      { label: "Edit project…", icon: "square-pen", run: () => openEdit(machine, id) },
      { label: "Remove project", icon: "x", line: true, run: () => setShared(STORE, removeProject(store(), machine, id)) },
    ];
  }

  choose(i) {
    const it = this.items()[i];
    if (!it) return;
    closeOverlay(props().overlay);
    it.run();
  }

  pick(cx) {
    cx.spawn(async (cx) => {
      const picked = await pickFolder({ prompt: "Choose the project's folder" });
      if (picked) { this.path.set_value(picked); this.error = null; }
      cx.notify();
    });
  }

  submit(cx) {
    const p = props();
    if (this.busy) return;
    const path = this.path.value().trim(), name = this.name?.value().trim() ?? "";
    if (!path) { this.error = "Type the folder's path."; cx.notify(); return; }
    const was = p.role === "edit" ? project(p.machine, p.id) : null;
    this.busy = true;
    cx.notify();
    cx.spawn(async (cx) => {
      // An unchanged folder isn't asked for again (its machine may be away).
      const root = was && path === was.root ? was.root : await existing(path, p.machine);
      this.busy = false;
      if (!root) { this.error = `No folder at ${path}${p.machine ? ` on ${p.machine}` : ""}.`; cx.notify(); return; }
      if (taken(store(), p.machine, root, was?.id ?? null)) { this.error = "Another project has this folder."; cx.notify(); return; }
      setShared(STORE, was ? editProject(store(), p.machine, p.id, { name, root }) : addProject(store(), p.machine, root, { name }));
      closeOverlay(p.overlay);
    });
  }

  menuView(t, p) {
    const list = this.items();
    return v_flex().id("project-menu").track_focus(this.handle).w_full().min_h(0).p(5).bg(t.popover).text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter") this.choose(this.at);
        else if (e.key === "escape") closeOverlay(p.overlay);
        else return;
        cx.notify();
      })
      .children(list.map((it, i) => v_flex()
        .when(Boolean(it.line), (el) => el.child(div().mx(7).my(4).h(1).bg(t.border)))
        .child(h_flex().id(`pm-${i}`).h(31).px(8).gap(9).rounded(7).items_center().text_color(t.foreground)
          .when(i === this.at, (el) => el.bg(t.selected)).hover((s) => s.bg(t.hover))
          .on_click(() => this.choose(i))
          .child(svg(`mods/workspace-chrome/${it.icon}.svg`).size(14).flex_none().text_color(t.muted))
          .child(div().flex_1().child(it.label)))));
  }

  render() {
    const t = theme(), p = props();
    if (p.role === "project-menu") return this.menuView(t, p);
    const edit = p.role === "edit";
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).flex_none().items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover((s) => s.opacity(0.88)).on_click(action).child(text);
    const field = (label, input, hint, extra = null) => v_flex().gap(6)
      .child(div().text_size(12).font_medium().text_color(t.muted).child(label))
      .child(h_flex().gap(8)
        .child(div().flex_1().min_w(0).h(34).px(10).flex().items_center().rounded(8).border_1()
          .border_color(this.focus === input ? t.accent : t.input).bg(t.background)
          .child(Input.new(input).w_full().text_size(13).text_color(t.foreground)))
        .when(Boolean(extra), (el) => el.child(extra)))
      .when(Boolean(hint), (el) => el.child(div().text_size(11.5).text_color(t.dim).child(hint)));
    const choose = p.machine ? null : button("pd-choose", "Choose…", false, (_e, cx) => this.pick(cx));
    return v_flex().id("project-dialog").track_focus(this.handle)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(p.overlay); cx.stop_propagation(); } })
      .w_full().min_h(0).p(20).gap(16).bg(t.popover).text_color(t.foreground)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().child(edit ? "Edit project" : p.machine ? `New project on ${p.machine}` : "New project"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(field("Name", this.name, edit ? "Empty goes back to the folder's name." : "Empty: the folder's name."))
      .child(field("Folder", this.path, p.machine ? `A path on ${p.machine}, such as ~/code/app.` : "Spaces working in it belong to the project; its + opens one there.", choose))
      .when(Boolean(this.error), (el) => el.child(div().text_size(12).text_color(t.blocked).child(this.error)))
      .child(h_flex().pt(4).gap(8).justify_end()
        .child(button("pd-cancel", "Cancel", false, () => closeOverlay(p.overlay)))
        .child(button("pd-save", this.busy ? "Checking…" : edit ? "Save" : "Add", true, (_e, cx) => this.submit(cx))));
  }
}

const open = (p, how) => openOverlay({ mod: "paddock", ...how, props: p });
export const openMenu = (machine, id) => open({ role: "project-menu", machine, id }, { kind: "popup", width: 200, height: 112 });
export const openEdit = (machine, id) => open({ role: "edit", machine, id }, { kind: "dialog", width: 460, height: 300 });
export const openAdd = (machine) => open({ role: "add", machine }, { kind: "dialog", width: 460, height: 300 });
