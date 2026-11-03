// cmd-w の tab.close の前に確かめる。同梱の confirm を openOverlay で開かないのは、
// cmd-w を押すたびに confirm が重なるため。自分を dialog にすれば、mod.open が
// 開いている自分を閉じるので重ならない。
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, focused, spaces, theme } from "herdr";

export default class ConfirmClose extends View {
  init(_props, cx) {
    const f = focused();
    this.space = spaces().find((s) => s.id === f?.space);
    this.tab = this.space?.tabs.find((t) => t.id === f?.tab);
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  close() {
    const id = props()?.overlay;
    if (id) closeOverlay(id);
  }

  yes() {
    this.close();
    if (this.tab) run("tab.close", { id: this.tab.id, confirmed: true });
  }

  render() {
    const t = theme();
    const tab = this.tab;
    const title = tab ? `Close tab "${tab.name}"?` : "No tab to close";
    const detail = !tab ? "" : this.space.tabs.length === 1 ? `This is the last tab, so the space "${this.space.name}" closes too.` : "Its terminals end.";
    const button = (id, label, bg, fg, onClick) =>
      h_flex().id(id).h(32).px(14).items_center().rounded(8).border_1().border_color(id === "no" ? t.input : bg).bg(bg).text_color(fg).cursor_pointer().hover((s) => s.opacity(0.88)).on_click(onClick).child(label);
    return v_flex()
      .id("confirm-close")
      .track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.key === "enter") this.yes();
        else if (e.key === "escape") this.close();
        else return;
        cx.stop_propagation();
      })
      .size_full()
      .min_h(0)
      .p(18)
      .gap(12)
      .bg(t.popover)
      .text_size(13)
      .child(h_flex().items_center().child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child(title)).child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(div().flex_1().min_h(0).text_color(t.muted).child(detail))
      .child(
        h_flex()
          .justify_end()
          .gap(8)
          .text_size(12)
          .child(button("no", "Cancel", t.raised, t.foreground, () => this.close()))
          .child(button("yes", "Close", t.solid, t.solid_foreground, () => this.yes())),
      );
  }
}
