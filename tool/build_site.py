#!/usr/bin/env python3
"""Builds the project's web pages (GitHub Pages serves `docs/`) and checks them.

  tool/build_site.py            write docs/index.html and docs/features/*.html
  tool/build_site.py --check    build in memory, fail if a written page is out of date,
                                and check every link and file the pages use

The pages are written by hand as fragments in `site/src/` and listed, with their
titles and cards, in `site/features.json`. This script wraps each in the same
header, footer and navigation. The stylesheet, script and fonts are in `docs/site/`;
the pictures are the design reviews' own (`docs/design-review/`), the build video's
frames and the captures in `docs/site/img/`.

The site is held to the app's own rule (CLAUDE.md 1): **it uses nothing from
anywhere else**. No web font, script, stylesheet, picture, analytics or embed from
another site; the only address outside the repo that a page may link to is this
project's own on GitHub. `--check` fails on anything else.

Standard library only.
"""
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "site" / "src"
DOCS = ROOT / "docs"
REGISTRY = ROOT / "site" / "features.json"

REPO_URL = "https://github.com/ictashik/tapedash"
SITE_NAME = "TapeDash"

GROUPS = [
    ("drive", "On the dash"),
    ("money", "Where the money goes"),
    ("learn", "Learning from your drives"),
    ("car", "The car"),
    ("platform", "Other screens and your data"),
    ("principles", "How it is built"),
]


def load():
    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    return data["features"]


def esc(s):
    return html.escape(s, quote=True)


def head(title, description, root, page_class):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#050607">
<title>{esc(title)}</title>
<meta name="description" content="{esc(description)}">
<link rel="icon" href="{root}site/icon.png">
<link rel="stylesheet" href="{root}site/site.css">
</head>
<body class="{page_class}">
"""


def header(root, current):
    def link(href, label, key):
        cur = ' aria-current="page"' if key == current else ""
        return f'<a href="{href}"{cur}>{label}</a>'

    return f"""<div class="wrap">
  <header class="bar">
    <a class="mark" href="{root}index.html">Tape<span>Dash</span></a>
    <nav aria-label="Site">
      {link(root + "index.html#features", "Features", "home")}
      {link(root + "features/offline.html", "Offline", "offline")}
      {link(root + "index.html#status", "Status", "status")}
      <a href="{REPO_URL}">GitHub</a>
    </nav>
  </header>
"""


def more(features, root, current):
    items = []
    for f in features:
        cur = ' aria-current="page"' if f["slug"] == current else ""
        items.append(
            f'<li><a href="{root}features/{f["slug"]}.html"{cur}>{esc(f["title"])}</a></li>'
        )
    return f"""
    <section class="more" aria-labelledby="h-more">
      <h2 id="h-more">All features</h2>
      <ul>
        {chr(10).join("        " + i for i in items).strip()}
      </ul>
    </section>
"""


def footer(root):
    return f"""
  <footer>
    <div class="links">
      <a href="{REPO_URL}">Source on GitHub</a>
      <a href="{REPO_URL}/blob/main/docs/STATUS.md">What is verified (STATUS.md)</a>
      <a href="{REPO_URL}/blob/main/DESIGN.md">Design spec</a>
      <a href="{REPO_URL}/blob/main/CLAUDE.md">Architecture and rules</a>
    </div>
    <p>TapeDash is a free, open-source, strictly offline Android app. Fuel and money figures are estimates. It is an aid, not a certified instrument: set it up while parked, and you remain responsible for driving safely.</p>
    <p>This page itself loads nothing from anywhere else: no web fonts, scripts, analytics or embeds. Google Maps is a trademark of Google LLC; TapeDash is independent and is not affiliated with or endorsed by Google.</p>
  </footer>
</div>

<dialog id="lightbox" aria-label="Screenshot">
  <img id="lbImg" alt="">
  <div class="cap">
    <span id="lbCap"></span>
    <form method="dialog"><button class="btn" autofocus>Close</button></form>
  </div>
</dialog>

