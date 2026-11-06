import { nested, role, byParent, tree } from "../mods/paddock/agents-data.js";
const eq = (a, b) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.error("FAIL", JSON.stringify(a), "!=", JSON.stringify(b)); process.exitCode = 1; } };
eq(role({ name: "ararat-review", labels: { "herdr-team.role": "review" } }), "review");
eq(role({ name: "helper", labels: {} }), "helper");
eq(role(undefined), "");
// A seat with a pane is nested under its orchestrator; the orchestrator and design are not.
const all = [
  { address: "t1", parent: null, state: "live" },
  { address: "t2", parent: null, state: "live" },
  { address: "t3", parent: "t2", state: "live" },
  { address: "t4", parent: "t2", state: "live" },
];
const parentOf = new Map(all.map((k) => [k.address, k.parent]));
const listed = new Map([["t1", "idle"], ["t2", "idle"], ["t3", "working"]]);
eq(["t1", "t2", "t3"].filter((a) => !nested({ address: a }, parentOf, listed)), ["t1", "t2"]);
// The tree under t2 holds both the paned seat (t3) and the paneless sub-agent (t4).
eq(tree(byParent(all), "t2").map((s) => [s.k.address, s.lines.join("")]), [["t3", "├"], ["t4", "└"]]);
