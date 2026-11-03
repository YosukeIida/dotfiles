// VS Code–style activity sidebar for Herdr. One mod, several views, chosen by
// the block's props: { view: "bar" | "files" | "search" | "git" | "spaces" | "agents" | "editor" | ... }.
//   bar    — the horizontal activity bar that switches the sidebar stack
//   files  — Explorer: file tree with git marks
//   search — text search (rg / git grep / grep)
//   git    — Source Control: stage, unstage, discard, commit, pull, push, log
//   spaces — Spaces by machine (this computer, ssh machines): tabs, Open Folder…
//   agents — running agents with title / model / status, and resumable session history
//   editor — the editor area (or a pane): text, diffs, images, PDFs, media
//   titlebar / panelbar — the workbench's title bar and terminal panel header
//   menu / fileprompt — the Explorer's right-click popup and its dialogs
import { View, div } from "gpui-kit";
import { props as herdrProps } from "herdr";
import Bar from "./bar.js";
import Files from "./files.js";
import Browse from "./browse.js";
import Search from "./search.js";
import Git from "./git.js";
import EditorPane from "./editor.js";
import Titlebar from "./titlebar.js";
import PanelBar from "./panelbar.js";
import Spaces from "./spaces.js";
import Agents from "./agents.js";
import { FileMenu, FilePrompt } from "./fileops.js";

const VIEWS = { bar: Bar, files: Files, browse: Browse, search: Search, git: Git, editor: EditorPane, titlebar: Titlebar, panelbar: PanelBar, spaces: Spaces, agents: Agents, remote: Spaces, menu: FileMenu, fileprompt: FilePrompt };

export default class Activity extends View {
  init(initProps, cx) {
    const p = { ...(initProps ?? {}), ...(herdrProps() ?? {}) };
    this.view = p.view;
    const Impl = VIEWS[p.view] ?? null;
    this.impl = Impl ? new Impl() : null;
    this.impl?.init(p, cx);
  }
  render(cx) {
    return this.impl ? this.impl.render(cx) : div().p(12).child(`activity: unknown view "${this.view}"`);
  }
  async close() { this.impl?.release?.(); }
}
