// File and process helpers that work the same here and on an ssh machine.
//
// Herdr's exec() is text-only (binary output is mangled), has a 30 s limit and
// costs a round trip per call on a remote machine (0.1–0.5 s). So:
//  - several reads go out as one `sh` script and come back in sections;
//  - binary files travel through `hc exec --on <machine> -- cat`, redirected to a
//    file by a local shell, in the background so big files can take longer than 30 s;
//  - saving a remote file pipes it through `hc exec -i`, after checking the file
//    there still is what was opened (its md5).
// Pictures shown with image() must sit under the app's folder: they go to
// mods/activity/.cache (hidden, so Herdr doesn't reload the mod when it changes).
import { exec, appHome } from "herdr";
import * as fs from "fs/promises";

export const SEP = "\n@@HERDR-SEP@@\n";
export const CACHE_REL = "mods/activity/.cache";
export const cacheDir = () => `${appHome()}/${CACHE_REL}`;

let made = false, counter = 0;
export async function ensureCache() {
  if (made) return;
  await exec("mkdir", ["-p", cacheDir()]);
  made = true;
  // Leftovers of earlier sessions.
  exec("find", [cacheDir(), "-mindepth", "1", "-mmin", "+720", "-delete"]).catch(() => {});
}
// A fresh name per render: the app caches images by path.
export const unique = (ext = "") => `${Date.now().toString(36)}-${(counter++).toString(36)}${ext ? "." + ext : ""}`;

/** Runs a POSIX shell script with positional args, here or on `on`. */
export const sh = (script, args = [], opts = {}) => exec("sh", ["-c", script, "sh", ...args], opts);

const q = (s) => "'" + String(s).replaceAll("'", "'\\''") + "'";

/** Size and change time of a file: { size, mtime } or null when it's gone. */
export async function stat(path, on) {
  const r = await sh('stat -c "%s %Y" "$1" 2>/dev/null || stat -f "%z %m" "$1"', [path], { on }).catch(() => null);
  if (!r || r.code !== 0) return null;
  const [size, mtime] = r.stdout.trim().split(/\s+/).map(Number);
  return { size, mtime };
}

/**
 * Puts a copy of a file under the cache and resolves with its path, absolute.
 * Local files are copied (fast); remote ones are downloaded in the background
 * and `progress(bytes)` is called while they come.
 */
export async function fetchToCache(path, on, ext, progress) {
  await ensureCache();
  const out = `${cacheDir()}/${unique(ext)}`;
  if (!on) {
    const r = await exec("cp", ["--", path, out]);
    if (r.code !== 0) throw new Error(r.stderr.trim() || "Cannot read the file");
    return out;
  }
  // Detached, so it outlives this exec's 30 s; the poll below follows it.
  const job = `hc exec --timeout 600 --on ${q(on)} -- cat ${q(path)} > ${q(out + ".part")} 2> ${q(out + ".err")} && mv ${q(out + ".part")} ${q(out)} || { rm -f ${q(out + ".part")}; [ -s ${q(out + ".err")} ] || echo "Download failed" > ${q(out + ".err")}; }`;
  await sh('(setsid sh -c "$1" || sh -c "$1") </dev/null >/dev/null 2>&1 &', [job]);
  for (let i = 0; i < 6000; i++) {
    // The wait is in the shell: mods have no setTimeout outside a view's cx.
    const r = await sh('sleep 0.4; if [ -e "$1" ]; then echo done; elif [ -s "$1.err" ] && ! [ -e "$1.part" ]; then echo err; cat "$1.err"; else echo part; stat -c %s "$1.part" 2>/dev/null; fi', [out]);
    const [head, ...rest] = r.stdout.split("\n");
    if (head === "done") { exec("rm", ["-f", out + ".err"]).catch(() => {}); return out; }
    if (head === "err") throw new Error(rest.join("\n").trim() || "Download failed");
    progress?.(Number(rest[0]) || 0);
    // The job died without leaving a file or an error.
    if (i > 5 && !rest[0]) {
      const alive = await sh('[ -e "$1.part" ] || [ -e "$1" ]', [out]);
      if (alive.code !== 0) throw new Error("Download failed");
    }
  }
  throw new Error("Download took too long");
}

