"""Palette-lock CONTENT check (Req 5.7/7.2, Decision 23).

Decision 23 redefines v1 in place — the "v1" label no longer changes when the
palette does, so the label-only lock cannot detect a stale artifact. The lock
gains a content check: the ordered class list parsed from ClassPalette.swift
(foodClasses then liquidClasses, declaration order, sentinels excluded) must
equal FOOD_DATA's class ids exactly. A stale pre-liquid list must fail on
CONTENT while the label still reads "v1".
"""

import pytest

import generate

LIQUID_CLASSES = ["water", "coffee", "tea", "milk",
                  "fruit_juice", "soup", "beer", "wine"]

# A pre-liquid v1Standard: the label says "v1" but the content predates the
# liquid classes — exactly the drift the label-only lock cannot see.
STALE_PRELIQUID_SWIFT = """
public extension ClassPalette {
    static let v1Standard = ClassPalette(
        foodClasses: [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
            "pork", "fish_white", "egg", "cheese", "salad_leaves",
            "broccoli", "carrot", "peas", "beans_baked", "lentils",
            "apple", "banana", "tomato", "mixed_vegetables"
        ],
        background: 24,
        unknownFood: 25,
        unsupportedLiquid: 26,
        version: "v1"
    )
}
"""


def test_palette_class_list_reads_food_then_liquid():
    # Canonical order per design §DB bake: foodClasses then liquidClasses,
    # declaration order, sentinels excluded.
    class_list = generate.palette_class_list()
    assert len(class_list) == 32
    assert class_list == [row[0] for row in generate.FOOD_DATA]
    assert class_list[24:] == LIQUID_CLASSES


def test_content_lock_passes_on_current_palette():
    generate.verify_palette_lock(generate.PALETTE_VERSION)  # must not raise


def test_stale_preliquid_palette_fails_on_content(tmp_path, monkeypatch):
    stale = tmp_path / "ClassPalette.swift"
    stale.write_text(STALE_PRELIQUID_SWIFT)
    monkeypatch.setattr(generate, "_CLASS_PALETTE_SWIFT", stale)
    # The label matches ("v1") — the CONTENT mismatch must abort the bake.
    with pytest.raises(SystemExit, match="class list"):
        generate.verify_palette_lock("v1")


def test_reordered_palette_fails_on_content(tmp_path, monkeypatch):
    # Same members, different order: channel order is load-bearing, so a
    # reorder is drift the lock must catch too.
    reordered = STALE_PRELIQUID_SWIFT.replace(
        '"white_rice", "brown_rice"', '"brown_rice", "white_rice"'
    ).replace(
        "foodClasses: [",
        "foodClasses: [", 1
    ).replace(
        "],\n        background",
        """],
        liquidClasses: [
            "coffee", "water", "tea", "milk",
            "fruit_juice", "soup", "beer", "wine"
        ],
        background""", 1
    )
    swift = tmp_path / "ClassPalette.swift"
    swift.write_text(reordered)
    monkeypatch.setattr(generate, "_CLASS_PALETTE_SWIFT", swift)
    with pytest.raises(SystemExit, match="class list"):
        generate.verify_palette_lock("v1")
