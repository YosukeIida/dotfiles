// Projects, as Orca has them: a project is a folder on one machine, a git
// repository or any folder, kept in a list until it's removed. A repo a space
// opens in joins the list by itself; any folder can be added. A space belongs
// to its repo's project, else to the project whose folder holds where it is now
// (the deepest one). Pure: no herdr imports, so node can test it.

// A repo's folder from git's common dir: "/x/app/.git" -> "/x/app"; a bare
// repo ("/x/app.git") is its own folder.
export function repoRoot(commonDir) {
  const dir = String(commonDir ?? "").replace(/[\\/]+$/, "");
  return /[\\/]\.git$/.test(dir) ? dir.slice(0, -5) : dir;
}

// A path as compared: "/" for "\", no trailing slash, and on a Windows path
// (a drive letter) lowercased, since Windows ignores case.
export function norm(path) {
  let p = String(path ?? "").replace(/\\/g, "/");
  if (p.length > 1) p = p.replace(/\/+$/, "");
  return /^[A-Za-z]:/.test(p) ? p.toLowerCase() : p;
}

export const inside = (path, root) => {
  const p = norm(path), r = norm(root);
  return Boolean(p && r) && (p === r || p.startsWith(r.endsWith("/") ? r : r + "/"));
};

export const baseName = (path) => String(path ?? "").replace(/[\\/]+$/, "").split(/[\\/]/).pop() || String(path ?? "");

// A machine's key in the store: "" for this computer.
export const machineKey = (machine) => machine ?? "";

// The store: { [machineKey]: { list: [{ id, root, name, auto }], removed: [root],
// of: { [spaceId]: projectId | "" } } }. `of` is where a space was dragged: into a
// project, or "" out of the one its folder would put it in.
export const emptyStore = () => ({});
const entry = (store, machine) => ({ list: [], removed: [], of: {}, ...(store?.[machineKey(machine)] ?? {}) });
const put = (store, machine, e) => ({ ...store, [machineKey(machine)]: e });
export const projectList = (store, machine) => entry(store, machine).list;
export const placedOf = (store, machine) => entry(store, machine).of;

// An id from the folder, made unique in the list (a project's folder can change).
const newId = (root, list) => {
  const base = "p" + [...norm(root)].reduce((h, c) => (Math.imul(h, 31) + c.charCodeAt(0)) >>> 0, 2166136261).toString(36);
  let id = base, n = 1;
  while (list.some((p) => p.id === id)) id = `${base}-${++n}`;
  return id;
};

// Whether another project of the machine has this folder already.
export const taken = (store, machine, root, except = null) =>
  entry(store, machine).list.some((p) => p.id !== except && norm(p.root) === norm(root));

// The store with a project added (no change when its folder is listed already).
// `auto`: found from a repo a space opened in; one the person removed stays out.
export function addProject(store, machine, root, { name, auto = false } = {}) {
  const e = entry(store, machine);
  if (e.list.some((p) => norm(p.root) === norm(root))) return store;
  if (auto && e.removed.some((r) => norm(r) === norm(root))) return store;
  const list = [...e.list, { id: newId(root, e.list), root, name: name || baseName(root), auto }];
  const removed = auto ? e.removed : e.removed.filter((r) => norm(r) !== norm(root));
  return put(store, machine, { ...e, list, removed });
}

// Removed from the list, with the spaces dragged into it; a repo's folder is
// remembered so it isn't added back by itself.
export function removeProject(store, machine, id) {
  const e = entry(store, machine), p = e.list.find((x) => x.id === id);
  if (!p) return store;
  const of = Object.fromEntries(Object.entries(e.of).filter(([, v]) => v !== id));
  return put(store, machine, { list: e.list.filter((x) => x.id !== id), removed: [...e.removed.filter((r) => norm(r) !== norm(p.root)), p.root], of });
}

// A new name and folder; an empty name goes back to the folder's.
// A new name and folder; an empty name goes back to the folder's. A folder another
// project has is refused (no change). The folder left behind is remembered as
// removed, so a repo there isn't added back by itself.
export function editProject(store, machine, id, { name, root }) {
  const e = entry(store, machine), p = e.list.find((x) => x.id === id);
  if (!p) return store;
  const to = root || p.root;
  if (taken(store, machine, to, id)) return store;
  const moved = norm(to) !== norm(p.root);
  const removed = moved ? [...e.removed.filter((r) => norm(r) !== norm(p.root) && norm(r) !== norm(to)), p.root] : e.removed;
  const list = e.list.map((x) => (x.id === id ? { ...x, root: to, name: name || baseName(to) } : x));
  return put(store, machine, { ...e, list, removed });
}

