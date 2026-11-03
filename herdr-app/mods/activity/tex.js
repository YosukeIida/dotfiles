// Inline math ($…$) in the Markdown preview, written out as Unicode text.
// Herdr app's Markdown view draws no images inside a line, nor <sub>/<sup>.

const SYM = {
  alpha: "α", beta: "β", gamma: "γ", delta: "δ", epsilon: "ϵ", varepsilon: "ε", zeta: "ζ", eta: "η", theta: "θ",
  vartheta: "ϑ", iota: "ι", kappa: "κ", lambda: "λ", mu: "μ", nu: "ν", xi: "ξ", pi: "π", rho: "ρ", sigma: "σ",
  tau: "τ", upsilon: "υ", phi: "ϕ", varphi: "φ", chi: "χ", psi: "ψ", omega: "ω",
  Gamma: "Γ", Delta: "Δ", Theta: "Θ", Lambda: "Λ", Xi: "Ξ", Pi: "Π", Sigma: "Σ", Phi: "Φ", Psi: "Ψ", Omega: "Ω",
  le: "≤", leq: "≤", ge: "≥", geq: "≥", neq: "≠", ne: "≠", approx: "≈", sim: "∼", simeq: "≃", equiv: "≡", propto: "∝",
  ll: "≪", gg: "≫", perp: "⊥", mid: "|", in: "∈", notin: "∉", ni: "∋", subset: "⊂", subseteq: "⊆", supset: "⊃",
  supseteq: "⊇", cup: "∪", cap: "∩", setminus: "∖", times: "×", cdot: "·", pm: "±", mp: "∓", div: "÷", ast: "∗",
  star: "⋆", circ: "∘", oplus: "⊕", otimes: "⊗", infty: "∞", to: "→", rightarrow: "→", leftarrow: "←",
  gets: "←", leftrightarrow: "↔", mapsto: "↦", Rightarrow: "⇒", Leftarrow: "⇐", Leftrightarrow: "⇔", implies: "⇒",
  iff: "⇔", sum: "∑", prod: "∏", int: "∫", oint: "∮", partial: "∂", nabla: "∇", forall: "∀", exists: "∃", neg: "¬",
  lnot: "¬", land: "∧", wedge: "∧", lor: "∨", vee: "∨", top: "⊤", bot: "⊥", emptyset: "∅", varnothing: "∅",
  ldots: "…", dots: "…", cdots: "⋯", vdots: "⋮", prime: "′", ell: "ℓ", hbar: "ℏ", aleph: "ℵ",
  langle: "⟨", rangle: "⟩", lceil: "⌈", rceil: "⌉", lfloor: "⌊", rfloor: "⌋", lVert: "‖", rVert: "‖", Vert: "‖",
  lvert: "|", rvert: "|", vert: "|", "|": "‖", "{": "{", "}": "}", "$": "$", "%": "%", "&": "&", "#": "#", "_": "_",
  ",": " ", ";": " ", ":": " ", "!": "", " ": " ", quad: " ", qquad: "  ",
  log: "log", ln: "ln", exp: "exp", max: "max", min: "min", argmax: "argmax", argmin: "argmin", lim: "lim",
  sup: "sup", inf: "inf", det: "det", Pr: "Pr", sin: "sin", cos: "cos", tan: "tan",
  left: "", right: "", big: "", Big: "", bigg: "", Bigg: "", displaystyle: "", limits: "", nolimits: "",
};
const BB = { R: "ℝ", N: "ℕ", Z: "ℤ", Q: "ℚ", C: "ℂ", E: "𝔼", P: "ℙ" };
const ACCENT = { bar: "̄", overline: "̄", hat: "̂", widehat: "̂", tilde: "̃", widetilde: "̃", dot: "̇", ddot: "̈", vec: "⃗" };
const STYLE = new Set(["text", "textrm", "textit", "textbf", "mathrm", "mathit", "mathbf", "mathsf", "mathtt", "mathcal", "mathscr", "mathfrak", "boldsymbol", "bm", "operatorname", "mbox"]);
const SUP = { 0: "⁰", 1: "¹", 2: "²", 3: "³", 4: "⁴", 5: "⁵", 6: "⁶", 7: "⁷", 8: "⁸", 9: "⁹", "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
  a: "ᵃ", b: "ᵇ", c: "ᶜ", d: "ᵈ", e: "ᵉ", f: "ᶠ", g: "ᵍ", h: "ʰ", i: "ⁱ", j: "ʲ", k: "ᵏ", l: "ˡ", m: "ᵐ", n: "ⁿ", o: "ᵒ", p: "ᵖ", r: "ʳ", s: "ˢ", t: "ᵗ", u: "ᵘ", v: "ᵛ", w: "ʷ", x: "ˣ", y: "ʸ", z: "ᶻ",
  T: "ᵀ", "*": "*", "′": "′", "∗": "*" };
