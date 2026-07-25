"""Palette-lock CONTENT check (Req 5.7/7.2, Decision 23).

Decision 23 established that a palette label can be redefined in place — the
label alone no longer changes when the palette does, so the label-only lock
cannot detect a stale artifact. The lock therefore has a content check: the
ordered class list parsed from ClassPalette.swift's current standard palette
(foodClasses then liquidClasses, declaration order, sentinels excluded) must
equal FOOD_DATA's class ids exactly. A stale pre-cereal list must fail on
CONTENT while the label still reads "v2".
"""

import pytest

import generate

LIQUID_CLASSES = ["water", "coffee", "tea", "milk",
                  "fruit_juice", "soup", "beer", "wine"]

# A stale v2Standard: the label says "v2" but the content predates the cereal
# class (and the liquids) — exactly the drift the label-only lock cannot see.
STALE_PRECEREAL_SWIFT = """
public extension ClassPalette {
    static let v2Standard = ClassPalette(
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
        version: "v2"
    )
}
"""


def test_palette_class_list_reads_food_then_liquid():
    # Canonical order per design §DB bake: foodClasses then liquidClasses,
    # declaration order, sentinels excluded. Palette v2: 25 solids (cereal
    # appended at index 24) + 8 liquids at [25:].
    class_list = generate.palette_class_list()
    assert len(class_list) == 33
    assert class_list == [row[0] for row in generate.FOOD_DATA]
    assert class_list[24] == "cereal"
    assert class_list[25:] == LIQUID_CLASSES


def test_content_lock_passes_on_current_palette():
    generate.verify_palette_lock(generate.PALETTE_VERSION)  # must not raise


def test_stale_precereal_palette_fails_on_content(tmp_path, monkeypatch):
    stale = tmp_path / "ClassPalette.swift"
    stale.write_text(STALE_PRECEREAL_SWIFT)
    monkeypatch.setattr(generate, "_CLASS_PALETTE_SWIFT", stale)
    # The label matches ("v2") — the CONTENT mismatch must abort the bake.
    with pytest.raises(SystemExit, match="class list"):
        generate.verify_palette_lock("v2")


def test_reordered_palette_fails_on_content(tmp_path, monkeypatch):
    # Same v2 members, different order: channel order is load-bearing, so a
    # reorder is drift the lock must catch too.
    reordered = STALE_PRECEREAL_SWIFT.replace(
        '"white_rice", "brown_rice"', '"brown_rice", "white_rice"'
    ).replace(
        '"tomato", "mixed_vegetables"',
        '"tomato", "mixed_vegetables", "cereal"', 1
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
        generate.verify_palette_lock("v2")
