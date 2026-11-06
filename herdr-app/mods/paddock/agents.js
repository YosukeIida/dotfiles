// A space's agents, under it in the sidebar as Orca shows them: a traffic light
// (red: needs you, amber: working, green: done, a ring: idle), the program and the
// session it's on, and how long it has been in that state. A click goes to it.
// Folded, the space's row says only the most urgent state (see main.js).
import { div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { run } from "herdr";
import { session } from "./session.js";
import { duration, kidStatus } from "./agents-data.js";
export { duration, kidStatus, tree, byParent, nested, role } from "./agents-data.js";

// What a row says: "Pi · Fix login redirect", or the program alone. A terminal
// named with hc (a team's seat) says its role instead: "Codex · implementation".
export function label(a, termName = "") {
  const name = a.program?.name || a.app || "Agent", s = termName || session(a);
  return s ? { name, session: s } : { name, session: "" };
}

// The tree lines before a nested row, as subRow draws them.
const treeLines = (lines, t, h) => lines.map((l) => div().self_start().mt(-4).w(9).h(h).mr(3).flex_none()
  .when(Boolean(l), (el) => el.border_l(1.5).border_color(t.input))
  .when(l === "└" || l === "├", (el) => el.border_b(1.5).rounded_bl(5)));

// The light: a filled dot for needs-you and done, a pulsing one while working, a ring idle.
export function light(status, t, size = 8) {
  const dot = div().size(size).flex_none().rounded(size / 2);
  if (status === "blocked") return dot.bg(t.blocked);
  if (status === "done") return dot.bg(t.done);
  if (status === "working") return dot.bg(t.working).loop("opacity", { from: 0.35, to: 1, period: 1200 });
  return dot.border(1.5).border_color(t.idle ?? t.dim);
}

function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

// One agent's row; `inset` matches its space's row inside a project. `lines`: it
// has a pane but another agent started it, so it sits under that one's row.
export function agentRow(a, t, { inset = false, since = 0, now = Date.now(), lines = null, termName = "" } = {}) {
  const { name, session: s } = label(a, termName);
  const pic = icon(a.program, 13, t.muted);
  return h_flex().id(`space-agent-${a.address}`).h(24).flex_none().pl(inset ? 51 : 33).pr(8).gap(7).items_center().rounded(6)
    .text_size(12).cursor_pointer()
    .when(Boolean(lines), (el) => el.child(h_flex().flex_none().self_stretch().children(treeLines(lines, t, 17))))
    .when(a.focused, (el) => el.bg(t.selected))
    .when(!a.focused, (el) => el.hover((st) => st.bg(t.hover)))
    .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click((_e, cx) => { cx.stop_propagation(); run("pane.focus", { pane: a.pane }); })
    .child(light(a.status, t))
    .when(Boolean(pic), (el) => el.child(pic))
    .child(div().flex_none().max_w(110).truncate().text_color(a.status === "idle" ? t.muted : t.foreground).child(name))
    .when(Boolean(s), (el) => el.child(div().flex_none().text_color(t.dim).child("·"))
      .child(div().min_w(0).flex_1().truncate().text_color(t.muted).child(s)))
    .when(!s, (el) => el.child(div().flex_1()))
    .when(since > 0, (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(duration(now - since))));
}

// A sub-agent's row under its parent's: tree lines, its light, what it runs. A click peeks at it.
export function subRow({ k, lines }, t, { inset = false, listed }) {
  const pic = icon(k.program, 12, t.muted);
  return h_flex().id(`space-sub-${k.address}`).h(22).flex_none().pl(inset ? 51 : 33).pr(8).items_center().rounded(6)
    .text_size(11.5).cursor_pointer().hover((st) => st.bg(t.hover))
    .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click((_e, cx) => { cx.stop_propagation(); run("terminal.peek", { terminal: k.address }); })
    .children(treeLines(lines, t, 15))
    .child(div().mr(6).child(light(kidStatus(k, listed), t, 7)))
    .when(Boolean(pic), (el) => el.child(div().mr(6).child(pic)))
    .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(k.name || k.template || k.program?.name || k.address));
}
