// The horizontal activity bar: one icon per sidebar view, like VS Code's
// when its activity bar sits on top. Clicking switches the sidebar's stack.
import { div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { run, theme, shared, nextCommand } from "herdr";
import { VIEWS, activeView, showView, narrow, icon } from "./common.js";

export default class Bar {
  init(_props, cx) {
    // Keys: "activity.view-files" etc. (see keys.json in the repo).
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        const v = VIEWS.find((x) => x.id === c || x.id === `view-${c}`);
        if (v) showView(v.id);
        else if (c === "next" || c === "prev") {
          const i = VIEWS.findIndex((x) => x.id === activeView());
          showView(VIEWS[(i + (c === "next" ? 1 : VIEWS.length - 1)) % VIEWS.length].id);
        }
        cx.notify();
      }
    });
  }

  item(v, active, t) {
    const badge = v.id === "view-git" ? shared("activity.git.count") ?? 0 : 0;
    return v_flex().id(`act-${v.id}`).h_full().w(40).flex_none().items_center().justify_center().cursor_pointer()
      .tooltip(v.label)
      .text_color(active ? t.foreground : t.dim).hover((s) => s.text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click(() => showView(v.id))
      .child(div().relative().child(icon(v.icon, 18))
        .when(badge > 0, (el) => el.child(div().absolute().top(-6).left(10).min_w(15).h(15).px(3).rounded_full().bg(t.accent)
          .text_color(t.accent_foreground).text_size(9).font_semibold().flex().items_center().justify_center().child(badge > 99 ? "99+" : String(badge)))))
      .child(div().absolute().bottom(0).left(8).w(24).h(2).rounded(1).bg(active ? t.accent : "#00000000"));
  }

  render() {
    const t = theme();
    const active = activeView();
    if (narrow()) {
      const v = VIEWS.find((x) => x.id === active) ?? VIEWS[0];
      return h_flex().size_full().justify_center().bg(t.chrome).border_b(1).border_color(t.border).child(this.item(v, true, t));
    }
    return h_flex().id("activity-bar").size_full().px(6).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .children(VIEWS.map((v) => this.item(v, v.id === active, t)))
      .child(div().flex_1())
      .child(div().id("act-vscode").size(28).flex_none().flex().items_center().justify_center().rounded(6).cursor_pointer()
        .tooltip("Open folder in VS Code (Ctrl+Shift+G)")
        .text_color(t.dim).hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click(() => run("mod.open", { name: "open-vscode" }))
        .child(icon("vscode", 15)));
  }
}
