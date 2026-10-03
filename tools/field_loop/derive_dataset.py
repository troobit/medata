#!/usr/bin/env python3
"""Turn field captures into training and calibration material (Req 8.4-8.6).

The loop's end state is its own redundancy: every capture that carries signal —
a note, a correction, a stated quantity — becomes material the segmenter and
the calibration can be refitted on, until real-world readings no longer need a
human note. This module is where that conversion happens, and it follows
`merge_corpus_foodrec2022.py` exactly rather than inventing a third layout:
`<split>/images`, `<split>/masks`, `splits.json`, `co_stats.json`, one source
prefix (`fld_`) so stems cannot collide.

Four refusals are the substance of it:

* **The frozen anchor is never written.** Field data reaches `train` and `val`
  only. The leak-free heldout anchor is the surface every promotion verdict is
  measured on; a field image in it would make the model's own kitchen its exam
  paper. The derivation asserts the anchor is untouched and aborts if a field
  stem is found there.
* **The mixing cap** (Req 8.5). Field images may be at most
  `field_train_share_cap` of the MERGED train set, so one developer's plates,
  lighting and habits cannot dominate. Captures over the cap are deferred, not
  discarded.
* **The evaluation-floor guard.** Consuming a capture removes it from the
  alignment metric's evaluation set (Req 6.4), so a hungry derivation could
  quietly drive a `(class, capture mode)` cell below the floor and make the
  metric read `insufficient` through its own doing. Candidates that would do
  that are left in the corpus.
* **Provenance on every label.** Which note or correction produced it, which
  model interpreted it, and — since the masks here are the segmenter's own
  argmax — an explicit `self_training` flag. A self-trained mask that did not
  say so would let confirmation bias look like progress.

Launching a training or calibration run stays human-gated (Req 8.6): the
recommended commands are written into the cycle verdict and nothing here runs
them.
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys
import zlib
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    __package__ = "field_loop"

from . import bundle, config, corpus, cycle_file  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]

# The third source in the merged corpus. FoodSeg103 stems are zero-padded ids
# and Food-Recognition's carry `fr22_`; this prefix keeps field stems distinct
# from both, which is what lets one flat split directory hold all three.
FIELD_PREFIX = "fld_"

TRAIN_SPLITS = ("train", "val")
ANCHOR_SPLIT = "heldout"

# One in this many accepted captures goes to val. Deterministic on the sorted
# stem order rather than random: a derivation that shuffled would put the same
# capture in a different split on a re-run, and the split posture recorded in
# splits.json would stop being a description of anything.
VAL_EVERY = 5

CHANNEL_COUNT = 36
SPECIAL_CHANNELS = [33, 34, 35]
FOODSEG_SEED = 20260715

MASK_SOURCE = "model_argmax"

# The canonical calibration handoff (tools/metafood3d/ingest.py `_summary_doc`).
# Field captures are photographs of real meals, not renders, so the render
# config records the capture's own geometry and says plainly that no seating
# rule applied — an authored plane would be a claim about a scene nobody posed.
CALIBRATION_DATASET = "medata_field"
CALIBRATION_LICENCE = "developer's own captures; not redistributable"
SEATING_RULE = "none — real capture, no authored support plane"
# Each bundle records its own ARKit intrinsics; there is no pinned camera.
INTRINSICS_MODEL = "arkit_per_capture"


# ------------------------------------------------------------------ PNG I/O
# Written by hand for the same reason the corpus reader is: this module has to
# stay importable on a bare python3, and a mask is an 8-bit greyscale plane —
# the narrowest possible corner of the format.

def write_grey_png(path: Path, plane: bytes, width: int, height: int) -> None:
    raw = b"".join(b"\x00" + plane[y * width:(y + 1) * width]
                   for y in range(height))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


# ------------------------------------------------------------------ selection

def signal_for(conn, stem: str) -> dict:
    """The notes and corrections that make one capture worth learning from.

    A capture with neither is still corpus (Req 8.1) but carries no label a
    derivation could honestly write, so it stays where it is.
    """
    notes = [dict(r) for r in conn.execute(
        "SELECT id, text, carbs_g, meal_id FROM notes WHERE stem = ? ORDER BY id",
        (stem,))]
    meal_ids = {n["meal_id"] for n in notes if n["meal_id"]}
    outcome_meals = {r[0] for r in conn.execute(
        "SELECT o.meal_id FROM outcomes o JOIN captures c "
        "ON c.timestamp_ms = o.timestamp_ms WHERE c.stem = ? AND o.meal_id IS NOT NULL",
        (stem,))}
    meal_ids |= outcome_meals
    corrections = []
    if meal_ids:
        corrections = [dict(r) for r in conn.execute(
            "SELECT meal_id, predicted_class, class_corrected, rejected, absent, "
            "amount_corrected FROM corrections WHERE meal_id IN (%s) "
            "ORDER BY meal_id, predicted_class" % ", ".join("?" for _ in meal_ids),
            sorted(meal_ids))]
    return {"notes": notes, "corrections": corrections}


def candidates(conn) -> list:
    """Unconsumed captures carrying signal, oldest first."""
    rows = [dict(r) for r in conn.execute(
        "SELECT stem, capture_mode, scale_source, detected_classes, timestamp_ms "
        "FROM captures WHERE training_used = 0 ORDER BY timestamp_ms, stem")]
    out = []
    for row in rows:
        signal = signal_for(conn, row["stem"])
        if not signal["notes"] and not signal["corrections"]:
            continue
        out.append(dict(row, signal=signal))
    return out


def cap_allowance(public_train: int, cap: float) -> int:
    """How many field images may join a train split of `public_train` others.

    The cap is a share OF the merged training set, so the bound is
    f / (p + f) <= cap, not f / p <= cap. Solved for f and floored: at 10 % of
    a 90-image public train the answer is 10, not 9.
    """
    if public_train <= 0 or cap <= 0:
        return 0
    return int(cap * public_train / (1.0 - cap))


def eval_cells(rows) -> dict:
    """(class, capture mode) -> how many EVALUATION captures the cell holds."""
    from . import field_report

    cells = {}
    for row in rows:
        for food in (row["detected_classes"] or "").split(","):
            if not food:
                continue
            key = (food, field_report.capture_mode(row))
            cells[key] = cells.get(key, 0) + 1
    return cells


def selectable(conn, pool: list, settings: dict) -> tuple:
    """Split the candidates into (consumable, blocked-by-the-evaluation-floor).

    Greedy over the corpus order: a capture is consumed only while every cell
    it belongs to would still hold at least `eval_floor_per_cell` evaluation
    captures afterwards. Greedy rather than optimal on purpose — the rule has
    to be explainable in a verdict, and "we took them in order until a cell got
    thin" is.
    """
    floor = config.get(settings, "eval_floor_per_cell")
    evaluation = [dict(r) for r in conn.execute(
        "SELECT detected_classes, capture_mode, scale_source FROM captures "
        "WHERE training_used = 0")]
    cells = eval_cells(evaluation)

    taken, blocked = [], []
    for item in pool:
        keys = [k for k in eval_cells([item])]
        if any(cells.get(key, 0) - 1 < floor for key in keys):
            blocked.append(item)
            continue
        for key in keys:
            cells[key] = cells.get(key, 0) - 1
        taken.append(item)
    return taken, blocked


# ---------------------------------------------------------------- derivation

def _split_for(position: int) -> str:
    return "val" if position % VAL_EVERY == VAL_EVERY - 1 else "train"


def _count_images(directory: Path) -> int:
    return sum(1 for p in directory.iterdir() if p.is_file()) \
        if directory.is_dir() else 0


def _assert_anchor(out: Path) -> dict:
    """The anchor is read, counted, and never written (Req 8.4).

    A field stem found in heldout means an earlier run — or a hand edit — put
    the developer's own kitchen into the exam paper, and no derivation may
    proceed on top of that.
    """
    images = out / ANCHOR_SPLIT / "images"
    leaked = sorted(p.name for p in images.iterdir()
                    if p.name.startswith(FIELD_PREFIX)) if images.is_dir() else []
    if leaked:
        raise SystemExit(
            "field stems are present in the %s split (%s) — the frozen "
            "leak-free anchor is the surface every promotion verdict is "
            "measured on and must contain no field data"
            % (ANCHOR_SPLIT, ", ".join(leaked[:5])))
    return {"split": ANCHOR_SPLIT, "images": _count_images(images),
            "untouched": True}


def provenance_for(item: dict, field_stem: str, split: str, ident: str) -> dict:
    """Where one derived label came from, and what it is not.

    The note text is quarantined (Req 4.7): this file is read by later tooling
    and by whatever model interprets the corpus next, and the developer's words
    — or anything a photograph put into them — are data.
    """
    return {
        "stem": item["stem"],
        "field_stem": field_stem,
        "split": split,
        "capture_mode": item["capture_mode"],
        "notes": [{"id": n["id"], "carbs_g": n["carbs_g"],
                   "text": cycle_file.quarantine(n["text"] or "")}
                  for n in item["signal"]["notes"]],
        "corrections": item["signal"]["corrections"],
        "interpreting_model_ident": ident,
        # Req 8.4: the mask is the segmenter's own argmax, so training on it is
        # self-training and has to say so.
        "self_training": True,
        "mask_source": MASK_SOURCE,
        "labelling": "developer-stated; the weighed surface is benchmark_meals",
    }


def derive(conn, root, out, settings: dict, interpreting_ident: str,
           cycle_dir=None) -> dict:
    """Write the field share of the merged corpus and record what it cost."""
    root, out = Path(root), Path(out)
    anchor = _assert_anchor(out)

    public_train = sum(
        1 for p in (out / "train" / "images").iterdir()
        if p.is_file() and not p.name.startswith(FIELD_PREFIX)) \
        if (out / "train" / "images").is_dir() else 0
    allowance = cap_allowance(public_train,
                              config.get(settings, "field_train_share_cap"))

    pool = candidates(conn)
    consumable, blocked = selectable(conn, pool, settings)

    files = {"train": [], "val": []}
    written = 0
    for position, item in enumerate(consumable):
        split = _split_for(position)
        if split == "train" and len(files["train"]) >= allowance:
            # Over the cap: leave it in the corpus for a later derivation
            # rather than dropping it or forcing it into val.
            break
        path = root / "captures" / ("%s.fixture" % item["stem"])
        if not path.exists():
            continue
        field_stem = FIELD_PREFIX + item["stem"]
        if not _write_pair(path, out / split, field_stem):
            continue
        (out / "provenance").mkdir(parents=True, exist_ok=True)
        (out / "provenance" / ("%s.json" % field_stem)).write_text(
            json.dumps(provenance_for(item, field_stem, split,
                                      interpreting_ident),
                       indent=2, sort_keys=True) + "\n")
        conn.execute("UPDATE captures SET training_used = 1 WHERE stem = ?",
                     (item["stem"],))
        files[split].append(field_stem)
        written += 1
    conn.commit()

    counts = _write_splits(out, files, anchor, settings, public_train)
    summary = {
        "counts": counts,
        "files": files,
        "anchor": anchor,
        "deferred_by_cap": len(pool) - len(blocked) - written,
        "blocked_by_eval_floor": len(blocked),
        "interpreting_model_ident": interpreting_ident,
    }
    commands = recommended_commands(out)
    if cycle_dir is not None:
        record_commands(cycle_dir, commands, summary)
    summary["recommended_commands"] = commands
    return summary


def _write_pair(fixture: Path, split_dir: Path, field_stem: str) -> bool:
    """The capture's own photograph and its argmax, as an image/mask pair.

    Returns False when the bundle carries no usable pair — a refusal recorded
    before segmentation has no argmax, and half a pair is not training data.
    """
    from candidate_probe import first

    raw = fixture.read_bytes()
    image = first(raw, bundle.F_NADIR_IMAGE)
    plane = bundle.argmax_plane(fixture)
    if not image or plane is None:
        return False
    buf, width, height = plane
    (split_dir / "images").mkdir(parents=True, exist_ok=True)
    (split_dir / "images" / ("%s.png" % field_stem)).write_bytes(image)
    write_grey_png(split_dir / "masks" / ("%s.png" % field_stem), buf,
                   width, height)
    return True


def _scan_split(split_dir: Path) -> tuple:
    """Per-channel pixel counts and per-image presence, read from the masks.

    `merge_corpus_foodrec2022.scan_masks` does this with numpy and PIL; the
    same numbers come out of the raw planes, and doing it here keeps the whole
    derivation runnable without the training venv.
    """
    counts = [0] * CHANNEL_COUNT
    presence = []
    masks = split_dir / "masks"
    if not masks.is_dir():
        return counts, presence
    for path in sorted(masks.iterdir()):
        if path.suffix != ".png":
            continue
        plane = _read_grey_png(path)
        if plane is None:
            continue
        seen = set()
        for value in plane:
            if value >= CHANNEL_COUNT:
                raise SystemExit("%s has pixel values >= %d"
                                 % (path, CHANNEL_COUNT))
            counts[value] += 1
            seen.add(value)
        presence.append(frozenset(seen))
    return counts, presence


def _read_grey_png(path: Path):
    """The pixel bytes of an 8-bit greyscale PNG, or None if it is not one."""
    raw = path.read_bytes()
    if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    offset, width, height, idat = 8, 0, 0, bytearray()
    while offset + 8 <= len(raw):
        length = struct.unpack(">I", raw[offset:offset + 4])[0]
        tag = raw[offset + 4:offset + 8]
        body = raw[offset + 8:offset + 8 + length]
        if tag == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            if depth != 8 or colour != 0:
                return None
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        offset += 12 + length
    if not width or not height:
        return None
    data = zlib.decompress(bytes(idat))
    out = bytearray()
    previous = bytearray(width)
    for y in range(height):
        start = y * (width + 1)
        filter_type = data[start]
        row = bytearray(data[start + 1:start + 1 + width])
        if filter_type == 2:  # Up — the only filter zlib picks on flat rows
            for x in range(width):
                row[x] = (row[x] + previous[x]) & 0xFF
        elif filter_type not in (0,):
            return None
        out += row
        previous = row
    return bytes(out)


def _write_splits(out: Path, files: dict, anchor: dict, settings: dict,
                  public_train: int) -> dict:
    """`splits.json` + `co_stats.json`, in the merged-corpus shape."""
    sys.path.insert(0, str(REPO_ROOT / "tools" / "segmenter"))
    from prepare_dataset import build_co_stats

    pixel_counts, train_presence = {}, None
    for split in TRAIN_SPLITS + (ANCHOR_SPLIT,):
        counts, presence = _scan_split(out / split)
        pixel_counts[split] = counts
        if split == "train":
            train_presence = presence

    co_stats = build_co_stats(pixel_counts, train_presence or [], CHANNEL_COUNT,
                              FOODSEG_SEED, "", SPECIAL_CHANNELS)
    (out / "co_stats.json").write_text(json.dumps(co_stats) + "\n")

    total = {split: _count_images(out / split / "images")
             for split in TRAIN_SPLITS}
    cap = config.get(settings, "field_train_share_cap")
    field_train = len(files["train"])
    splits = {
        "sources": {
            "field": {
                "prefix": FIELD_PREFIX,
                "posture": "notes and corrections from real captures; train and "
                           "val only, never the frozen leak-free anchor",
                "mixing_cap": cap,
                "public_train_images": public_train,
                "field_train_images": field_train,
                "field_share_of_train": round(
                    field_train / total["train"], 4) if total["train"] else 0.0,
                "val_posture": "every %dth accepted capture, on sorted stem "
                               "order" % VAL_EVERY,
                "mask_source": MASK_SOURCE,
                "self_training": True,
            },
        },
        "channel_count": CHANNEL_COUNT,
        "counts": dict(total, field_train=field_train,
                       field_val=len(files["val"])),
        "anchor": anchor,
        "files": files,
    }
    (out / "splits.json").write_text(json.dumps(splits) + "\n")
    return splits["counts"]


# ------------------------------------------------------ calibration material
# The calibration side is a set of HarnessCLI inputs, one directory per
# segmenter checkpoint. The loader refuses a fixture whose checkpoint is not
# `--checkpoint-sha256` because β_c is coupled to the segmenter that labelled the
# volume (pipeline design §6.9, §7.3): a β fitted across two checkpoints belongs
# to neither. So the derivation groups rather than asking the loader to accept a
# mixed set, and prints one command pair per group.

# PbMealFixture fields `accuracy` and `calibrate` read the weighed truth from.
F_TRUTH_CLASS_MASS = 17     # map<string, float> ground_truth_class_mass_g
F_TRUTH_TOTAL_CARBS = 18    # float ground_truth_total_carbs_g

# Where a weighed capture's bundle may be, after the canonical captures/. A pull
# keeps its own hardlink, and reports/ survives `make field-discard`; a copy
# found there is used only when its SHA-256 matches the indexed capture.
BUNDLE_FALLBACK_GLOBS = ("pulls/*/captures/%s.fixture", "reports/**/%s.fixture")


def _varint(value: int) -> bytes:
    out = bytearray()
    while True:
        low = value & 0x7F
        value >>= 7
        if value:
            out.append(low | 0x80)
        else:
            out.append(low)
            return bytes(out)


def _key(number: int, wire: int) -> bytes:
    return _varint((number << 3) | wire)


def truth_bytes(class_mass_g: dict, total_carbs_g: float) -> bytes:
    """Fields 17 and 18 of PbMealFixture, ready to append to a bundle.

    A protobuf parser reads a message followed by more of its own fields as the
    merge of both, so appending these gives the bundle its weighed truth
    without decoding the ~200 MB message. A device bundle records neither
    field — proto3 does not write a zero — so nothing is overwritten.
    """
    out = bytearray()
    for name in sorted(class_mass_g):
        encoded = name.encode()
        entry = (_key(1, 2) + _varint(len(encoded)) + encoded
                 + _key(2, 5) + struct.pack("<f", class_mass_g[name]))
        out += _key(F_TRUTH_CLASS_MASS, 2) + _varint(len(entry)) + entry
    out += _key(F_TRUTH_TOTAL_CARBS, 5) + struct.pack("<f", total_carbs_g)
    return bytes(out)


def clone_or_copy(src: Path, dst: Path) -> None:
    """A writable copy of `src` that shares its blocks where the volume can.

    The derived fixture is appended to, so it cannot be a hardlink into the
    corpus. On APFS `clonefile(2)` makes the copy without writing any data —
    the appended truth is the only new block — and anywhere else this falls
    back to a full copy.
    """
    import ctypes
    import shutil

    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    clonefile = getattr(ctypes.CDLL(None), "clonefile", None) \
        if sys.platform == "darwin" else None
    if clonefile is not None:
        clonefile.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32]
        clonefile.restype = ctypes.c_int
        if clonefile(os.fsencode(src), os.fsencode(dst), 0) == 0:
            return
    shutil.copyfile(src, dst)


def find_bundle(root: Path, stem: str, sha256):
    """The capture's bundle: captures/ first, then a verified copy elsewhere."""
    canonical = root / "captures" / ("%s.fixture" % stem)
    if canonical.exists():
        return canonical
    if not sha256:
        return None
    for pattern in BUNDLE_FALLBACK_GLOBS:
        for path in sorted(root.glob(pattern % stem)):
            if corpus.sha256_file(path) == sha256:
                return path
    return None


