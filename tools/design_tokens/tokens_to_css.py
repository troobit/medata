#!/usr/bin/env python3
"""
Generate design-system/tokens.css from App/Colors.swift.

One direction only. `App/Colors.swift` is hand-written and authoritative; this
script reads it and never writes it. There is no SwiftPM target for the tokens:
`Makefile` `build:` runs `swift build` on the macOS host, `Package.swift`
declares `.macOS(.v14)`, and 12 of the 22 tokens use `Color(uiColor:)`, which
does not compile on macOS. A generator sidesteps that entirely and matches the
convention already used by `tools/food_db/generate.py` and
`tools/segmenter/export.py`.

Naming: every `static let <name>` becomes `--medata-<kebab(name)>`. The rule is
mechanical and has no exceptions, so `medataAccent` becomes
`--medata-medata-accent`. A carve-out would read better in one place and cost a
remembered exception in every hand-written wireframe.

`Color(uiColor: .systemX)` has no fixed sRGB value — UIKit resolves it per
appearance. The wireframes are OLED-dark, so each system colour is emitted at
its documented dark-appearance sRGB value and marked `approx` in a comment.

Run from repo root: python3 tools/design_tokens/tokens_to_css.py

Requirements: python3 (stdlib only)
"""

import argparse
import re
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_SWIFT = "App/Colors.swift"
OUTPUT_CSS = "design-system/tokens.css"

# UIKit dynamic colours resolved at their documented DARK-appearance sRGB
# values. Approximations by construction: UIKit resolves these per appearance,
# per accessibility contrast setting and per OS release. The wireframes commit
# to OLED-dark (MASTER.md "Style — three layers"), so dark is the branch taken.
SYSTEM_DARK = {
    "systemOrange": (255, 159, 10, 1.0),
    "systemRed": (255, 69, 58, 1.0),
    "systemYellow": (255, 214, 10, 1.0),
    "systemTeal": (64, 200, 224, 1.0),
    "systemPurple": (191, 90, 242, 1.0),
    "systemPink": (255, 55, 95, 1.0),
    "systemGroupedBackground": (0, 0, 0, 1.0),
    "secondarySystemGroupedBackground": (28, 28, 30, 1.0),
    "label": (255, 255, 255, 1.0),
    "secondaryLabel": (235, 235, 245, 0.60),
    "separator": (84, 84, 88, 0.65),
}

_TOKEN = re.compile(r"^\s*static let (\w+)\s*=\s*(.+?)\s*$")
_MARK = re.compile(r"^\s*// MARK: -\s*(.+?)\s*$")

_CHANNEL = r"(?:0x([0-9A-Fa-f]{1,2})\s*/\s*255|([0-9.]+))"
_RGB = re.compile(
    r"^Color\(red:\s*" + _CHANNEL + r",\s*green:\s*" + _CHANNEL +
    r",\s*blue:\s*" + _CHANNEL + r"\)$"
)
_BW = re.compile(r"^Color\.(black|white)(?:\.opacity\(([0-9.]+)\))?$")
_UICOLOR = re.compile(r"^Color\(uiColor:\s*\.(\w+)\)$")
_WHITE_LEVEL = re.compile(r"^Color\(white:\s*([0-9.]+)\)$")
_ALIAS = re.compile(r"^(\w+)(?:\.opacity\(([0-9.]+)\))?$")


class UnknownForm(Exception):
    """A `static let` whose right-hand side this parser does not model."""


def kebab(name: str) -> str:
    """`captureChromeBG` -> `capture-chrome-bg`.

    A run of capitals is one word, so the acronyms in `captureChromeBG`,
    `placeholderBG` and `placeholderFG` do not shatter into `b-g` / `f-g`.
    """
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1-\2", name)
    name = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", name)
    return name.lower()


def _channel(hex_digits, decimal) -> int:
    if hex_digits is not None:
        return int(hex_digits, 16)
    value = float(decimal)
    # Swift takes 0–1 components; a bare 255 would be a clamp, not a channel.
    return round(value * 255) if value <= 1.0 else round(value)


