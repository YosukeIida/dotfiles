#!/usr/bin/env python3
"""Generate a fully self-contained KaTeX + markdown-it viewer.html.

KaTeX css/js comes from the nix store (`nixpkgs#katex`); its 20 woff2 fonts are
base64-inlined into the CSS. markdown-it and markdown-it-katex are vendored next
to this script. The result is a single HTML file with zero external references,
so it works offline and is immune to WKWebView file:// cross-origin restrictions.

Usage: gen_viewer.py <out.html>
The page exposes two globals the launcher drives over `cmux browser ... eval`:
    window.__render(markdownText)   -> render markdown (math-aware) into #content
    window.__b64(base64Utf8)        -> decode a base64 UTF-8 payload to a string
"""
import base64, re, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
VENDOR = HERE / "vendor"


def katex_root() -> pathlib.Path:
    out = subprocess.check_output(
        ["nix", "build", "nixpkgs#katex", "--no-link", "--print-out-paths"],
        text=True).strip().splitlines()[0]
    return pathlib.Path(out) / "lib/node_modules/katex"


def inline_fonts(css: str, fonts_dir: pathlib.Path) -> str:
    """Replace each `src:url(fonts/X.woff2) ...woff...ttf` list with a single
    woff2 data: URI, dropping the woff/ttf fallbacks (WKWebView supports woff2)."""
    def repl(m: "re.Match[str]") -> str:
        name = m.group(1)
        b64 = base64.b64encode((fonts_dir / f"{name}.woff2").read_bytes()).decode()
        return f'src:url(data:font/woff2;base64,{b64}) format("woff2")'
    return re.sub(r'src:url\(fonts/([A-Za-z0-9_\-]+)\.woff2\)[^;}]*', repl, css)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: gen_viewer.py <out.html>")
    kx = katex_root()
    css = inline_fonts((kx / "dist/katex.min.css").read_text(), kx / "fonts")
    katex_js = (kx / "dist/katex.min.js").read_text()
    md_js = (VENDOR / "markdown-it.min.js").read_text()
    mdk_js = (VENDOR / "markdown-it-katex.js").read_text()

    page = f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>cmux md+katex viewer</title>
<style>
{css}
:root {{ color-scheme: light dark; }}
html, body {{ margin: 0; padding: 0; }}
body {{
  font-family: -apple-system, "Hiragino Kaku Gothic ProN", "Helvetica Neue", Arial, sans-serif;
  line-height: 1.7; background: #ffffff; color: #1f2328;
  padding: 32px 40px 120px; max-width: 900px; margin: 0 auto;
}}
@media (prefers-color-scheme: dark) {{
  body {{ background: #0d1117; color: #e6edf3; }}
  pre, code {{ background: #161b22 !important; }}
  a {{ color: #4493f8; }}
  hr {{ border-color: #30363d; }}
  table th, table td {{ border-color: #30363d; }}
}}
h1, h2 {{ border-bottom: 1px solid rgba(128,128,128,.3); padding-bottom: .3em; }}
code {{ background: rgba(128,128,128,.15); padding: .15em .35em; border-radius: 4px;
  font-family: "SF Mono", Menlo, Consolas, monospace; font-size: .9em; }}
pre {{ background: rgba(128,128,128,.12); padding: 14px 16px; border-radius: 8px; overflow: auto; }}
pre code {{ background: none; padding: 0; }}
blockquote {{ margin: 0; padding: 0 1em; border-left: 4px solid rgba(128,128,128,.4); opacity: .85; }}
table {{ border-collapse: collapse; }}
table th, table td {{ border: 1px solid rgba(128,128,128,.4); padding: 6px 12px; }}
img {{ max-width: 100%; }}
.katex-display {{ overflow-x: auto; overflow-y: hidden; padding: 4px 0; }}
#content:empty::before {{ content: "(empty)"; opacity: .4; }}
</style>
</head>
<body>
<div id="content"></div>
<script>{katex_js}</script>
<script>{md_js}</script>
<script>
// CommonJS shim so markdown-it-katex (require('katex'), module.exports) loads in-browser.
// Loaded AFTER katex/markdown-it UMD bundles so they bind to window, not to this module.
window.module = {{ exports: {{}} }};
window.require = function (n) {{ if (n === 'katex') return window.katex; throw new Error('no module ' + n); }};
</script>
<script>{mdk_js}</script>
<script>
(function () {{
  var mdKatex = window.module.exports;
  try {{ delete window.module; delete window.require; }} catch (e) {{}}
  var md = window.markdownit({{ html: false, linkify: true, breaks: false }});
  md.use(mdKatex, {{ throwOnError: false, errorColor: '#cc0000' }});
  window.__render = function (text) {{
    try {{ document.getElementById('content').innerHTML = md.render(text); }}
    catch (e) {{ document.getElementById('content').textContent = String(e); }}
  }};
  window.__b64 = function (b64) {{
    var bin = atob(b64), bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder('utf-8').decode(bytes);
  }};
  if (window.__INITIAL__) window.__render(window.__b64(window.__INITIAL__));
}})();
</script>
</body>
</html>
"""
    out = pathlib.Path(sys.argv[1])
    out.write_text(page)
    print(f"wrote {out} ({len(page)//1024} KB)")


if __name__ == "__main__":
    main()