def truth_for(items_json: str, truth_carbs_g: float) -> dict:
    """The weighed truth in the shape fields 17 and 18 carry.

    Items are recorded under the class the review settled on. The device
    writes `grams`; the 2026-09-29 back-fill wrote `mass_g`.
    """
    class_mass = {}
    for item in json.loads(items_json or "[]"):
        grams = item.get("grams", item.get("mass_g"))
        if item.get("class_id") and grams is not None:
            class_mass[item["class_id"]] = \
                class_mass.get(item["class_id"], 0.0) + float(grams)
    return {"class_mass_g": class_mass, "total_carbs_g": float(truth_carbs_g)}


def review_for(conn, outcome_id: str, meal_id) -> dict:
    """What the review changed on this capture: relabels and removals.

    Amount corrections are left out on purpose: the volume is what is being
    measured, the weighed mass is its truth, and a typed amount is neither.
    """
    rows = conn.execute(
        "SELECT predicted_class, class_corrected, rejected, record_json "
        "FROM corrections WHERE outcome_id = ? "
        "OR (outcome_id IS NULL AND meal_id = ?) ORDER BY predicted_class",
        (outcome_id, meal_id)).fetchall()
    relabelled, rejected = {}, []
    for row in rows:
        if row["rejected"]:
            rejected.append(row["predicted_class"])
            continue
        if not row["class_corrected"]:
            continue
        try:
            corrected = json.loads(row["record_json"] or "{}").get(
                "corrected", {}).get("classId")
        except ValueError:
            corrected = None
        if corrected and corrected != row["predicted_class"]:
            relabelled[row["predicted_class"]] = corrected
    return {"relabelled": relabelled, "rejected": rejected}


