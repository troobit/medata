#!/usr/bin/env python3
"""What a capture bundle says about itself, read without decoding it.

A `.fixture` is a ~390 MB proto. Ingest needs six small fields from it — the
stamp, the capture mode, the classes the segmenter found — and decoding the
whole message to get them would make a day's pull unaffordable. The wire-level
reader is `tools/candidate_probe.py`'s and is IMPORTED, never copied: a second
reader that drifted from the first would make the loop's joins disagree with
the figures they are judged against (design, "Deterministic diagnosis").

Detected classes come straight out of the argmax byte buffer — it is a plane of
uint8 class indices, so the distinct values are `set(buf)`. That keeps this
module, and the ingest path that depends on it, stdlib-only.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from candidate_probe import (            # noqa: E402  (path set above)
    CLASS_NAMES,
    first,
    is_food,
    parse_intrinsics,
)

# PbMealFixture field numbers (MedataCore/Sources/PortableContracts/Schemas/
# MealFixture.proto). The ones this module adds to candidate_probe's set.
F_DATABASE_EDITION = 4
F_CHECKPOINT_SHA256 = 5
# PNG-encoded RGB8, top-left origin — already an image file on the wire, which
# is why the derivation copies it through rather than re-encoding it.
F_NADIR_IMAGE = 6
F_NADIR_PROBS = 9
F_NADIR_ARGMAX = 11
F_NADIR_INTRINSICS = 13
F_CAPTURE_PATH = 19
F_SOURCE_DATASET = 22

# capture_path_canonical values, and the Req 6.6 segmentation key they feed.
LIDAR_PATH = "single_view_lidar"
TWO_VIEW_PATH = "two_view_sfs"


def _text(raw: bytes, number: int) -> str:
    payload = first(raw, number)
    return payload.decode() if isinstance(payload, (bytes, bytearray)) else ""


def read_summary(path: Path) -> dict:
    """The index-shaped facts about one bundle.

    `detected_classes` is empty for a refusal bundle recorded before
    segmentation ran — an absence the cause taxonomy reads as structurally
    absent evidence (Req 4.4), not as "no food".
    """
    raw = Path(path).read_bytes()
    argmax = first(raw, F_NADIR_ARGMAX)
    classes = []
    if argmax:
        classes = sorted(CLASS_NAMES[c] for c in set(argmax) if is_food(c))
    intrinsics = first(raw, F_NADIR_INTRINSICS)
    size = parse_intrinsics(intrinsics) if intrinsics else {"width": 0, "height": 0}
    return {
        "fixture_id": _text(raw, 1),
        "capture_mode": _text(raw, F_CAPTURE_PATH) or "unknown",
        "model_version": _text(raw, F_CHECKPOINT_SHA256),
        "db_edition": _text(raw, F_DATABASE_EDITION),
        "source_dataset": _text(raw, F_SOURCE_DATASET),
        "detected_classes": classes,
        "has_probs": first(raw, F_NADIR_PROBS) is not None,
        "width": size["width"],
        "height": size["height"],
    }


def argmax_plane(path: Path):
    """(bytes, width, height) of the persisted argmax, or None.

    Returned as raw bytes rather than an array so the mask-consistency measure
    can be computed without numpy; the caller indexes it directly.
    """
    raw = Path(path).read_bytes()
    buf = first(raw, F_NADIR_ARGMAX)
    intrinsics = first(raw, F_NADIR_INTRINSICS)
    if not buf or not intrinsics:
        return None
    size = parse_intrinsics(intrinsics)
    if len(buf) != size["width"] * size["height"]:
        return None
    return buf, size["width"], size["height"]
