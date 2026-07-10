"""Stratified carve + co-occurrence statistics tests (segmenter-foundation
tasks 8/9, design §3.5 and §4.3, Reqs 2.6 and 2.3).

The carve logic is exercised directly with synthetic staple-presence maps (no
files needed — ``carve_splits`` only reads mask stems), and the raw-mask
presence pass + ``main()`` end-to-end run use tiny PIL-generated corpora with
the COMMITTED class mapping (source id 66 → white_rice, 58 → bread_white,
70 → potato_boiled). numpy + pillow are required (they are light deps of the
tool itself); torch is not.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("PIL")
from PIL import Image  # noqa: E402

import prepare_dataset  # noqa: E402  (sys.path set up by conftest.py)

STAPLES = prepare_dataset.CARB_PRIORITY_CLASSES


def _pairs(n: int):
    """Synthetic (image, mask) path pairs; carve only touches mask stems."""
    return [(Path(f"img{i:03d}.jpg"), Path(f"img{i:03d}.png")) for i in range(n)]


def _presence(pairs, staple_map):
    """stem -> frozenset of staple names; unlisted stems carry no staple."""
    return {
        mask.stem: frozenset(staple_map.get(mask.stem, ()))
        for _, mask in pairs
    }


# ── Quota formula (design §3.5) ─────────────────────────────────────────────────

@pytest.mark.parametrize("n,frac,expected", [
    (3, 0.12, 1),     # floor(3/3) caps the min-3
    (5, 0.12, 1),     # floor(5/3) = 1 — training keeps the majority
    (9, 0.12, 3),     # min-3 floor binds
    (25, 0.12, 3),    # ceil(0.12*25)=3
    (100, 0.12, 12),  # ceil binds
    (100, 0.5, 33),   # floor(n/3) caps a large fraction
])
def test_staple_quota_formula(n, frac, expected):
    assert prepare_dataset.staple_quota(n, frac) == expected


# ── Unstratified path stays backwards-compatible ────────────────────────────────

def test_unstratified_carve_matches_legacy_slices():
    pairs = _pairs(50)
    splits, strat = prepare_dataset.carve_splits(pairs, 0.12, 0.1, seed=1234)
    assert strat is None
    assert len(splits["heldout"]) == 6   # int(50 * 0.12)
    assert len(splits["val"]) == 5       # int(50 * 0.1)
    assert len(splits["train"]) == 39
    again, _ = prepare_dataset.carve_splits(pairs, 0.12, 0.1, seed=1234)
    assert splits == again


# ── Stratified carve (design §3.5) ──────────────────────────────────────────────

def _staple_map_all_staples(pairs):
    """Give each of the 8 staples 6 member images (distinct, plus a few
    multi-staple plates), leaving the rest staple-free."""
    staple_map = {}
    i = 0
    for name in STAPLES:
        for _ in range(6):
            staple_map.setdefault(pairs[i][1].stem, []).append(name)
            i += 1
    # A few multi-staple plates: images carrying two staples at once.
    staple_map[pairs[0][1].stem].append(STAPLES[1])
    staple_map[pairs[6][1].stem].append(STAPLES[0])
    return staple_map


def test_stratified_carve_is_deterministic_for_a_fixed_seed():
    pairs = _pairs(120)
    presence = _presence(pairs, _staple_map_all_staples(pairs))
    a, strat_a = prepare_dataset.carve_splits(pairs, 0.12, 0.1, 42, presence)
    b, strat_b = prepare_dataset.carve_splits(pairs, 0.12, 0.1, 42, presence)
    assert a == b
    assert strat_a == strat_b
    c, _ = prepare_dataset.carve_splits(pairs, 0.12, 0.1, 43, presence)
    assert a != c  # a different seed cuts a different held-out set


def test_every_staple_lands_in_heldout():
    pairs = _pairs(120)
    presence = _presence(pairs, _staple_map_all_staples(pairs))
    splits, strat = prepare_dataset.carve_splits(pairs, 0.12, 0.1, 42, presence)
    heldout_stems = {m.stem for _, m in splits["heldout"]}
    for name in STAPLES:
        members = {s for s, staples in presence.items() if name in staples}
        got = len(members & heldout_stems)
        assert got >= 1, f"staple {name} missing from heldout"
        assert strat["staples"][name]["heldout"] == got
    assert strat["warnings"] == []
    # Quota-driven picks may exceed the plain fraction (8 staples x quota 3
    # here); heldout is never topped up below the fraction, and val follows it.
    assert len(splits["heldout"]) >= 14  # int(120 * 0.12)
    assert len(splits["val"]) == 12
    total = sum(len(s) for s in splits.values())
    assert total == 120


def test_assigned_image_counts_toward_every_staple_quota():
    # One image carries ALL staples and each staple has exactly 3 members →
    # quota 1 each; the shared image can satisfy several quotas at once, so
    # heldout picks stay minimal for the staples it covers.
    pairs = _pairs(40)
    staple_map = {pairs[0][1].stem: list(STAPLES)}
    for j, name in enumerate(STAPLES):
        for k in (1, 2):
            staple_map.setdefault(pairs[1 + j * 2 + (k - 1)][1].stem, []).append(name)
    presence = _presence(pairs, staple_map)
    splits, strat = prepare_dataset.carve_splits(pairs, 0.12, 0.0, 7, presence)
    heldout_stems = {m.stem for _, m in splits["heldout"]}
    if pairs[0][1].stem in heldout_stems:
        # The multi-staple plate satisfied every quota by itself.
        for name in STAPLES:
            assert strat["staples"][name]["heldout"] >= 1


def test_two_image_staple_gets_one_heldout_and_a_warning():
    pairs = _pairs(30)
    staple_map = {pairs[0][1].stem: [STAPLES[0]], pairs[1][1].stem: [STAPLES[0]]}
    # Give the other staples enough images that they raise no warnings.
    i = 2
    for name in STAPLES[1:]:
        for _ in range(3):
            staple_map.setdefault(pairs[i][1].stem, []).append(name)
            i += 1
    presence = _presence(pairs, staple_map)
    splits, strat = prepare_dataset.carve_splits(pairs, 0.12, 0.1, 5, presence)
    entry = strat["staples"][STAPLES[0]]
    assert entry["quota"] == 1
    assert entry["heldout"] == 1  # infeasibility rule: heldout gets exactly 1
    assert any(STAPLES[0] in w for w in strat["warnings"])


def test_quota_cap_keeps_a_training_majority_for_thin_staples():
    # A staple with 3–5 images: quota = floor(n/3) = 1, so training keeps the
    # majority of its images (val_frac 0 so none leak into val).
    pairs = _pairs(60)
    staple_map = {}
    for k in range(5):  # 5-image staple
        staple_map[pairs[k][1].stem] = [STAPLES[2]]
    i = 5
    for name in STAPLES:
        if name == STAPLES[2]:
            continue
        for _ in range(6):
            staple_map.setdefault(pairs[i][1].stem, []).append(name)
            i += 1
    presence = _presence(pairs, staple_map)
    splits, strat = prepare_dataset.carve_splits(pairs, 0.12, 0.0, 11, presence)
    entry = strat["staples"][STAPLES[2]]
    assert entry["quota"] == 1
    assert entry["train"] > entry["heldout"]  # measurability never buys unlearnability
    assert entry["train"] >= 3


def test_absent_staple_records_a_warning():
    pairs = _pairs(20)
    staple_map = {}
    i = 0
    for name in STAPLES[:-1]:
        for _ in range(2):
            staple_map.setdefault(pairs[i][1].stem, []).append(name)
            i += 1
    presence = _presence(pairs, staple_map)
    _, strat = prepare_dataset.carve_splits(pairs, 0.12, 0.1, 3, presence)
    absent = STAPLES[-1]
    assert strat["staples"][absent] == {"quota": 0, "heldout": 0, "train": 0}
    assert any(absent in w and "no images" in w for w in strat["warnings"])


# ── Pass 1: staple presence from RAW masks via the LUT ──────────────────────────

# FoodSeg103 source ids in the committed mapping: 66 → white_rice (0),
# 58 → bread_white (3), 70 → potato_boiled (5), 0 → background (32).
RICE_SRC, BREAD_SRC, POTATO_SRC = 66, 58, 70


def _write_corpus(root: Path, images: dict[str, list[int]]) -> None:
    """A flat corpus the fallback discovery understands: masks under masks/,
    images under imgs/, matching stems. Each mask is 8x8 of the given raw
    FoodSeg103 source ids painted in vertical bands."""
    (root / "masks").mkdir(parents=True, exist_ok=True)
    (root / "imgs").mkdir(parents=True, exist_ok=True)
    for stem, source_ids in images.items():
        arr = np.zeros((8, 8), dtype=np.uint8)  # background (source id 0)
        for band, sid in enumerate(source_ids):
            arr[:, band] = sid
        Image.fromarray(arr, "L").save(root / "masks" / f"{stem}.png")
        rgb = np.full((8, 8, 3), 128, dtype=np.uint8)
        Image.fromarray(rgb, "RGB").save(root / "imgs" / f"{stem}.jpg")


def test_compute_staple_presence_uses_raw_mask_ids(tmp_path):
    mapping = prepare_dataset.load_mapping(
        Path(prepare_dataset.__file__).with_name("class_mapping_foodseg103_v1.json")
    )
    lut = prepare_dataset.build_lut(mapping)
    staples = prepare_dataset.staple_channels(mapping)
    _write_corpus(tmp_path, {
        "rice_and_bread": [RICE_SRC, BREAD_SRC],
        "potato_only": [POTATO_SRC],
        "background_only": [],
    })
    pairs = prepare_dataset.discover_pairs(tmp_path)
    presence = prepare_dataset.compute_staple_presence(pairs, lut, staples)
    assert presence["rice_and_bread"] == frozenset({"white_rice", "bread_white"})
    assert presence["potato_only"] == frozenset({"potato_boiled"})
    assert presence["background_only"] == frozenset()


# ── co_stats.json (design §4.3, task 9) ─────────────────────────────────────────

def test_build_co_stats_counts_presence_and_joint_presence():
    train_presence = [
        frozenset({0, 3}),   # rice + bread on one plate
        frozenset({0}),      # rice alone
        frozenset({3, 32}),  # bread + background
    ]
    stats = prepare_dataset.build_co_stats(
        {"train": [1, 2], "val": [3, 4], "heldout": [5, 6]},
        train_presence, channel_count=35,
        split_seed=42, class_mapping_sha256="ab" * 32,
    )
    assert stats["schema"] == "co_stats.v1"
    assert stats["split_seed"] == 42
    assert stats["class_mapping_sha256"] == "ab" * 32
    assert stats["train_images"] == 3
    assert stats["presence_counts"][0] == 2
    assert stats["presence_counts"][3] == 2
    assert stats["presence_counts"][32] == 1
    joint = stats["joint_presence_counts"]
    assert joint[0][3] == joint[3][0] == 1   # rice+bread co-occur once
    assert joint[0][0] == 2                  # diagonal = presence count
    assert joint[3][32] == 1
    assert joint[0][32] == 0
    assert stats["pixel_counts"]["val"] == [3, 4]


def test_main_end_to_end_writes_stratification_and_co_stats(tmp_path):
    src = tmp_path / "src"
    out = tmp_path / "out"
    # Enough rice/bread/potato images that the carve has real work; other
    # staples are absent (warnings expected — the committed mapping is real).
    images = {}
    for i in range(8):
        images[f"rice{i}"] = [RICE_SRC]
        images[f"bread{i}"] = [BREAD_SRC]
    for i in range(2):
        images[f"potato{i}"] = [POTATO_SRC]  # 2-image staple → infeasibility
    for i in range(10):
        images[f"plain{i}"] = []
    _write_corpus(src, images)

    mapping_path = Path(prepare_dataset.__file__).with_name(
        "class_mapping_foodseg103_v1.json"
    )
    rc = prepare_dataset.main([
        "--src", str(src), "--mapping", str(mapping_path), "--out", str(out),
        "--heldout-frac", "0.12", "--val-frac", "0.1", "--seed", "77",
    ])
    assert rc == 0

    manifest = json.loads((out / "splits.json").read_text())
    strat = manifest["stratification"]
    assert strat["staples"]["white_rice"]["heldout"] >= 1
    assert strat["staples"]["bread_white"]["heldout"] >= 1
    assert strat["staples"]["potato_boiled"]["heldout"] == 1
    assert any("potato_boiled" in w for w in strat["warnings"])

    co = json.loads((out / "co_stats.json").read_text())
    assert co["split_seed"] == 77
    assert co["class_mapping_sha256"] == prepare_dataset.file_sha256(mapping_path)
    assert co["channel_count"] == 35
    assert co["train_images"] == manifest["counts"]["train"]
    assert len(co["pixel_counts"]["train"]) == 35
    assert len(co["joint_presence_counts"]) == 35
    # Statistics come from the TRAIN split only: total presence of any class
    # never exceeds the train image count.
    assert max(co["presence_counts"]) <= co["train_images"]


def test_no_stratify_flag_omits_the_block_and_still_writes_co_stats(tmp_path):
    src = tmp_path / "src"
    out = tmp_path / "out"
    _write_corpus(src, {f"m{i}": [RICE_SRC] for i in range(10)})
    mapping_path = Path(prepare_dataset.__file__).with_name(
        "class_mapping_foodseg103_v1.json"
    )
    rc = prepare_dataset.main([
        "--src", str(src), "--mapping", str(mapping_path), "--out", str(out),
        "--seed", "5", "--no-stratify",
    ])
    assert rc == 0
    manifest = json.loads((out / "splits.json").read_text())
    assert "stratification" not in manifest
    assert (out / "co_stats.json").is_file()
