// Display math ($$…$$, \[…\]) in the Markdown preview, drawn by RaTeX's
// ratex-svg into the cache and shown as images between the text.
import { exec } from "herdr";
import * as fs from "fs/promises";
import { ensureCache, cacheDir, CACHE_REL } from "./io.js";

const MATH = /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]/g;

/** Splits Markdown into [{ md }] and [{ tex }] parts; fenced code is left alone. */
export function splitMath(text) {
  const parts = [], push = (md) => { if (md.trim()) { const last = parts[parts.length - 1]; if (last?.md !== undefined) last.md += md; else parts.push({ md }); } };
  // Odd chunks are fenced code blocks (the fence lines included).
  const chunks = text.split(/(^(?:```|~~~)[^\n]*\n[\s\S]*?(?:^(?:```|~~~)[^\n]*$|(?![\s\S])))/m);
  chunks.forEach((chunk, i) => {
    if (i % 2) { push(chunk); return; }
    let at = 0;
    for (const m of chunk.matchAll(MATH)) {
      push(chunk.slice(at, m.index));
      parts.push({ tex: (m[1] ?? m[2]).trim() });
      at = m.index + m[0].length;
    }
    push(chunk.slice(at));
  });
  return parts;
}

const done = new Map(), running = new Map();
let missing = false;

function hash(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
  return h.toString(36);
}

/** The drawn formula ({ src, w, h } or { error }), or null while it's being drawn. */
export const drawn = (tex, color) => done.get(`${color}\n${tex}`) ?? null;

/** Draws a formula once per color; resolves when it's ready. */
export function draw(tex, color) {
  const key = `${color}\n${tex}`;
  if (done.has(key)) return Promise.resolve();
  if (running.has(key)) return running.get(key);
  const job = (async () => {
    if (missing) { done.set(key, { error: "ratex-svg is not installed" }); return; }
    // ratex-svg reads one formula per line.
    const r = await exec("sh", ["-c", 'printf "%s\\n" "$1" | ratex-svg --stdout --font-size 17 --padding 2 --color "$2"', "sh", tex.replace(/\s*\n\s*/g, " "), color])
      .catch((e) => ({ code: 127, stdout: "", stderr: String(e) }));
    const svg = r.stdout.slice(r.stdout.indexOf("<svg"));
    const box = /viewBox="[\d.\-]+ [\d.\-]+ ([\d.]+) ([\d.]+)"/.exec(svg);
    if (r.code === 127) missing = true;
    if (r.code !== 0 || !box) { done.set(key, { error: r.code === 127 ? "ratex-svg is not installed" : (r.stderr.trim() || "Cannot draw this formula") }); return; }
    await ensureCache();
    const name = `math-${hash(key)}.svg`;
    await fs.writeFile(`${cacheDir()}/${name}`, svg);
    done.set(key, { src: `${CACHE_REL}/${name}`, w: Number(box[1]), h: Number(box[2]) });
  })().finally(() => running.delete(key));
  running.set(key, job);
  return job;
}
