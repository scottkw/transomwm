#!/usr/bin/env python3
"""Build public/index.html from source/Website.dc.html (the Design canvas artboard).

Removes the design tool's wrapper, resolves the headline, and inlines the fonts
and icons as data URIs, so the deployed page is one file with no outside requests.

Usage, from the repo root:  python3 -I scripts/build.py
"""
import base64, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "source/Website.dc.html"
OUT = ROOT / "public/index.html"
FONTS = ROOT / "source/fonts"
IMG = ROOT / "source/img"

# Canvas asset ids (the /_blob/<id> urls in the artboard) -> local copies.
BLOBS = {
    "e9a2d08c51a1ad2dede3ce9ddce59d1e": IMG / "icon-64.png",
    "b1199f6a784e1094c3288d9ccf9430e2": IMG / "icon-32.png",
    "e26eaa8016530e48713408939afa8ac0": IMG / "icon-256.png",
    "b315590be1105f49eb2f00bffa2e694f": IMG / "menubar-glyph-36.png",
}
# The artboard's "headline" tweak. Keep in step with the canvas.
HEADLINES = {
    "overlap": "Windows that never overlap.",
    "dock": "Drag a window. It docks.",
    "tidy": "Tiled windows that tidy themselves.",
}
HEADLINE = HEADLINES["overlap"]


def b64(path):
    return base64.b64encode(path.read_bytes()).decode()


def main():
    src = SRC.read_text(encoding="utf-8")
    helmet = re.search(r"<helmet>(.*?)</helmet>", src, re.S).group(1)
    body = re.search(r"</helmet>(.*?)</x-dc>", src, re.S).group(1)

    helmet = re.sub(r'\s*<link rel="preconnect"[^>]*>', "", helmet)
    helmet = re.sub(r'\s*<link href="https://fonts\.googleapis\.com[^>]*>', "", helmet)
    helmet = re.sub(
        r'<link rel="icon"[^>]*>',
        f'<link rel="icon" type="image/png" sizes="32x32" href="data:image/png;base64,{b64(IMG / "favicon-32.png")}">\n'
        f'<link rel="apple-touch-icon" href="data:image/png;base64,{b64(IMG / "apple-touch-icon.png")}">',
        helmet,
    )

    faces = []
    for fam, slug, weights in [("Instrument Sans", "instrument-sans", [400, 500, 600, 700]),
                               ("JetBrains Mono", "jetbrains-mono", [400, 500])]:
        for w in weights:
            font = FONTS / f"{slug}-latin-{w}-normal.woff2"
            faces.append(f"@font-face{{font-family:'{fam}';font-style:normal;font-weight:{w};font-display:swap;"
                         f"src:url(data:font/woff2;base64,{b64(font)}) format('woff2')}}")

    page = (
        "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<meta name=\"theme-color\" content=\"#F7F7F5\">\n"
        f"{helmet.strip()}\n<style>\n" + "\n".join(faces) + "\n</style>\n</head>\n<body>\n"
        f"{body.strip()}\n</body>\n</html>\n"
    )
    page = page.replace("{{ headline }}", HEADLINE)
    page = re.sub(r"/_blob/([0-9a-f]{32})", lambda m: "data:image/png;base64," + b64(BLOBS[m.group(1)]), page)

    leftovers = [s for s in ("{{", "/_blob/", "googleapis", "<x-dc", "<helmet") if s in page]
    if leftovers:
        raise SystemExit(f"unresolved design-tool markup: {leftovers}")
    OUT.write_text(page, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