def resolve(expr: str, known: dict) -> tuple:
    """Resolve a right-hand side to (r, g, b, a, note).

    `note` is the provenance comment emitted beside the property, or "".
    """
    match = _RGB.match(expr)
    if match:
        g = match.groups()
        return (_channel(g[0], g[1]), _channel(g[2], g[3]), _channel(g[4], g[5]), 1.0, "")

    match = _BW.match(expr)
    if match:
        level = 0 if match.group(1) == "black" else 255
        alpha = float(match.group(2)) if match.group(2) else 1.0
        return (level, level, level, alpha, "")

    match = _UICOLOR.match(expr)
    if match:
        symbol = match.group(1)
        if symbol not in SYSTEM_DARK:
            raise UnknownForm(f"unmapped UIKit colour .{symbol}")
        r, g, b, a = SYSTEM_DARK[symbol]
        return (r, g, b, a, f"approx: .{symbol} at dark appearance")

    match = _WHITE_LEVEL.match(expr)
    if match:
        level = round(float(match.group(1)) * 255)
        return (level, level, level, 1.0, "")

    match = _ALIAS.match(expr)
    if match:
        target = match.group(1)
        if target not in known:
            raise UnknownForm(f"alias of unknown token `{target}`")
        r, g, b, a, note = known[target]
        alpha = float(match.group(2)) if match.group(2) else a
        detail = f"alias of {target}"
        if match.group(2):
            detail += f" at {match.group(2)}"
        if note.startswith("approx"):
            detail = f"approx: {detail}, {note[len('approx: '):]}"
        return (r, g, b, alpha, detail)

    raise UnknownForm(f"unparsed form `{expr}`")


def css_value(r: int, g: int, b: int, a: float) -> str:
    if a >= 1.0:
        return f"#{r:02X}{g:02X}{b:02X}"
    return f"rgb({r} {g} {b} / {a:g})"


def parse(swift_text: str) -> list:
    """Return an ordered list of ("mark", title) and ("token", ...) entries."""
    entries = []
    known = {}
    for line in swift_text.splitlines():
        mark = _MARK.match(line)
        if mark:
            entries.append(("mark", mark.group(1)))
            continue
        token = _TOKEN.match(line)
        if not token:
            continue
        name, expr = token.group(1), token.group(2)
        r, g, b, a, note = resolve(expr, known)
        known[name] = (r, g, b, a, note)
        entries.append(("token", name, expr, css_value(r, g, b, a), note))
    return entries


def render(entries: list) -> str:
    out = [
        "/* GENERATED FILE — do not edit by hand.",
        f" * Source: {SOURCE_SWIFT} (hand-written, authoritative)",
        " * Regenerate: python3 tools/design_tokens/tokens_to_css.py",
        " *",
        " * Every `static let <name>` becomes `--medata-<kebab(name)>`, with no",
        " * exceptions — hence `--medata-medata-accent`.",
        " *",
        " * Values marked `approx` come from `Color(uiColor:)`, which UIKit resolves",
        " * per appearance and therefore has no fixed sRGB value. They are emitted at",
        " * the documented DARK-appearance value, because the wireframes are OLED-dark",
        " * (design-system/MASTER.md, \"Style — three layers, used together\").",
        " */",
        "",
        ":root {",
    ]
    first_group = True
    for entry in entries:
        if entry[0] == "mark":
            if not first_group:
                out.append("")
            first_group = False
            out.append(f"  /* {entry[1]} */")
            continue
        _, name, _expr, value, note = entry
        line = f"  --medata-{kebab(name)}: {value};"
        if note:
            line += f" /* {note} */"
        out.append(line)
    out.append("}")
    out.append("")
    return "\n".join(out)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Generate tokens.css from Colors.swift")
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if the on-disk output is stale; write nothing")
    args = parser.parse_args(argv)

    source = _REPO_ROOT / SOURCE_SWIFT
    output = _REPO_ROOT / OUTPUT_CSS

    try:
        entries = parse(source.read_text(encoding="utf-8"))
    except UnknownForm as exc:
        print(f"tokens_to_css error={exc} source={SOURCE_SWIFT}", file=sys.stderr)
        return 1

    text = render(entries)
    tokens = [e for e in entries if e[0] == "token"]
    approx = sum(1 for e in tokens if e[4].startswith("approx"))
    alias = sum(1 for e in tokens if "alias of" in e[4])

    if args.check:
        stale = (not output.exists()) or output.read_text(encoding="utf-8") != text
        print(f"tokens={len(tokens)} stale={int(stale)} out={OUTPUT_CSS}")
        return 1 if stale else 0

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"tokens={len(tokens)} approx={approx} alias={alias} "
          f"groups={sum(1 for e in entries if e[0] == 'mark')} out={OUTPUT_CSS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
