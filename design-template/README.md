# Transom design template

Everything from the Transom Design canvas: icons, the website, and the canvas source.

| Folder | What it is |
|---|---|
| `icons/` | App icon and menu bar icon, exported from the canvas: SVG sources, every PNG size, `Transom.icns`, `AppIcon.appiconset`, an Icon Composer `Transom.icon`, and menu bar template images (`TransomTemplate`, `TransomZoomedTemplate`) as SVG, 1x/2x/3x PNG and `.imageset`. See `icons/README.md` for wiring them into the app. |
| `website/` | The transomwm.app Cloudflare Worker project: `public/index.html` (one self-contained file), `wrangler.jsonc`, and `scripts/build.py`, which rebuilds the page from `source/Website.dc.html`. See `website/README.md`. |
| `canvas/` | The Design canvas source: `canvas.json` plus the three artboards (`Main.dc.html` app icon, `MenuBar.dc.html` menu bar icon, `Website.dc.html` website). Images in the artboards are canvas asset URLs (`/_blob/<id>`), so they render only on the canvas. |

To change the website, edit the Website artboard on the canvas, copy it over `website/source/Website.dc.html`, then run `python3 -I scripts/build.py` from `website/`.