<script src="{root}site/site.js"></script>
</body>
</html>
"""


def levels_html(levels):
    if not levels:
        return ""
    lis = "\n".join(
        f'      <li class="{"on" if on else "off"}">{esc(label)}</li>' for label, on in levels
    )
    return f"""
    <ul class="levels" aria-label="Where this has been seen working">
{lis}
    </ul>"""


def image_size(path):
    """(width, height) of a PNG or JPEG, from its header, with no library."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if data[:2] == b"\xff\xd8":
        i = 2
        while i < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                return int.from_bytes(data[i + 7 : i + 9], "big"), int.from_bytes(data[i + 5 : i + 7], "big")
            i += 2 + int.from_bytes(data[i + 2 : i + 4], "big")
    raise ValueError(f"{path}: not a PNG or JPEG")


MISSING = []

def thumb_size(path):
    return image_size(DOCS / path) if (DOCS / path).exists() else (1, 1)


FIG = re.compile(r"\{\{fig:\s*(.+?)\s*\}\}", re.S)


def expand(text, root):
    """{{root}} is the way back to docs/; {{fig: path | alt | caption}} is a picture
    that opens larger, with its own size so that the page does not jump."""

    def fig(m):
        parts = [p.strip() for p in m.group(1).split(" | ")]
        if len(parts) != 3:
            raise ValueError(f"fig needs 'path | alt | caption': {m.group(1)[:60]}")
        path, alt, caption = parts
        if not (DOCS / path).exists():
            MISSING.append(path)
            w, h = 1, 1
        else:
            w, h = image_size(DOCS / path)
        return (
            f'<figure>\n          <button class="zoom" type="button"><img src="{root}{path}" '
            f'width="{w}" height="{h}" loading="lazy" alt="{esc(alt)}"></button>\n'
            f"          <figcaption>{caption}</figcaption>\n        </figure>"
        )

    return FIG.sub(fig, text).replace("{{root}}", root)


def fragment(slug, root):
    path = SRC / "features" / f"{slug}.html"
    return expand(path.read_text(encoding="utf-8"), root)


def prev_next(features, i, root):
    out = []
    if i > 0:
        p = features[i - 1]
        out.append(
            f'<a class="prev" href="{root}features/{p["slug"]}.html"><small>Previous</small>{esc(p["title"])}</a>'
        )
    if i < len(features) - 1:
        n = features[i + 1]
        out.append(
            f'<a class="next" href="{root}features/{n["slug"]}.html"><small>Next</small>{esc(n["title"])}</a>'
        )
    return f'\n    <nav class="pn" aria-label="Neighbouring features">\n      {"".join(out)}\n    </nav>\n' if out else ""


def feature_page(features, i):
    f = features[i]
    root = "../"
    body = fragment(f["slug"], root)
    group = dict(GROUPS)[f["group"]]
    page = head(f'{f["title"]} | {SITE_NAME}', f["card"], root, "feature")
    page += header(root, f["slug"] if f["slug"] == "offline" else "feature")
    page += f"""
  <main id="top">
    <section class="pagehead" aria-labelledby="h-page">
      <p class="crumbs"><a href="{root}index.html#features">Features</a> / {esc(group)}</p>
      <h1 id="h-page">{esc(f["title"])}</h1>
      <p class="lede sub">{f["lede"]}</p>{levels_html(f.get("levels"))}
    </section>

{body}
{prev_next(features, i, root)}{more(features, root, f["slug"])}  </main>
"""
    page += footer(root)
    return page


def index_page(features):
    root = ""
    body = expand((SRC / "index.html").read_text(encoding="utf-8"), root)
    cards = []
    for key, label in GROUPS:
        group = [f for f in features if f["group"] == key]
        if not group:
            continue
        cards.append(f'      <h3 class="group">{esc(label)}</h3>\n      <div class="cards">')
        for f in group:
            cards.append(
                f"""        <a class="card" href="features/{f["slug"]}.html">
          <div class="thumb"><img src="{f["thumb"]}" width="{thumb_size(f["thumb"])[0]}" height="{thumb_size(f["thumb"])[1]}" loading="lazy" alt="{esc(f["thumb_alt"])}"></div>
          <div class="body"><h3>{esc(f["title"])}</h3><p>{esc(f["card"])}</p></div>
        </a>"""
            )
        cards.append("      </div>")
    body = body.replace("{{cards}}", "\n".join(cards))
    page = head(
        f"{SITE_NAME}: a car dashboard from an old phone",
        "A free, open-source, strictly offline Android app: a car dashboard, a windshield HUD and a trip computer that shows where the money goes, from a cheap OBD-II adapter.",
        root,
        "landing",
    )
    page += header(root, "home")
    page += body
    page += footer(root)
    return page