def device_cost(measurements_json, model_version) -> dict:
    """The segmenter the phone ran and its prediction time per frame.

    `prediction_ms` holds `nadir`, and `oblique` on a two-view capture; a
    frame the outcome row did not time is left out rather than written 0.
    """
    try:
        measurements = json.loads(measurements_json or "{}")
    except ValueError:
        measurements = {}
    prediction = {}
    for view, key in (("nadir", "segmentationNadir"),
                      ("oblique", "segmentationOblique")):
        ms = (measurements.get(key) or {}).get("predictionMs")
        if ms is not None:
            prediction[view] = ms
    return {"model_version": measurements.get("modelVersion") or model_version,
            "prediction_ms": prediction}


def _clear_previous(out: Path) -> None:
    """Remove the groups an earlier derivation wrote into `out`.

    A capture that is no longer weighed, whose bundle has gone, or whose group
    has changed would otherwise stay behind as a fixture the harness loads.
    Only a group this layout wrote is touched — a field summary naming its
    checkpoint — and a hardlinked fixture is never removed, so pointing `out`
    at a preserved directory such as `reports/calibration-20260929-roll/`
    cannot delete the last copy of a bundle.
    """
    for summary in out.glob("*/run_summary.json"):
        try:
            document = json.loads(summary.read_text())
        except ValueError:
            continue
        if document.get("dataset") != CALIBRATION_DATASET \
                or "checkpoint" not in document:
            continue
        for fixture in summary.parent.glob("*.fixture"):
            if fixture.stat().st_nlink == 1:
                fixture.unlink()
        summary.unlink()


