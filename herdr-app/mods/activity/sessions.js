// Coding-agent sessions, read on the machine they ran on, for one folder:
//   Claude Code  ~/.claude/projects/*/*.jsonl
//   Codex        ~/.codex/sessions/**/rollout-*.jsonl (+ session_index.jsonl names)
//   pi / omp     ~/.pi/agent/sessions/*/*.jsonl, ~/.omp/agent/sessions/*/*.jsonl
//   opencode     ~/.local/share/opencode/opencode.db or storage/session/*/*.json
// One python3 run picks the files whose cwd is inside the folder (through symlinks),
// reads only their head and tail (they can be tens of MB) and prints a JSON list,
// newest first, at most `limit` per agent:
//   { agent, id, title, preview (first prompt), last (last prompt), cwd, branch,
//     model, updated (unix s), size (bytes), here (inside the folder) }
// `extra` folders (where live agents run) add their newest few sessions with
// here: false, so a running agent gets its title and model.
// "sshpass -p <password>" typed into a prompt is masked.
import { sh } from "./io.js";

const SCAN = String.raw`import json, os, glob, sys, re
LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 60
MAIN = (sys.argv[2] if len(sys.argv) > 2 else "").rstrip("/") or ("/" if len(sys.argv) > 2 and sys.argv[2] else "")
EXTRA = [f.rstrip("/") or "/" for f in (json.loads(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else []) if f]
EXTRA_CAP = 4
H = os.path.expanduser("~")
out = []

# Folders match through symlinks too (a space may open /home/me/repos/x while the
# agent recorded the real path, or the other way round).
def real(p):
    try: return os.path.realpath(p)
    except Exception: return p
MAINS = {MAIN, real(MAIN)} if MAIN else set()
EXTRAS = {g for f in EXTRA for g in (f, real(f))}
REAL = {}

def inside(path, f):
    return bool(path) and (f == "/" or path == f or path.startswith(f + "/"))

def where(cwd):
    if not cwd: return None
    if cwd not in REAL: REAL[cwd] = real(cwd)
    both = (cwd, REAL[cwd])
    if any(inside(c, f) for c in both for f in MAINS): return "main"
    if any(inside(c, f) for c in both for f in EXTRAS): return "extra"
    return None

class Quota:
    def __init__(self): self.n = {"main": 0, "extra": 0}
    def full(self): return (not MAIN or self.n["main"] >= LIMIT) and (not EXTRA or self.n["extra"] >= EXTRA_CAP)
    def take(self, cwd):
        k = where(cwd)
        if not k or self.n[k] >= (LIMIT if k == "main" else EXTRA_CAP): return False
        self.n[k] += 1
        return True

def rd(path, start, n):
    with open(path, "rb") as f:
        if start < 0:
            f.seek(0, 2); size = f.tell(); f.seek(max(0, size + start))
        else: f.seek(start)
        return f.read(n).decode("utf-8", "replace").splitlines()

def objs(lines):
    for l in lines:
        try:
            o = json.loads(l)
            if isinstance(o, dict): yield o
        except Exception: pass

def text_of(c):
    if isinstance(c, str): return c
    if isinstance(c, list):
        return " ".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") in ("text", "input_text"))
    return ""

def prompt(s):
    s = (s or "").strip()
    if not s or s.startswith("<") or s.startswith("Caveat:") or s.startswith("[Request interrupted") or s.startswith("# AGENTS.md instructions"): return ""
    s = re.sub(r"(sshpass\s+-p\s*)\S+", r"\1***", s)  # never show a password typed into a prompt
    return re.sub(r"\s+", " ", s)[:200]

def newest(files):
    files = [(f, os.path.getmtime(f)) for f in files]
    files.sort(key=lambda x: -x[1])
    return [f for f, _ in files]

def blank(agent, f, id=""):
    st = os.stat(f)
    return {"agent": agent, "id": id, "updated": int(st.st_mtime), "size": st.st_size,
            "cwd": "", "branch": "", "title": "", "preview": "", "last": "", "model": ""}

def enc(path): return re.sub(r"[^A-Za-z0-9]", "-", path)

# Claude Code: ~/.claude/projects/<cwd, non-alphanumerics as "-">/<id>.jsonl
def claude():
    pre = [enc(f) for f in MAINS | EXTRAS]
    dirs = [d for d in glob.glob(os.path.join(H, ".claude/projects/*")) if any(os.path.basename(d).startswith(p) for p in pre)]
    files = [f for d in dirs for f in glob.glob(os.path.join(glob.escape(d), "*.jsonl")) if not os.path.basename(f).startswith("agent-")]
    q = Quota()
    for f in newest(files):
        if q.full(): break
        s = blank("claude", f, os.path.basename(f)[:-6])
        side = False
        for o in objs(rd(f, 0, 262144)):
            if not s["cwd"] and o.get("cwd"): s["cwd"] = o["cwd"]; s["branch"] = o.get("gitBranch") or ""
            if o.get("isSidechain"): side = True
            if not s["preview"] and o.get("type") == "user" and not o.get("isMeta"):
                s["preview"] = prompt(text_of((o.get("message") or {}).get("content")))
            if s["cwd"] and s["preview"]: break
        if side and not s["preview"]: continue
        if s["cwd"] and not where(s["cwd"]): continue
        custom = ""
        for o in reversed(list(objs(rd(f, -1048576, 1048576)))):
            t = o.get("type")
            if t == "custom-title" and not custom: custom = o.get("customTitle") or o.get("title") or ""
            elif t in ("ai-title", "summary") and not s["title"]: s["title"] = o.get("aiTitle") or o.get("summary") or ""
            elif t == "last-prompt" and not s["last"]: s["last"] = prompt(o.get("lastPrompt"))
            elif t == "assistant" and not s["model"]:
                m = (o.get("message") or {}).get("model") or ""
                if m and not m.startswith("<"): s["model"] = m
            if not s["cwd"] and o.get("cwd"): s["cwd"] = o["cwd"]
            if custom and s["title"] and s["model"] and s["last"]: break
        s["title"] = custom or s["title"]
        if not (s["title"] or s["preview"] or s["last"]): continue
        if q.take(s["cwd"]): out.append(s)

# Codex: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl; the cwd is in the first line.
CWD = re.compile(r'"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"')
def codex():
    files = glob.glob(os.path.join(H, ".codex/sessions/*/*/*/rollout-*.jsonl"))
    names = {}
    try:
        for o in objs(open(os.path.join(H, ".codex/session_index.jsonl"), encoding="utf-8", errors="replace")):
            if o.get("id") and o.get("thread_name"): names[o["id"]] = o["thread_name"]
    except OSError: pass
    q = Quota()
    for f in newest(files):
        if q.full(): break
        m = CWD.search("\n".join(rd(f, 0, 8192)))
        try: cwd = json.loads('"' + m.group(1) + '"') if m else ""
        except Exception: cwd = ""
        if not where(cwd): continue
        s = blank("codex", f)
        sub = False
        for o in objs(rd(f, 0, 262144)):
            p = o.get("payload") or {}
            if o.get("type") == "session_meta" and not s["id"]:
                s["id"] = p.get("id") or p.get("session_id") or ""; s["cwd"] = p.get("cwd") or ""
                s["branch"] = (p.get("git") or {}).get("branch") or ""
                src = p.get("thread_source"); sub = bool(src and src != "user")
            elif o.get("type") == "turn_context" and not s["model"]: s["model"] = p.get("model") or ""
            elif o.get("type") == "event_msg" and p.get("type") == "thread_settings_applied" and not s["model"]: s["model"] = (p.get("thread_settings") or {}).get("model") or ""
            elif not s["preview"] and ((o.get("type") == "response_item" and p.get("type") == "message" and p.get("role") == "user") or (o.get("type") == "event_msg" and p.get("type") == "user_message")):
                s["preview"] = prompt(p.get("message") if p.get("type") == "user_message" else text_of(p.get("content")))
            if s["id"] and s["model"] and s["preview"]: break
        if sub or not s["id"]: continue
        if not s["model"]:
            for o in reversed(list(objs(rd(f, -262144, 262144)))):
                if o.get("type") == "turn_context": s["model"] = (o.get("payload") or {}).get("model") or ""; break
        s["title"] = names.get(s["id"], "")
        if (s["title"] or s["preview"]) and q.take(s["cwd"]): out.append(s)

# pi and omp (its fork): <sessions>/<one folder per cwd>/<time>_<id>.jsonl. The first
# line is {"type":"session", id, cwd, title?}; the folder names are lossy, so each
# folder's cwd is read from the first line of one of its files.
def pi_like(agent, roots):
    files = []
    for root in roots:
        for d in glob.glob(os.path.join(root, "*")):
            fs = glob.glob(os.path.join(glob.escape(d), "*.jsonl"))
            if not fs: continue
            head = next(objs(rd(fs[0], 0, 4096)), {})
            if where(head.get("cwd") or ""): files += fs
    q = Quota()
    for f in newest(files):
        if q.full(): break
        s = blank(agent, f)
        def model(o):
            m = o.get("modelId") or o.get("model") or ""
            return m.split("/", 1)[1] if "/" in m and not o.get("modelId") else m
        def user(o):
            msg = o.get("message") or {}
            return prompt(text_of(msg.get("content"))) if o.get("type") == "message" and msg.get("role") == "user" else ""
        for o in objs(rd(f, 0, 262144)):
            t = o.get("type")
            if t == "session" and not s["id"]:
                s["id"] = o.get("id") or ""; s["cwd"] = o.get("cwd") or ""; s["title"] = o.get("title") or o.get("name") or ""
            elif t == "model_change" and not s["model"]: s["model"] = model(o)
            elif not s["preview"]: s["preview"] = user(o)
            if s["id"] and s["model"] and s["preview"]: break
        if not s["id"] or not where(s["cwd"]): continue
        latest = ""
        for o in reversed(list(objs(rd(f, -1048576, 1048576)))):
            t = o.get("type")
            if t == "model_change" and not latest: latest = model(o)
            elif t == "session_info" and not s["title"]: s["title"] = o.get("name") or o.get("title") or ""
            elif not s["last"]: s["last"] = user(o)
            if latest and s["last"]: break
        s["model"] = latest or s["model"]
        if s["last"] == s["preview"]: s["last"] = ""
        if (s["title"] or s["preview"]) and q.take(s["cwd"]): out.append(s)

def pi(): pi_like("pi", [os.path.join(os.environ.get("PI_CODING_AGENT_DIR") or os.path.join(H, ".pi/agent"), "sessions")])
def omp(): pi_like("omp", [os.path.join(H, ".omp/agent/sessions")])

# opencode: sessions in $XDG_DATA_HOME/opencode/opencode.db (newer) or as JSON files
# under storage/session/ (older). Child sessions (sub-agents) have a parent id.
def opencode():
    base = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(H, ".local/share"), "opencode")
    rows = []
    db = os.path.join(base, "opencode.db")
    if os.path.exists(db):
        import sqlite3
        con = sqlite3.connect("file:" + db + "?mode=ro", uri=True, timeout=2)
        con.row_factory = sqlite3.Row
        cols = [r[1] for r in con.execute("PRAGMA table_info(session)")]
        upd = next((c for c in ("time_updated", "updated_at", "time_created") if c in cols), None)
        for r in con.execute("SELECT * FROM session" + (" ORDER BY %s DESC" % upd if upd else "")):
            r = dict(r)
            if r.get("parent_id") or r.get("time_archived"): continue
            rows.append({"id": r.get("id"), "title": r.get("title"), "directory": r.get("directory"), "updated": r.get(upd) if upd else 0})
        con.close()
    for f in glob.glob(os.path.join(base, "storage/session/*/*.json")):
        try: o = json.load(open(f, encoding="utf-8"))
        except Exception: continue
        if not isinstance(o, dict) or not o.get("id") or o.get("parentID"): continue
        tm = o.get("time") or {}
        rows.append({"id": o["id"], "title": o.get("title"), "directory": o.get("directory"), "updated": tm.get("updated") or tm.get("created") or os.path.getmtime(f)})
    seen = set(); q = Quota()
    for r in sorted(rows, key=lambda r: -(r["updated"] or 0)):
        if r["id"] in seen or q.full(): continue
        seen.add(r["id"])
        u = r["updated"] or 0
        s = {"agent": "opencode", "id": r["id"], "updated": int(u / 1000 if u > 1e11 else u), "size": 0, "cwd": r["directory"] or "",
             "branch": "", "title": r["title"] or "", "preview": "", "last": "", "model": ""}
        if s["title"] and q.take(s["cwd"]): out.append(s)

for fn in (claude, codex, pi, omp, opencode):
    try: fn()
    except Exception as e: sys.stderr.write("%s: %s\n" % (fn.__name__, e))
for s in out:
    s["here"] = where(s["cwd"]) == "main"
    s["title"] = re.sub(r"(sshpass\s+-p\s*)\S+", r"\1***", s["title"] or "")
out.sort(key=lambda s: -s["updated"])
print(json.dumps(out, ensure_ascii=False))
`;