const SUB = { 0: "₀", 1: "₁", 2: "₂", 3: "₃", 4: "₄", 5: "₅", 6: "₆", 7: "₇", 8: "₈", 9: "₉", "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎",
  a: "ₐ", e: "ₑ", h: "ₕ", i: "ᵢ", j: "ⱼ", k: "ₖ", l: "ₗ", m: "ₘ", n: "ₙ", o: "ₒ", p: "ₚ", r: "ᵣ", s: "ₛ", t: "ₜ", u: "ᵤ", v: "ᵥ", x: "ₓ" };

/** TeX (one inline formula) as plain Unicode text. */
export function texToText(tex) {
  let i = 0;
  // One argument: a {group}, a \command, or one character.
  const arg = () => {
    while (tex[i] === " ") i++;
    if (tex[i] === "{") {
      let depth = 0, start = ++i;
      for (; i < tex.length; i++) {
        if (tex[i] === "\\") { i++; continue; }
        if (tex[i] === "{") depth++;
        else if (tex[i] === "}" && depth-- === 0) break;
      }
      return texToText(tex.slice(start, i++));
    }
    return atom();
  };
  const script = (map, mark) => {
    const s = arg(), all = [...s].every((ch) => map[ch]);
    if (all) return [...s].map((ch) => map[ch]).join("");
    return mark + (/^[\p{L}\p{N}]+$/u.test(s) && (mark === "_" || s.length === 1) ? s : `(${s})`);
  };
  const atom = () => {
    const ch = tex[i++];
    if (ch === undefined) return "";
    if (ch === "^") return script(SUP, "^");
    if (ch === "_") return script(SUB, "_");
    if (ch === "{" ) { i--; return arg(); }
    if (ch === "}") return "";
    if (ch === "~") return " ";
    if (ch === "-") return "−";
    if (ch !== "\\") return ch;
    const name = /^[A-Za-z]+/.exec(tex.slice(i))?.[0] ?? tex[i] ?? "";
    i += name.length;
    if (name === "frac" || name === "dfrac" || name === "tfrac") {
      const wrap = (s) => (/^[\p{L}\p{N}.′]+$/u.test(s) ? s : `(${s})`);
      const a = arg(), b = arg();
      return `${wrap(a)}/${wrap(b)}`;
    }
    if (name === "sqrt") { const s = arg(); return `√${[...s].length > 1 ? `(${s})` : s}`; }
    if (name === "mathbb") { const s = arg(); return [...s].map((c) => BB[c] ?? c).join(""); }
    if (STYLE.has(name)) return arg();
    if (ACCENT[name]) return arg() + ACCENT[name];
    if (name in SYM) return SYM[name];
    return name;
  };
  let out = "";
  while (i < tex.length) out += atom();
  return out.replace(/ {2,}/g, " ").trim();
}

// $ needs no space inside it and no digit after it ($5 and $10 stay).
const INLINE = /(?<![\\$])\$(?![\s$])([^$\n]+?)(?<![\s\\])\$(?!\d)/g;

/** Markdown with each inline formula replaced by its Unicode text; `code` is left alone. */
export const inlineMath = (md) => md.split(/(`+[^`\n]*?`+)/).map((s, i) => (i % 2 ? s
  : s.replace(INLINE, (_m, tex) => texToText(tex).replace(/[\\`*_[\]<>|]/g, "\\$&")))).join("");