def _summary_document(group: dict) -> dict:
    """One checkpoint group's run_summary.json (`CalibrateRun.loadIngestSummary`)."""
    return {
        "dataset": CALIBRATION_DATASET,
        "licence": CALIBRATION_LICENCE,
        "source_dataset": "medata field corpus",
        "snapshot": "field",
        "mapping_version": "palette-native",
        "mapping_categories_source": "ClassPalette (no mapping applied — field "
                                     "captures are already in the palette's "
                                     "label space)",
        "checkpoint": group["checkpoint"],
        "ingested": len(group["fixtures"]),
        # CaptureBundleRecorder stamps every device bundle single_dominant.
        "estimator_paths": {"single_dominant": len(group["fixtures"])},
        # `{reason: [stems]}`, the shape every ingest summary uses.
        "skipped": {reason: sorted(stems)
                    for reason, stems in group["skipped"].items()},
        # No plane_depth_mm: nothing was posed, so there is no authored plane.
        "render_config": {
            "intrinsics_model": INTRINSICS_MODEL,
            "image_width": group["width"],
            "image_height": group["height"],
            "seating_rule": SEATING_RULE,
        },
        "truth_source": "benchmark_meals, weighed (SNAQ Parity); developer-"
                        "stated figures are deliberately not calibration input",
        # Per fixture id: the truth written into the bundle (fields 17/18),
        # the review `accuracy` and `calibrate` apply before scoring, and the
        # segmenter's on-device cost, which `field-score` prints.
        "fixtures": group["fixtures"],
    }