// Run on the remote machine: refuses if the file changed since it was opened,
// then writes stdin into it in place (keeping its owner and permissions).
const REMOTE_SAVE = `p=$1; want=$2
h() { if command -v md5sum >/dev/null 2>&1; then md5sum | cut -c1-32; else md5 -q; fi; }
if [ "$want" = new ]; then [ -e "$p" ] && { echo "A file with this name exists now" >&2; exit 3; }
else cur=$(h < "$p" 2>/dev/null); [ "$cur" = "$want" ] || { echo "The file changed on the machine since it was opened" >&2; exit 3; }; fi
tmp=$(mktemp) || exit 4
cat > "$tmp" || { rm -f "$tmp"; exit 4; }
cat "$tmp" > "$p"; s=$?; rm -f "$tmp"; exit $s`;

/** Saves text to a file on `on`, unless it no longer matches `expected` (null: a new file). */
export async function writeRemoteText(path, text, expected, on) {
  await ensureCache();
  const up = `${cacheDir()}/${unique("up")}`, orig = `${cacheDir()}/${unique("orig")}`;
  await fs.writeFile(up, text);
  if (expected !== null) await fs.writeFile(orig, expected);
  const r = await sh(
    'if [ -e "$4" ]; then want=$(md5sum < "$4" | cut -c1-32); else want=new; fi; rm -f "$4"; ' +
    'hc exec -i --on "$1" -- sh -c "$5" sh "$2" "$want" < "$3"; s=$?; rm -f "$3"; exit $s',
    [on, path, up, orig, REMOTE_SAVE]);
  if (r.code !== 0) throw new Error(r.stderr.trim() || `Save failed (${r.code})`);
}

// ---- Background jobs -------------------------------------------------------

/**
 * Runs a shell script detached (so it can take longer than exec's 30 s) and
 * resolves with its stdout once it ends; rejects with its stderr if it fails.
 * `tick()` is called every poll, for a "still working" display.
 */
export async function job(script, args = [], tick) {
  await ensureCache();
  const d = `${cacheDir()}/${unique("job")}`;
  await sh('d=$1; shift; S=; command -v setsid >/dev/null 2>&1 && S=setsid; ' +
    '$S sh -c \'d=$1; shift; s=$1; shift; sh -c "$s" sh "$@" > "$d.out" 2> "$d.err"; echo $? > "$d.code"\' sh "$d" "$@" </dev/null >/dev/null 2>&1 &',
    [d, script, ...args]);
  for (let i = 0; ; i++) {
    const r = await sh('sleep 0.3; [ -e "$1.code" ] && cat "$1.code"', [d]);
    if (r.code === 0 && r.stdout.trim() !== "") break;
    tick?.(i);
  }
  const r = await sh('c=$(cat "$1.code"); cat "$1.out"; printf "\\n@@HERDR-SEP@@\\n%s\\n@@HERDR-SEP@@\\n" "$c"; tail -c 4000 "$1.err"; rm -f "$1.code" "$1.out" "$1.err"', [d]);
  const [out, code, err] = r.stdout.split(SEP);
  if (Number(code) !== 0) throw new Error(err?.trim() || `Failed (${code.trim()})`);
  return out;
}

// Shell helpers every transfer script starts with: R runs a command where a
// file is (here when the machine is ""), RI the same with stdin passed on.
const PRELUDE = `R() { m=$1; shift; if [ -z "$m" ]; then "$@"; else hc exec --timeout 600 --on "$m" -- "$@"; fi; }
RI() { m=$1; shift; if [ -z "$m" ]; then "$@"; else hc exec -i --timeout 600 --on "$m" -- "$@"; fi; }
`;

// Unpacks a tar from stdin into folder $1 as name $2 ($3 is the name inside the tar).
const UNTAR = 'd=$1; t=$(mktemp -d "$d/.herdr-in.XXXXXX") || exit 1; tar -xf - -C "$t" || { rm -rf "$t"; exit 1; }; mv "$t/$3" "$d/$2" && rmdir "$t"';

