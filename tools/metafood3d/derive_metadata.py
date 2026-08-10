#!/usr/bin/env python3
"""Derive ``metadata.csv`` from the shipped MetaFood3D nutrition workbook.

Stdlib-only (zipfile + ElementTree — no openpyxl), because this is the one
step between "downloaded the dataset" and "ingest can run" and it must not
require the render venv.

The workbook is the request-gated dataset's
``complete_dataset_nutrition_v2.xlsx``: one sheet, one header row, one row
per food object. This tool is deliberately RIGID (cross-dataset-calibration
Decision 19): it accepts exactly the known v2 header and aborts loudly on
any deviation, naming what was found and what was expected — a changed
snapshot is reconciled by a human reading that message, not by parser
guesswork.

Column mapping (the workbook's names are inverted from what you'd guess):

- ``Object_name``  -> ``category``  (e.g. ``Almond(bowl)`` — the folder
  name in the mesh tree)
- ``Food_Type``    -> ``object_id`` (e.g. ``almond_1`` — the object's
  directory name inside its category)
- ``Weight (g)``   -> ``weight_g``  (written through verbatim; ingest.py
  judges malformed weights, this tool does not)

Beside the CSV it writes ``categories.txt`` (sorted unique raw category
names, one per line) — the enumeration ``build_mapping.py
--categories-file`` consumes to regenerate the mapping artifact with the
stale-rule abort armed.

Usage::

    python3 tools/metafood3d/derive_metadata.py \\
        --xlsx data/_MetaFood3D_new_complete_dataset_nutrition_v2.xlsx \\
        --out data/metafood3d/metadata.csv
"""

from __future__ import annotations

import argparse
import csv
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"

# The v2 workbook's exact header row. Any mismatch aborts: a renamed or
# reordered column means a new snapshot whose semantics a human must
# confirm before rows flow into calibration.
EXPECTED_HEADER = [
    "Object_name", "Food_Type", "FNDDS Food Code", "Weight (g)",
    "Energy (Kcal)", "Protein (g)", "Fat (g)", "Carbs (g)", "Volume",
]

OUTPUT_HEADER = ["object_id", "category", "weight_g"]


def _die(message: str) -> None:
    raise SystemExit(f"[derive_metadata] {message}")


def _shared_strings(book: zipfile.ZipFile) -> list[str]:
    try:
        root = ET.fromstring(book.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    return ["".join(t.text or "" for t in si.iter(f"{_NS}t"))
            for si in root.findall(f"{_NS}si")]


def _cell_value(cell: ET.Element, shared: list[str]) -> str:
    v = cell.find(f"{_NS}v")
    if v is None or v.text is None:
        return ""
    kind = cell.get("t")
    if kind == "s":
        return shared[int(v.text)]
    if kind in (None, "n", "str"):
        return v.text
    _die(f"unsupported cell type {kind!r} in cell {cell.get('r')!r} — "
         f"this tool reads the known v2 workbook shape only; inspect the "
         f"new workbook and extend deliberately.")
    raise AssertionError  # unreachable


def read_rows(xlsx_path: Path) -> list[list[str]]:
    """All rows of sheet1 as string lists, header first."""
    if not xlsx_path.is_file():
        _die(f"workbook not found: {xlsx_path}")
    with zipfile.ZipFile(xlsx_path) as book:
        if "xl/worksheets/sheet1.xml" not in book.namelist():
            _die(f"{xlsx_path} has no xl/worksheets/sheet1.xml — not the "
                 f"single-sheet nutrition workbook this tool reads.")
        shared = _shared_strings(book)
        sheet = ET.fromstring(book.read("xl/worksheets/sheet1.xml"))
    return [[_cell_value(c, shared) for c in row.findall(f"{_NS}c")]
            for row in sheet.iter(f"{_NS}row")]


def derive(rows: list[list[str]]) -> list[tuple[str, str, str]]:
    """(object_id, category, weight_g) triples, aborting on any deviation
    from the v2 shape."""
    if not rows:
        _die("workbook sheet is empty.")
    header = rows[0]
    if header != EXPECTED_HEADER:
        _die("unexpected header row.\n"
             f"  found:    {header}\n"
             f"  expected: {EXPECTED_HEADER}\n"
             "A changed snapshot must be reconciled deliberately: confirm "
             "the new columns' semantics, then update EXPECTED_HEADER and "
             "the column mapping in this tool.")
    triples: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for i, row in enumerate(rows[1:], start=2):
        padded = row + [""] * (len(EXPECTED_HEADER) - len(row))
        category, object_id, _code, weight_g = (
            padded[0].strip(), padded[1].strip(), padded[2], padded[3].strip())
        if not category or not object_id:
            _die(f"row {i}: blank Object_name or Food_Type "
                 f"({row!r}) — every data row must identify one object.")
        key = (category, object_id)
        if key in seen:
            _die(f"row {i}: duplicate object {category!r}/{object_id!r} — "
                 f"one workbook row per object.")
        seen.add(key)
        triples.append((object_id, category, weight_g))
    if not triples:
        _die("workbook has a header but no data rows.")
    return triples


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xlsx", required=True,
                        help="The shipped complete_dataset_nutrition_v2 "
                             "workbook.")
    parser.add_argument("--out", required=True,
                        help="metadata.csv destination (put it at the "
                             "MetaFood3D snapshot root, next to 3D_Mesh/).")
    args = parser.parse_args(argv)

    triples = derive(read_rows(Path(args.xlsx)))

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(OUTPUT_HEADER)
        writer.writerows(triples)
    categories = sorted({c for _o, c, _w in triples})
    categories_path = out_path.parent / "categories.txt"
    categories_path.write_text("\n".join(categories) + "\n")
    print(f"[derive_metadata] wrote {len(triples)} objects "
          f"({len(categories)} categories) -> {out_path}")
    print(f"[derive_metadata] wrote enumeration -> {categories_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
