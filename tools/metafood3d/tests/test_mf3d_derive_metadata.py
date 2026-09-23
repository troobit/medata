"""Tests for derive_metadata.py (Decision 19).

The tool is rigid: it accepts exactly the known v2 nutrition-workbook
header and aborts loudly on any deviation. These tests build minimal
synthetic xlsx files with the stdlib (the tool reads only
``xl/sharedStrings.xml`` + ``xl/worksheets/sheet1.xml``), so they run on
system python — no venv needed.
"""

import csv
import zipfile
from pathlib import Path

import pytest

from mf3d_testkit import load_tool

derive_metadata = load_tool("derive_metadata")

V2_HEADER = derive_metadata.EXPECTED_HEADER


def write_xlsx(path: Path, rows: list[list]) -> Path:
    """Minimal single-sheet workbook: strings via sharedStrings, numbers
    as plain cells — the two cell kinds the real v2 file uses."""
    shared: list[str] = []

    def cell(ref: str, value) -> str:
        if isinstance(value, str):
            if value not in shared:
                shared.append(value)
            return (f'<c r="{ref}" t="s">'
                    f"<v>{shared.index(value)}</v></c>")
        return f'<c r="{ref}"><v>{value}</v></c>'

    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    body = []
    for r, row in enumerate(rows, start=1):
        cells = "".join(
            cell(f"{chr(ord('A') + i)}{r}", v) for i, v in enumerate(row))
        body.append(f'<row r="{r}">{cells}</row>')
    sheet = (f'<?xml version="1.0"?><worksheet {ns}>'
             f'<sheetData>{"".join(body)}</sheetData></worksheet>')
    strings = "".join(f"<si><t>{s}</t></si>" for s in shared)
    sst = (f'<?xml version="1.0"?><sst {ns} count="{len(shared)}" '
           f'uniqueCount="{len(shared)}">{strings}</sst>')
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("xl/worksheets/sheet1.xml", sheet)
        z.writestr("xl/sharedStrings.xml", sst)
    return path


def _derive(tmp_path, rows):
    xlsx = write_xlsx(tmp_path / "nutrition.xlsx", rows)
    out = tmp_path / "metadata.csv"
    rc = derive_metadata.main(["--xlsx", str(xlsx), "--out", str(out)])
    assert rc == 0
    with open(out, newline="") as fh:
        return list(csv.DictReader(fh))


class TestDerivation:
    def test_maps_the_inverted_workbook_columns(self, tmp_path):
        # Object_name is the CATEGORY, Food_Type is the OBJECT — the
        # workbook's names are inverted from what you'd guess.
        rows = _derive(tmp_path, [
            V2_HEADER,
            ["Almond(bowl)", "almond_1", 42100100, 187, 1118.26,
             39.2, 98.2, 39.3, 341.29],
        ])
        assert rows == [{"object_id": "almond_1",
                         "category": "Almond(bowl)",
                         "weight_g": "187"}]

    def test_weight_is_written_through_verbatim(self, tmp_path):
        # Judging malformed weights is ingest.py's job, not this tool's.
        rows = _derive(tmp_path, [
            V2_HEADER,
            ["Almonds", "almond_2", 1, "", 0, 0, 0, 0, 0],
        ])
        assert rows[0]["weight_g"] == ""

    def test_writes_the_category_enumeration_beside_the_csv(self, tmp_path):
        # categories.txt is the build_mapping.py --categories-file input:
        # sorted unique raw category names, one per line.
        _derive(tmp_path, [
            V2_HEADER,
            ["Steak", "steak_1", 1, 100, 0, 0, 0, 0, 0],
            ["Apple", "apple_1", 1, 80, 0, 0, 0, 0, 0],
            ["Steak", "steak_2", 1, 120, 0, 0, 0, 0, 0],
        ])
        enumeration = (tmp_path / "categories.txt").read_text()
        assert enumeration == "Apple\nSteak\n"

    def test_duplicate_object_names_in_distinct_categories_pass(self, tmp_path):
        # The real snapshot repeats Food_Type across categories.
        rows = _derive(tmp_path, [
            V2_HEADER,
            ["Almond(bowl)", "almond_3", 1, 264, 0, 0, 0, 0, 0],
            ["Almonds", "almond_3", 1, 30, 0, 0, 0, 0, 0],
        ])
        assert len(rows) == 2


class TestRigidity:
    def test_changed_header_aborts_showing_both(self, tmp_path):
        header = list(V2_HEADER)
        header[3] = "Weight (kg)"
        xlsx = write_xlsx(tmp_path / "n.xlsx", [header])
        with pytest.raises(SystemExit, match=r"Weight \(kg\)") as exc:
            derive_metadata.main(["--xlsx", str(xlsx),
                                  "--out", str(tmp_path / "m.csv")])
        assert "Weight (g)" in str(exc.value)  # expected shown beside found

    def test_duplicate_object_in_same_category_aborts(self, tmp_path):
        xlsx = write_xlsx(tmp_path / "n.xlsx", [
            V2_HEADER,
            ["Almonds", "almond_2", 1, 30, 0, 0, 0, 0, 0],
            ["Almonds", "almond_2", 1, 31, 0, 0, 0, 0, 0],
        ])
        with pytest.raises(SystemExit, match="duplicate"):
            derive_metadata.main(["--xlsx", str(xlsx),
                                  "--out", str(tmp_path / "m.csv")])

    def test_blank_identity_aborts(self, tmp_path):
        xlsx = write_xlsx(tmp_path / "n.xlsx", [
            V2_HEADER,
            ["", "almond_2", 1, 30, 0, 0, 0, 0, 0],
        ])
        with pytest.raises(SystemExit, match="blank"):
            derive_metadata.main(["--xlsx", str(xlsx),
                                  "--out", str(tmp_path / "m.csv")])

    def test_missing_workbook_aborts(self, tmp_path):
        with pytest.raises(SystemExit, match="not found"):
            derive_metadata.main(["--xlsx", str(tmp_path / "absent.xlsx"),
                                  "--out", str(tmp_path / "m.csv")])

    def test_header_only_aborts(self, tmp_path):
        xlsx = write_xlsx(tmp_path / "n.xlsx", [V2_HEADER])
        with pytest.raises(SystemExit, match="no data rows"):
            derive_metadata.main(["--xlsx", str(xlsx),
                                  "--out", str(tmp_path / "m.csv")])