// Picks names that don't exist yet in folder $1, VS Code style: "a.txt", "a copy.txt", "a copy 2.txt".
const FREE_NAMES = `d=$1; shift
for n; do
  if [ ! -e "$d/$n" ] && [ ! -L "$d/$n" ]; then echo "$n"; continue; fi
  case "$n" in .*.*|[!.]*.*) stem=\${n%.*}; ext=.\${n##*.};; *) stem=$n; ext=;; esac
  c="$stem copy$ext"; i=2
  while [ -e "$d/$c" ] || [ -L "$d/$c" ]; do c="$stem copy $i$ext"; i=$((i+1)); done
  echo "$c"
done`;

export const sameMachine = (a, b) => (a ?? null) === (b ?? null);
const parentOf = (p) => p.replace(/\/[^/]*$/, "") || "/";
const baseOf = (p) => p.split("/").filter(Boolean).pop() ?? p;

/**
 * Copies (or moves) files and folders into folder `dest` on machine `destOn`
 * (null: here). items: [{ path, on }]. Within one machine it's cp -a / mv; across
 * machines a tar stream goes through `hc exec`. Names that are taken get " copy".
 * Resolves with the new names.
 */
export async function transfer(items, dest, destOn, move = false, tick) {
  // Moving into the folder it's already in does nothing; a folder can't go into itself.
  items = items.filter((it) => !(move && sameMachine(it.on, destOn) && parentOf(it.path) === dest));
  for (const it of items) if (sameMachine(it.on, destOn) && (dest === it.path || dest.startsWith(it.path + "/")))
    throw new Error(`Cannot put ${baseOf(it.path)} inside itself`);
  if (!items.length) return [];
  const free = await sh(FREE_NAMES, [dest, ...items.map((it) => baseOf(it.path))], { on: destOn });
  if (free.code !== 0) throw new Error(free.stderr.trim() || "Cannot write to the folder");
  const names = free.stdout.split("\n").filter(Boolean);
  // Two items with one name (from different folders) would both get the same free name.
  const seen = new Set();
  for (let i = 0; i < names.length; i++) { while (seen.has(names[i])) names[i] = names[i].replace(/(\.[^.]*)?$/, (e) => ` ${i + 1}${e ?? ""}`); seen.add(names[i]); }
  const script = PRELUDE + `fail=0
while [ $# -ge 6 ]; do
  so=$1; src=$2; dm=$3; dd=$4; f=$5; mv=$6; shift 6
  if [ "$so" = "$dm" ]; then
    if [ "$mv" = 1 ]; then R "$so" mv -- "$src" "$dd/$f"; else R "$so" cp -a -- "$src" "$dd/$f"; fi || { echo "\${src##*/}: failed" >&2; fail=1; }
  else
    st=$(mktemp)
    { R "$so" tar -C "\${src%/*}/" -cf - "./\${src##*/}"; echo $? > "$st"; } | RI "$dm" sh -c '${UNTAR}' sh "$dd" "$f" "./\${src##*/}"
    r=$?; s=$(cat "$st"); rm -f "$st"
    if [ "$r" = 0 ] && [ "$s" = 0 ]; then [ "$mv" = 1 ] && R "$so" rm -rf -- "$src"
    else echo "\${src##*/}: transfer failed" >&2; fail=1; fi
  fi
done
exit $fail`;
  const args = items.flatMap((it, i) => [it.on ?? "", it.path, destOn ?? "", dest, names[i], move ? "1" : "0"]);
  await job(script, args, tick);
  return names;
}

/** Saves the clipboard's picture (image/png) as a new file in `dest`. Resolves with its name. */
export async function pasteImage(dest, destOn) {
  const free = await sh(FREE_NAMES, [dest, "image.png"], { on: destOn });
  const name = free.stdout.trim() || "image.png";
  await job(PRELUDE + '{ wl-paste -n -t image/png 2>/dev/null || xclip -selection clipboard -t image/png -o; } | RI "$1" sh -c \'cat > "$1"\' sh "$2/$3"',
    [destOn ?? "", dest, name]);
  return name;
}