def build(features):
    out = {DOCS / "index.html": index_page(features)}
    for i, f in enumerate(features):
        out[DOCS / "features" / f'{f["slug"]}.html'] = feature_page(features, i)
    return out


ATTR = re.compile(r'\b(src|href|poster|action)="([^"]*)"')
CSS_URL = re.compile(r'url\(\s*["\']?([^)"\']+)["\']?\s*\)')


def problems(pages):
    """Every file a page uses must exist, and nothing may come from another site."""
    found = []
    for path, text in pages.items():
        rel = path.relative_to(ROOT)
        for _, ref in ATTR.findall(text):
            if ref.startswith(("#", "mailto:")) or ref == "":
                continue
            if ref.startswith(("http://", "https://", "//")):
                if not (ref == REPO_URL or ref.startswith(REPO_URL + "/")):
                    found.append(f"{rel}: {ref} is from another site")
                continue
            target = (path.parent / ref.split("#")[0].split("?")[0]).resolve()
            if DOCS.resolve() not in target.parents and target != DOCS.resolve():
                found.append(f"{rel}: {ref} is outside docs/, which is all that is published")
            elif not target.exists():
                found.append(f"{rel}: {ref} does not exist")
        if re.search(r"<script[^>]*src=\"(https?:)?//", text) or "@import" in text:
            found.append(f"{rel}: loads a script or style from elsewhere")
    css = DOCS / "site" / "site.css"
    for ref in CSS_URL.findall(css.read_text(encoding="utf-8")):
        if ref.startswith(("http", "//", "data:")):
            found.append(f"docs/site/site.css: {ref} is from another site")
        elif not (css.parent / ref).exists():
            found.append(f"docs/site/site.css: {ref} does not exist")
    for ref in re.findall(r"https?://[^\s\"')]+", (DOCS / "site" / "site.js").read_text(encoding="utf-8")):
        found.append(f"docs/site/site.js: {ref} is from another site")
    return found


def fonts_match():
    """The site's fonts are copies of the app's own: they must not drift."""
    found = []
    for f in (DOCS / "site" / "fonts").glob("*"):
        src = ROOT / "assets" / "fonts" / f.name
        if src.exists() and src.read_bytes() != f.read_bytes():
            found.append(f"docs/site/fonts/{f.name} differs from assets/fonts/{f.name}")
    return found


def main():
    features = load()
    pages = build(features)
    for path in features:
        for key in ("thumb",):
            if not (DOCS / path[key]).exists():
                MISSING.append(path[key])
    if MISSING:
        for path in sorted(set(MISSING)):
            print(f"site: {path} does not exist")
        return 1
    if "--check" in sys.argv:
        bad = problems(pages) + fonts_match()
        for path, text in pages.items():
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                bad.append(f"{path.relative_to(ROOT)} is out of date: run tool/build_site.py")
        for stray in sorted((DOCS / "features").glob("*.html")):
            if stray not in pages:
                bad.append(f"{stray.relative_to(ROOT)} is not in site/features.json")
        for f in bad:
            print("site:", f)
        print("site: ok" if not bad else f"site: {len(bad)} problem(s)")
        return 1 if bad else 0
    (DOCS / "features").mkdir(parents=True, exist_ok=True)
    for path, text in pages.items():
        path.write_text(text, encoding="utf-8")
    print(f"site: wrote {len(pages)} pages")
    bad = problems(pages)
    for f in bad:
        print("site:", f)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