def derive_calibration(conn, root, out) -> dict:
    """Weighed benchmark captures as HarnessCLI inputs, one directory per checkpoint.

    Only weighed benchmarks: calibration is the one place where the corpus has
    real ground truth, and feeding it developer-stated figures would put the
    estimate's own bias into the coefficient meant to correct it.

    Each `<out>/<checkpoint>/` holds the group's bundles with their truth
    written in, and a run_summary.json carrying each fixture's review. The
    corpus bundles are never written.
    """
    root, out = Path(root), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    _clear_previous(out)

    rows = [dict(r) for r in conn.execute(
        "SELECT c.stem, c.sha256, c.model_version, o.id AS outcome_id, "
        "o.meal_id, o.model_version AS outcome_model_version, "
        "o.measurements_json, b.id AS benchmark_meal_id, b.items, "
        "b.truth_carbs_g, b.fidelity FROM outcomes o "
        "JOIN benchmark_meals b ON b.id = o.benchmark_meal_id "
        "JOIN captures c ON c.timestamp_ms = o.timestamp_ms "
        "WHERE o.benchmark_meal_id IS NOT NULL ORDER BY c.stem")]

    groups = {}

    def group_for(checkpoint: str) -> dict:
        return groups.setdefault(checkpoint, {
            "checkpoint": checkpoint, "fixtures": {}, "width": 0, "height": 0,
            "skipped": {"not_weighed": [], "bundle_missing": []}})

    for row in rows:
        indexed = row["model_version"] or "unstamped"
        if row["fidelity"] != "weighed":
            group_for(indexed)["skipped"]["not_weighed"].append(row["stem"])
            continue
        source = find_bundle(root, row["stem"], row["sha256"])
        if source is None:
            group_for(indexed)["skipped"]["bundle_missing"].append(row["stem"])
            continue
        info = bundle.read_summary(source)
        # The bundle's own stamp, not the index's: it is what the loader
        # compares against `--checkpoint-sha256`.
        group = group_for(info["model_version"] or indexed)
        truth = truth_for(row["items"], row["truth_carbs_g"])
        target = out / group["checkpoint"] / source.name
        clone_or_copy(source, target)
        with open(target, "ab") as handle:
            handle.write(truth_bytes(truth["class_mass_g"],
                                     truth["total_carbs_g"]))
        group["fixtures"][info["fixture_id"] or row["stem"]] = {
            "stem": row["stem"],
            "source": str(source.relative_to(root)),
            "outcome_id": row["outcome_id"],
            "benchmark_meal_id": row["benchmark_meal_id"],
            "truth": truth,
            "review": review_for(conn, row["outcome_id"], row["meal_id"]),
            **device_cost(row["measurements_json"],
                          row["outcome_model_version"]),
        }
        group["width"] = info["width"] or group["width"]
        group["height"] = info["height"] or group["height"]

    for checkpoint, group in sorted(groups.items()):
        directory = out / checkpoint
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "run_summary.json").write_text(
            json.dumps(_summary_document(group), indent=2, sort_keys=True) + "\n")

    skipped = {}
    for group in groups.values():
        for reason, stems in group["skipped"].items():
            skipped.setdefault(reason, []).extend(stems)
    return {
        "out": str(out),
        "ingested": sum(len(g["fixtures"]) for g in groups.values()),
        "skipped": {reason: sorted(stems) for reason, stems in skipped.items()},
        "groups": {checkpoint: {
            "dir": str(out / checkpoint),
            "ingested": len(group["fixtures"]),
            "commands": harness_commands(out / checkpoint, checkpoint),
        } for checkpoint, group in sorted(groups.items())},
    }


