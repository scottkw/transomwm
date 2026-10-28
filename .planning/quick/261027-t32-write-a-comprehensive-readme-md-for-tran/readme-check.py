#!/usr/bin/env python3
"""Checks README.md against the code for quick task 261027-t32.

Run from the repo root: python3 -I .planning/quick/261027-t32-write-a-comprehensive-readme-md-for-tran/readme-check.py
Exit 0 when every check passes, 1 with one line per failure otherwise.

Checks:
  1. Every Transom hotkey in the README (a run of modifier glyphs containing the control glyph, then one key glyph)
     is written in the canonical order (control, option, command, then shift) and is a default in
     Sources/TransomMac/Input/Hotkeys.swift; every default in Hotkeys.swift appears in the README.
  2. Every repo path the README names under Sources/, Tests/, scripts/, xcode/ or .github/ exists
     (generated build output under xcode/.xcode-build and xcode/Transom.xcodeproj is exempt).
  3. Every backticked target name (Transom* or transom-dump) is a target in Package.swift, and all eight
     non-test targets are named.
  4. "pane" (any case, as a word) appears on at most one line, and that line is the rename note.
  5. Required facts are present; no images, badges or emoji.
"""
import os
import re
import sys

README = sys.argv[1] if len(sys.argv) > 1 else "README.md"
HOTKEYS = "Sources/TransomMac/Input/Hotkeys.swift"
PACKAGE = "Package.swift"

KEY_GLYPHS = {
    "leftArrow": "←", "rightArrow": "→", "upArrow": "↑", "downArrow": "↓",
    "equal": "=", "minus": "-", "return": "↩",
    "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
    "six": "6", "seven": "7", "eight": "8", "nine": "9",
}
CTRL, OPT, CMD, SHIFT = "⌃", "⌥", "⌘", "⇧"
MODS = CTRL + OPT + CMD + SHIFT
CANONICAL = {CTRL + OPT + CMD, CTRL + OPT + CMD + SHIFT}
TARGETS_REQUIRED = [
    "TransomModel", "TransomEngine", "TransomMac", "TransomPrivate",
    "TransomApp", "TransomFixtureApp", "transom-dump", "TransomTestSupport",
]
REQUIRED_LITERALS = [
    "transomwm.app", "scottkw/transomwm", "0.3.0", "Phase 4", "macOS 14", "Apple Silicon", "Intel",
    "Accessibility", "Screen Recording", "swift build", "swift test", "XcodeGen",
    "scripts/build-debug.sh", "scripts/release.sh", "scripts/check-no-appkit.sh", "scripts/vm-live-test.sh",
    "com.eightabyte.transom.debug", "TRANSOM_LIVE", "Tart", "Application Support/Transom",
    "transom://restore", "transom://toggle-desktop", "transom://split-finder",
    "TrellisWM", "AeroSpace", "Amethyst", "yabai", "Loop", "MIT", "LICENSE",
    "_AXUIElementGetWindow", "SkyLight", "--disable-private",
]
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️]")


def code_hotkeys(failures):
    text = open(HOTKEYS, encoding="utf-8").read()
    combos = {}
    pattern = r'Self\("(\w+)", initial: \.init\(\.(\w+), modifiers: \[([^\]]*)\]\)\)'
    for name, key, mods in re.findall(pattern, text):
        glyph = KEY_GLYPHS.get(key, key.upper() if len(key) == 1 else None)
        if glyph is None:
            failures.append(f"hotkeys: no glyph mapping for key .{key} ({name}); extend KEY_GLYPHS")
            continue
        order = [(".control", CTRL), (".option", OPT), (".command", CMD), (".shift", SHIFT)]
        prefix = "".join(g for token, g in order if token in mods)
        combos[prefix + glyph] = name
    if not combos:
        failures.append(f"hotkeys: parsed no defaults from {HOTKEYS}")
    return combos


def main():
    failures = []
    if not os.path.isfile(README):
        print(f"FAIL: {README} not found (run from the repo root)")
        return 1
    readme = open(README, encoding="utf-8").read()

    # 1. Hotkeys.
    combos = code_hotkeys(failures)
    seen = set()
    for mods, key in re.findall(f"([{MODS}]{{2,}})([^\\s{MODS}])", readme):
        if CTRL not in mods:
            continue  # not a Transom hotkey (e.g. a planned command-shift drag)
        combo = mods + key
        if mods not in CANONICAL:
            failures.append(f"hotkeys: {combo} is not in the order control, option, command, shift")
        elif combo not in combos:
            failures.append(f"hotkeys: {combo} is not a default in {HOTKEYS}")
        else:
            seen.add(combo)
    for combo, name in sorted(combos.items(), key=lambda kv: kv[1]):
        if combo not in seen:
            failures.append(f"hotkeys: default {combo} ({name}) is missing from the README")

    # 2. Paths.
    path_re = re.compile(r"(?<![\w/~.])((?:Sources|Tests|scripts|xcode|\.github)/[\w./+-]*\w)")
    for path in sorted(set(path_re.findall(readme))):
        if path.startswith(("xcode/.xcode-build", "xcode/Transom.xcodeproj")):
            continue
        if not os.path.exists(path):
            failures.append(f"paths: {path} does not exist")

    # 3. Targets.
    package = open(PACKAGE, encoding="utf-8").read()
    targets = set(re.findall(r'name: "([^"]+)"', package))
    for span in re.findall(r"`([^`\n]+)`", readme):
        if re.fullmatch(r"Transom[A-Z]\w*|transom-dump", span) and span not in targets:
            failures.append(f"targets: `{span}` is not a target in {PACKAGE}")
    for target in TARGETS_REQUIRED:
        if target not in targets:
            failures.append(f"targets: {target} is no longer in {PACKAGE}; update this check")
        if target not in readme:
            failures.append(f"targets: {target} is not described in the README")

    # 4. Old name.
    pane_lines = [line for line in readme.splitlines() if re.search(r"(?i)\bpane\b", line)]
    if len(pane_lines) > 1:
        failures.append(f"name: 'pane' appears on {len(pane_lines)} lines; only the rename note may use it")
    for line in pane_lines:
        if "renamed" not in line.lower():
            failures.append(f"name: 'pane' outside the rename note: {line.strip()[:100]}")

    # 5. Facts, images, emoji.
    for literal in REQUIRED_LITERALS:
        if literal not in readme:
            failures.append(f"facts: missing required text {literal!r}")
    if "![" in readme or "shields.io" in readme or "<img" in readme.lower():
        failures.append("style: images or badges found")
    for match in EMOJI.finditer(readme):
        failures.append(f"style: emoji or dingbat U+{ord(match.group()):04X} found")
        break

    for failure in failures:
        print(f"FAIL: {failure}")
    if failures:
        return 1
    print(f"OK: {len(combos)} hotkeys matched, README checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