// Spaces dragged in or out that are gone (`live`: the ids that still exist on the machine).
export function prunePlaced(store, machine, live) {
  const e = entry(store, machine), of = Object.fromEntries(Object.entries(e.of).filter(([id]) => live.has(id)));
  return Object.keys(of).length === Object.keys(e.of).length ? store : put(store, machine, { ...e, of });
}

// The project `id` moved to where `to` is (before it when moving up, after it down).
export function reorderProject(store, machine, id, to) {
  const e = entry(store, machine), list = [...e.list];
  const i = list.findIndex((p) => p.id === id), j = list.findIndex((p) => p.id === to);
  if (i < 0 || j < 0 || i === j) return store;
  list.splice(j, 0, ...list.splice(i, 1));
  return put(store, machine, { ...e, list });
}

// A space dragged into a project (`id`), or out of its project (null). Out of the
// project its folder or repo would put it in, it stays out ("").
export function placeSpace(store, machine, spaceId, id, { natural = null } = {}) {
  const e = entry(store, machine), of = { ...e.of };
  if (id && e.list.some((p) => p.id === id)) of[spaceId] = id === natural ? undefined : id;
  else if (!id) of[spaceId] = natural ? "" : undefined;
  else return store;
  if (of[spaceId] === undefined) delete of[spaceId];
  return put(store, machine, { ...e, of });
}

// Which project a space belongs to: its repo's, else the deepest folder holding it.
export function projectFor(list, { place, repo }) {
  if (repo) {
    const own = list.find((p) => norm(p.root) === norm(repo));
    if (own) return own;
  }
  let best = null;
  for (const p of list) if (inside(place, p.root) && (!best || norm(p.root).length > norm(best.root).length)) best = p;
  return best;
}

// The project a row's folder or repo puts it in, before any drag.
export function naturalProject(list, r) {
  const repo = r.g?.repo ? repoRoot(JSON.parse(r.g.repo)[1]) : null;
  return projectFor(list, { place: r.place, repo });
}

// rows: [{ w, i, g, place }] of one machine in Herdr's space order; g the space's
// git info ({ name, repo: JSON [machine, commonDir], linked }) or null; `of` the
// spaces dragged in or out (see placeSpace).
// Returns { projects: [{ ...project, rows }], loose } in the list's order, empty
// projects included; within a project its main checkouts come before worktrees
// (`worktree: true`).
export function groupRows(list, rows, of = {}) {
  const by = new Map(list.map((p) => [p.id, { main: [], linked: [] }])), loose = [];
  for (const r of rows) {
    const dragged = of[r.w.id];
    const p = dragged === "" ? null : (dragged && list.find((x) => x.id === dragged)) || naturalProject(list, r);
    if (!p) { loose.push(r); continue; }
    by.get(p.id)[r.g?.linked ? "linked" : "main"].push({ ...r, worktree: Boolean(r.g?.linked) });
  }
  return { projects: list.map((p) => ({ ...p, rows: [...by.get(p.id).main, ...by.get(p.id).linked] })), loose };
}

// The repos the rows are in that the list doesn't have yet: [{ root, name }].
export function reposToAdd(store, machine, rows) {
  const e = entry(store, machine), seen = new Set(), out = [];
  for (const r of rows) {
    if (!r.g?.repo) continue;
    const root = repoRoot(JSON.parse(r.g.repo)[1]), k = norm(root);
    if (seen.has(k) || e.list.some((p) => norm(p.root) === k) || e.removed.some((x) => norm(x) === k)) continue;
    seen.add(k);
    out.push({ root, name: r.g.name });
  }
  return out;
}

const RANK = { blocked: 4, done: 3, working: 2, idle: 1 };
// The most urgent status among a project's spaces, as Herdr ranks them.
export function urgent(statuses) {
  let best = null;
  for (const s of statuses) if ((RANK[s] ?? 0) > (RANK[best] ?? 0)) best = s;
  return best;
}

// Projects from the space-folders mod's file (~/.config/herdr-space-folders.json):
// each folder with a start path becomes a project, "~" expanded with `home`.
export function fromSpaceFolders(text, home) {
  try {
    const d = JSON.parse(text);
    return (d.list ?? []).filter((f) => f.path).map((f) => ({ root: f.path.replace(/^~(?=$|[\\/])/, home), name: f.name }));
  } catch { return []; }
}