def harness_commands(directory, checkpoint: str) -> dict:
    """`accuracy` and `calibrate` over one checkpoint group."""
    common = ("--fixtures-dir %s --checkpoint-sha256 %s --ingest-summary "
              "%s/run_summary.json" % (directory, checkpoint, directory))
    return {
        "accuracy": "swift run HarnessCLI accuracy %s --output %s/accuracy.json"
                    % (common, directory),
        "calibrate": "swift run HarnessCLI calibrate %s --output %s/calibrate.json"
                     % (common, directory),
    }


# ----------------------------------------------------- recommended commands

def recommended_commands(out) -> dict:
    """What to run next, recorded and never executed (Req 8.6)."""
    return {
        "retrain": "python tools/segmenter/train.py --data %s" % out,
        "recalibrate": "make field-score, or per checkpoint group: swift run "
                       "HarnessCLI calibrate --fixtures-dir <calibration "
                       "output>/<checkpoint> --checkpoint-sha256 <checkpoint> "
                       "--ingest-summary <calibration output>/<checkpoint>/"
                       "run_summary.json --output <artifact>",
        "rebake": "make food-db CALIBRATION=<artifact>",
        "human_gated": True,
        "note": "launching a training or calibration run is a human step by "
                "standing convention; the loop prepares inputs only",
    }


