// The session an agent is on, from the title it gives its terminal, and how a
// row names it. The same file as in herdr-session-titles (session-titles-agents,
// session-titles-pane); kept here so this mod stands alone.
//
// Each harness titles its terminal its own way (Pi, Claude Code and Codex
// checked running; OpenCode and Gemini CLI from their source):
//   Pi           "π - <session> - <folder>"; "π - <folder>" before it has one
//   Codex        "<spinner> <thread> | <project>", "[ ! ] Action Required | <thread> | <project>";
//                just "<project>" while the thread has no name
//   Claude Code  "<mark> <conversation title>", "Claude Code" before it has one
//   OpenCode     "OC | <session>", "OpenCode" on its home screen
//   Gemini CLI   a state and the folder ("◇  Ready (repo)", "✦  <thought> (repo)"): never a session
// Anything else falls back to its title, when that isn't a path, a prompt, its
// own name or a passing state.

const controls = (s) => String(s ?? "").replace(/[\x00-\x1f\x7f-\x9f]/g, " ");
const squeeze = (s) => controls(s).replace(/\s+/g, " ").trim();
// Spinner frames in front: braille, as Codex and Claude Code draw them.
const unspin = (s) => s.replace(/^[⠀-⣿]+\s*/u, "").trim();
// A spinner, or a status mark such as "✳" or "●" standing on its own; a
// symbol that belongs to the text stays ("#12 bug", "(draft) plan").
const unmark = (s) => unspin(s).replace(/^[^\p{L}\p{N}\s]+(?:\s+|$)/u, "").trim();

const HARNESS = {
  pi: "pi", omp: "pi",
  claude: "claude", "claude-code": "claude",
  codex: "codex",
  opencode: "opencode",
  gemini: "gemini", "gemini-cli": "gemini",
};

// Which harness: what the agent reports (`app`), else Herdr's program table
// (`program.key`), else the title's shape, for an agent Herdr knows by neither.
function harness(t, raw, title) {
  for (const k of [t?.app, t?.program?.key]) {
    const h = k && HARNESS[String(k).toLowerCase()];
    if (h) return h;
  }
  if (/^Gemini CLI \(/.test(title) || /^[◇✋⏲✦] {2}\S/u.test(raw)) return "gemini";
  if (/^π - /.test(title)) return "pi";
  if (/^OC \| /.test(title)) return "opencode";
  if (/^\[ [!.] \] Action Required(?: \| |$)/.test(title)) return "codex";
  return null;
}

const isPath = (s) => /^[~/\\]|^[A-Za-z]:[\\/]|^\S+@\S+:/.test(s);
const isState = (s) => /^(?:working|thinking|loading|connecting|idle|done|ready|busy|waiting)[.…! ]*$/i.test(s);

// The session in `t` (an agent or a pane: anything with title, app and
// program), or "" when its title names none.
export function session(t) {
  const raw = controls(t?.title).trim(), title = squeeze(raw);
  if (!title) return "";
  const h = harness(t, raw, title);
  if (h === "pi") {
    // The folder is the last part, the session everything between.
    const parts = title.split(" - ");
    return parts.length >= 3 ? parts.slice(1, -1).join(" - ").trim() : "";
  }
  if (h === "codex") {
    // The default title is "<thread> | <project>". A custom item list (/title)
    // can't be told apart from it, so anything but two parts reads as none.
    const parts = unspin(title.replace(/^\[ [!.] \] Action Required(?: \| |$)/, "")).split(" | ");
    return parts.length === 2 ? parts[0].trim() : "";
  }
  if (h === "opencode") {
    const m = /^OC \| (.+)$/.exec(title);
    return m ? m[1].trim() : "";
  }
  if (h === "gemini") return "";
  // Claude Code, and any harness this file doesn't know.
  const live = unmark(title);
  if (!live || isPath(live) || isState(live)) return "";
  const lower = live.toLowerCase();
  if ([t.program?.name, t.program?.key, t.app, "claude code"].some((s) => s && String(s).toLowerCase() === lower)) return "";
  return live;
}

// An Agents-list row's text after the space: "<tab> - <session>" when the tab
// has a name someone gave it, the session alone when the tab is unnamed, named
// after the agent's program or the same text, and `fallback` (the shipped
// list's own detail) when there's no session.
export function rowDetail({ tabName, tabNamed, programName, session: s, fallback }) {
  if (!s) return fallback;
  const named = (tabNamed ?? !/^\d+$/.test(tabName ?? "")) && tabName && tabName !== programName && tabName !== s;
  return named ? `${tabName} - ${s}` : s;
}

// A folder for a header: the home folder as "~". On Windows the drive and
// letters may differ in case and "\" and "/" both separate.
export function shortFolder(cwd, home, windows = false) {
  if (!cwd) return "";
  if (!home) return cwd;
  const same = windows ? (a, b) => a.replace(/\//g, "\\").toLowerCase() === b.replace(/\//g, "\\").toLowerCase() : (a, b) => a === b;
  if (same(cwd, home)) return "~";
  const head = cwd.slice(0, home.length), next = cwd[home.length] ?? "";
  return same(head, home) && (next === "/" || (windows && next === "\\")) ? "~" + cwd.slice(home.length) : cwd;
}
