# Transom icons

The mark is an arched transom light (the fanlight over a door) above three non-overlapping tiles. It reads as a window and as a tiled layout. The lit fanlight is the brand accent.

Colors: tile #232B3B → #0D1118 (flat #141A26 in the Icon Composer file), fanlight #5E8BFF → #2E5AE0 (flat #3D6BF0), panes #F7F5F0 → #E8E5DD (flat #F2F0EA).

## App icon

| File | Use |
|---|---|
| `app/Transom-AppIcon.svg` | Vector source, 1024 canvas, macOS icon grid (824 pt body at 100,100, radius 185, drop shadow) |
| `app/Transom-AppIcon-small.svg` | Simplified art for the 16 and 32 px slots: no muntins, wider gaps |
| `app/appicon.png` | 1024 px master |
| `app/Transom.iconset/` | Every macOS size, already named with `@2x`, so `iconutil -c icns app/Transom.iconset` works as is |
| `app/Transom.icns` | Prebuilt from the iconset. Set `CFBundleIconFile` to `Transom` and copy it into Resources |
| `app/AppIcon.appiconset/` | Drop into an `.xcassets` catalog and set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` |
| `app/Transom.icon/` | Icon Composer bundle for macOS 26 (layers: muntins, fanlight, panes), same structure as GIFsmith's `build/appicon.icon`. Open it in Icon Composer to tune glass, shadow and the dark/tinted variants |

With XcodeGen, the asset-catalog route is the least work: add `AppIcon.appiconset` to an `Assets.xcassets` under the app target's sources in `xcode/project.yml`.

## Menu bar (template images, pure black + alpha)

The glyph is drawn on an 18 × 18 pt canvas. `isTemplate = true` lets macOS tint it for light, dark and highlighted menu bars.

| File | State |
|---|---|
| `menubar/TransomTemplate.*` | Normal: lit fanlight over three outlined tiles |
| `menubar/TransomZoomedTemplate.*` | Zoomed in: hollow fanlight, the focused tile filled |

Each comes as an SVG, 1x/2x/3x PNGs (18/36/54 px), and an `.imageset` (vector-preserving, template rendering intent) for an asset catalog.

Paused keeps the normal glyph: `StatusItemController` already sets `button.appearsDisabled`, which dims it. The not-ready state keeps the SF Symbol `exclamationmark.triangle`, so a missing Accessibility grant still looks like a warning.

Swap in `StatusItemController.updateGlyph()`:

```swift
let name = !ready ? nil : zoomed ? "TransomZoomedTemplate" : "TransomTemplate"
let image = name.flatMap { Bundle.main.image(forResource: $0) }
    ?? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: description)
image?.size = NSSize(width: 18, height: 18)
image?.isTemplate = true
image?.accessibilityDescription = description
button.image = image
```

`Bundle.main.image(forResource:)` picks up either the imageset in a compiled catalog or the loose `TransomTemplate.png` / `@2x` / `@3x` files in Resources.

## Web

`web/favicon-32.png`, `web/icon-64.png` and `web/apple-touch-icon.png` (180 px) are the sizes the website inlines.