def record_commands(cycle_dir, commands: dict, summary: dict) -> Path:
    """Merge into the cycle verdict, or stand beside it when there is none.

    A verdict is the record of a closed cycle; derivation that ran before one
    exists writes its own file rather than fabricating a half-verdict nobody
    could read as the cycle's outcome.
    """
    directory = Path(cycle_dir)
    directory.mkdir(parents=True, exist_ok=True)
    verdict = directory / "verdict.json"
    payload = {"recommended_commands": commands,
               "derivation": {k: v for k, v in summary.items()
                              if k != "recommended_commands"}}
    if verdict.exists():
        document = json.loads(verdict.read_text())
        document.update(payload)
        verdict.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
        return verdict
    path = directory / "derivation.json"
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return path


# ------------------------------------------------------------------ the run

def print_calibration(document: dict) -> None:
    """The derivation, then one directory and command pair per checkpoint."""
    print("derive calibration ingested=%d skipped=%d out=%s"
          % (document["ingested"],
             sum(len(s) for s in document["skipped"].values()),
             document["out"]))
    for reason, stems in sorted(document["skipped"].items()):
        for stem in stems:
            print("derive calibration skipped %s=%s" % (reason, stem))
    for checkpoint, group in sorted(document["groups"].items()):
        print("derive calibration checkpoint=%s ingested=%d dir=%s"
              % (checkpoint, group["ingested"], group["dir"]))
        if group["ingested"]:
            for name, command in sorted(group["commands"].items()):
                print("derive calibration %s=%s" % (name, command))