/** Deletes files: here they go to the Trash (gio), on a machine they're removed. */
export async function remove(paths, on) {
  if (!paths.length) return;
  if (on) await job(PRELUDE + 'm=$1; shift; R "$m" rm -rf -- "$@"', [on, ...paths]);
  else {
    const r = await exec("gio", ["trash", "--", ...paths]).catch((e) => ({ code: 1, stderr: String(e) }));
    if (r.code !== 0) throw new Error(r.stderr.trim() || "Cannot move to the Trash");
  }
}

/** Renames (or moves) one path on its machine, refusing to overwrite. */
export async function rename(from, to, on) {
  const r = await sh('[ -e "$2" ] || [ -L "$2" ] && { echo "${2##*/} already exists" >&2; exit 3; }; mkdir -p -- "${2%/*}" && mv -- "$1" "$2"', [from, to], { on });
  if (r.code !== 0) throw new Error(r.stderr.trim() || "Rename failed");
}

/** Makes a new empty file or folder (with missing parent folders, like VS Code's "a/b.txt"). */
export async function create(path, dir, on) {
  const r = await sh('[ -e "$1" ] && { echo "${1##*/} already exists" >&2; exit 3; }; if [ "$2" = 1 ]; then mkdir -p -- "$1"; else mkdir -p -- "${1%/*}" && : > "$1"; fi', [path, dir ? "1" : "0"], { on });
  if (r.code !== 0) throw new Error(r.stderr.trim() || "Cannot create it");
}

// ---- The system clipboard (files) -------------------------------------------

const fileUri = (p) => "file://" + p.split("/").map(encodeURIComponent).join("/");
function uriPaths(text) {
  return text.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#"))
    .map((l) => /^file:\/\/(localhost)?(\/.*)$/.exec(l)?.[2]).filter(Boolean)
    .map((p) => { try { return decodeURIComponent(p); } catch { return p; } });
}

/** Puts local files on the system clipboard (text/uri-list), for file managers. */
export function copyFilesToSystem(paths) {
  const list = paths.map(fileUri).join("\r\n") + "\r\n";
  return sh('if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then printf %s "$1" | wl-copy -t text/uri-list; ' +
    'elif command -v xclip >/dev/null 2>&1; then printf %s "$1" | xclip -selection clipboard -t text/uri-list; fi >/dev/null 2>&1', [list]).catch(() => {});
}

/**
 * What the system clipboard holds, for a paste into the Explorer:
 * { kind: "files", paths, cut } (from a file manager or our own Copy),
 * { kind: "image" }, or { kind: "none" }.
 */
export async function readSystemClipboard() {
  const r = await sh(`if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-paste >/dev/null 2>&1; then
  t=$(wl-paste -l 2>/dev/null)
  case "$t" in
    *x-special/gnome-copied-files*) echo gnome; wl-paste -n -t x-special/gnome-copied-files;;
    *text/uri-list*) echo uris; wl-paste -n -t text/uri-list;;
    *image/png*) echo image;;
    *) echo none;;
  esac
elif command -v xclip >/dev/null 2>&1; then
  t=$(xclip -selection clipboard -t TARGETS -o 2>/dev/null)
  case "$t" in
    *x-special/gnome-copied-files*) echo gnome; xclip -selection clipboard -t x-special/gnome-copied-files -o;;
    *text/uri-list*) echo uris; xclip -selection clipboard -t text/uri-list -o;;
    *image/png*) echo image;;
    *) echo none;;
  esac
else echo none; fi`).catch(() => null);
  const [head, ...rest] = (r?.stdout ?? "none").split("\n");
  if (head === "image") return { kind: "image" };
  if (head === "gnome") { const [op, ...uris] = rest; const paths = uriPaths(uris.join("\n")); return paths.length ? { kind: "files", paths, cut: op.trim() === "cut" } : { kind: "none" }; }
  if (head === "uris") { const paths = uriPaths(rest.join("\n")); return paths.length ? { kind: "files", paths, cut: false } : { kind: "none" }; }
  return { kind: "none" };
}