// How each agent shows and resumes. Icons are Herdr's program icons (tint: a
// one-color glyph drawn in the text color). fork: null when the CLI can't.
export const AGENTS = {
  claude: { name: "Claude Code", icon: "icons/claude.svg", tint: false, resume: (id) => ["claude", "--resume", id], fork: (id) => ["claude", "--resume", id, "--fork-session"] },
  codex: { name: "Codex", icon: "icons/codex.svg", tint: false, resume: (id) => ["codex", "resume", id], fork: (id) => ["codex", "fork", id] },
  pi: { name: "pi", icon: "icons/pi.svg", tint: true, resume: (id) => ["pi", "--session", id], fork: (id) => ["pi", "--fork", id] },
  omp: { name: "omp", icon: "icons/pi.svg", tint: true, resume: (id) => ["omp", "--resume", id], fork: null },
  opencode: { name: "opencode", icon: "icons/opencode.svg", tint: true, resume: (id) => ["opencode", "--session", id], fork: null },
};

/** Sessions in `folder` (plus a few in each `extra` folder) on a machine (null: this
 *  one). Throws a short message on failure. */
export async function loadSessions(on, folder, extra = [], limit = 60) {
  const r = await sh('command -v python3 >/dev/null 2>&1 || { echo "python3 is needed to read agent sessions" >&2; exit 4; }; exec python3 -I -c "$1" "$2" "$3" "$4"',
    [SCAN, String(limit), folder ?? "", JSON.stringify(extra)], { on: on ?? undefined });
  if (r.code !== 0) throw new Error((r.stderr || "").trim().split("\n")[0] || `exit ${r.code}`);
  return JSON.parse(r.stdout || "[]");
}

/** "now", "12m", "3h", "6d", "5w" since a unix time in seconds (or ms). */
export function ago(t) {
  if (!t) return "";
  const s = Math.max(0, (Date.now() - (t > 1e12 ? t : t * 1000)) / 1000);
  return s < 60 ? "now" : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : s < 604800 ? `${Math.floor(s / 86400)}d` : `${Math.floor(s / 604800)}w`;
}