def run(args) -> int:
    settings = config.load(args.config)
    root = Path(args.corpus) if args.corpus else corpus.corpus_root()
    conn = corpus.open_index(root)

    if args.calibration_out:
        document = derive_calibration(conn, root, Path(args.calibration_out))
        print_calibration(document)

    summary = None
    if args.out:
        summary = derive(conn, root, Path(args.out), settings,
                         interpreting_ident=args.ident,
                         cycle_dir=Path(args.cycle_dir) if args.cycle_dir else None)
        counts = summary["counts"]
        print("derive train=%d val=%d field_train=%d field_val=%d"
              % (counts["train"], counts["val"], counts["field_train"],
                 counts["field_val"]))
        print("derive deferred_by_cap=%d blocked_by_eval_floor=%d"
              % (summary["deferred_by_cap"], summary["blocked_by_eval_floor"]))
        print("derive anchor=%s images=%d untouched=%s"
              % (summary["anchor"]["split"], summary["anchor"]["images"],
                 summary["anchor"]["untouched"]))
        for name, command in sorted(recommended_commands(args.out).items()):
            if isinstance(command, str):
                print("derive recommended %s=%s" % (name, command))
    conn.close()
    return 0 if (summary or args.calibration_out) else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus")
    ap.add_argument("--config")
    ap.add_argument("--out", help="merged corpus root to add the field share to")
    ap.add_argument("--calibration-out",
                    help="directory for weighed .fixture + run_summary.json")
    ap.add_argument("--cycle-dir",
                    help="cycle directory whose verdict records the commands")
    ap.add_argument("--ident", default="unrecorded",
                    help="ident of the model that interpreted the notes")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
