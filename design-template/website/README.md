# Transom website

The marketing site for Transom, the free, open-source tiling window manager for macOS (app repo: [github.com/scottkw/transomwm](https://github.com/scottkw/transomwm)). It is meant to serve at https://transomwm.app and https://www.transomwm.app from a static-assets-only Cloudflare Worker, set up the same way as `gifsmith-website`.

## Repository layout

| Path | What it is |
|------|------------|
| `public/index.html` | The whole site: one plain HTML file (about 240 KB) with fonts and icons inlined |
| `public/robots.txt` | Allow-all robots file |
| `public/.assetsignore` | Keeps OS and editor junk out of the upload |
| `source/Website.dc.html` | The design source: the "Website" artboard from the Transom Design canvas |
| `source/fonts/` | Instrument Sans and JetBrains Mono latin woff2 subsets, with their OFL licenses |
| `source/img/` | The icon PNGs the page inlines |
| `scripts/build.py` | Turns the artboard into `public/index.html` |
| `wrangler.jsonc` | Worker config: name, static assets directory, custom domains |

Only `public/` is deployed.

## How it differs from GIFsmith's site

GIFsmith's `index.html` is the design tool's self-unpacking bundle (React and a runtime, content in a JSON string). This one is real HTML and CSS: the build step strips the design wrapper instead of bundling a runtime. So:

- It needs no JavaScript. The hero demo is a CSS animation, and it holds still for visitors who ask for reduced motion.
- Crawlers and link previews see all the content and the meta description.
- It makes no outside requests. Fonts and images are data URIs.

## Updating the page

1. Edit the "Website" artboard on the Transom Design canvas.
2. Save the artboard's source over `source/Website.dc.html` (ask Claude to read the canvas, or copy it from the artboard's code view).
3. Run `python3 -I scripts/build.py` from the repo root. It refuses to write a page that still has design-tool markup in it.
4. Preview, commit and push.

The hero headline is the artboard's `headline` tweak (`overlap`, `dock`, `tidy`). The build uses `HEADLINE` in `scripts/build.py`; change it there to match.

If a new image is added on the canvas, it appears as a new `/_blob/<id>` URL. Add the file to `source/img/` and map the id in `BLOBS`, or the build stops with an error.

## Local preview

```bash
npx wrangler@4.151.2 dev --port 8799
```

Or open `public/index.html` directly in a browser.

## Deploying (same pipeline as gifsmith-website)

One-time setup:

1. Create a private GitHub repo `scottkw/transomwm-website` and push this folder.
2. Add the `transomwm.app` zone to the Cloudflare account if it isn't there yet.
3. Dashboard → Workers & Pages → Create → Import a repository → `transomwm-website`. Branch `main`, build command empty, deploy command `npx wrangler@4.151.2 deploy`, root `/`. The Worker name must be `transomwm-website` to match `wrangler.jsonc`.
4. Settings → Builds → turn off "Builds for Preview branches".

After that, every push to `main` deploys. Watch the `Workers Builds: transomwm-website` check on the commit.

The first attach of the custom domains may need DNS Edit, which the Workers Builds token is documented not to have (see the GIFsmith README's Gotchas). If the first CI deploy can't attach `transomwm.app`, run one local deploy with a token that has Workers Scripts Edit, Workers Routes Edit and DNS Edit on the zone:

```bash
CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... npx wrangler@4.151.2 deploy
```

Verify a deploy:

```bash
curl -s https://transomwm.app/ | shasum -a 256
shasum -a 256 public/index.html
```

Rollback: `git revert <bad-commit> && git push origin main`, or `npx wrangler@4.151.2 rollback <version-id>` for an instant one, followed by the revert.

## Before launch

The page is written for the pre-release: the "Get Transom" section has no download button, and the roadmap shows Phase 4 in progress. When 0.3.0 goes public, edit those on the canvas (download link to `releases/latest`, the requirements line, the checksum block if you want one like GIFsmith's) and rebuild.
