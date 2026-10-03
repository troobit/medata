#!/usr/bin/env python3
"""Build a larger leak-free held-out anchor from the merged corpus (backlog 35).

The 182-image ``heldout_leakfree`` anchor is the subset of FoodSeg103's re-cut
heldout that was ALSO held out of the pre-July seed-1234 carve, so the old
shipped checkpoints could be read on it. Every run trained on
``merged_foodseg_foodrec2022`` (R1 onward) saw only that corpus's ``train``
split, so for those runs every other image in the corpus is a candidate:

- FoodSeg103 ``heldout`` (854, the 182 included) and ``val`` (711);
- Food Recognition 2022's public validation release (1,000, merged ``val``).

``train.py`` reads ``val`` in eval mode only (no BatchNorm update) and saves the
LAST epoch, never a val-selected one, so ``val`` never reaches the weights. The
anchor relies on that: if the trainer ever selects a checkpoint on val, the
anchor stops being held out.

Stems alone do not prove an image is unseen — FoodSeg103 ships the same photo
under two ids — so every candidate is audited against every train image:

1. exact: SHA-256 of the image bytes;
2. screen: a 64-bit DCT perceptual hash (the ``imagehash.phash``
   construction), EXIF orientation applied, the candidate tried at all eight
   rotations and mirror images; train images within ``--screen-distance`` bits
   go to step 3;
3. judge: the pair is the same photograph when the hash distance is at most
   ``--max-distance`` OR the Pearson correlation of 64x64 greyscale thumbnails,
   at the best of the eight alignments, is at least ``--min-correlation``.

Why two stages: among 45k food photos a hash distance of 6-8 is routinely an
unrelated plate, while a colour-filtered copy of a train photo correlates at
only ~0.85 yet sits 4 bits away. The thresholds were set by inspecting every
pair above 0.80 correlation or within 8 bits (estimation-quality task 14,
2026-10-03 entry).

A candidate that matches train is dropped. Candidates that match each other are
not a leak but are not independent either, so the first stem is kept.

Writes ``<corpus>/<name>/{images,masks}`` as symlinks to the real files (the
corpus is gitignored and lives only in the main checkout) and
``<corpus>/<name>/manifest.json``: per-source and per-class image counts, the
classes with at least ``READABLE_IMAGES`` images, the audit result, the stem
list and a digest. The output directory is replaced, never merged into.

Usage::

    tools/segmenter/.venv/bin/python tools/segmenter/build_anchor.py \\
        --corpus /Users/r/repos/medata/data/merged_foodseg_foodrec2022 \\
        --name heldout_leakfree_v3
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from collections.abc import Callable, Sequence
from datetime import datetime, timezone
from multiprocessing import Pool
from pathlib import Path
from typing import NamedTuple

import numpy as np

CHANNEL_COUNT = 36
FR22_PREFIX = "fr22_"
# A class needs about 20 held-out images before identical runs agree on it to
# within 0.10 (estimation-quality task 14, ANCHOR RESOLUTION 2026-09-29).
READABLE_IMAGES = 20
HASH_SIZE = 8
HASH_THUMB = 32
CORR_THUMB = 64


class Fingerprint(NamedTuple):
    stem: str
    sha256: str
    hashes: list[int]  # phash under the eight alignments; [0] is the identity


def _dct_matrix(n: int) -> np.ndarray:
    """Unnormalised DCT-II basis, so ``M @ x`` is scipy.fftpack.dct(x) up to a
    constant factor — irrelevant, since the hash compares to a median."""
    k = np.arange(n)[:, None]
    i = np.arange(n)[None, :]
    return np.cos(np.pi * k * (2 * i + 1) / (2 * n))


_DCT = _dct_matrix(HASH_THUMB)


def phash(gray: np.ndarray) -> int:
    """64-bit perceptual hash of a HASH_THUMB-square greyscale array: the low
    8x8 of its 2-D DCT, thresholded at its median, bits in row-major order."""
    d = _DCT @ np.asarray(gray, dtype=np.float64) @ _DCT.T
    low = d[:HASH_SIZE, :HASH_SIZE].ravel()
    return int(np.packbits(low > np.median(low)).view(">u8")[0])


def alignments(a: np.ndarray) -> list[np.ndarray]:
    """The eight rotations and mirror images of a square array; [0] is ``a``."""
    return [np.rot90(f, k) for f in (a, a[:, ::-1]) for k in range(4)]


def dihedral_hashes(gray: np.ndarray) -> list[int]:
    return [phash(g) for g in alignments(gray)]


def thumbnail(path: Path, size: int) -> np.ndarray:
    """EXIF-oriented greyscale size x size thumbnail (JPEGs decode at reduced
    scale via ``draft``, which is the whole cost of hashing 48k images)."""
    from PIL import Image, ImageOps

    with Image.open(path) as im:
        im.draft("L", (size * 4, size * 4))
        im = ImageOps.exif_transpose(im)
        return np.asarray(im.convert("L").resize((size, size), Image.LANCZOS),
                          dtype=np.float64)


def aligned_correlation(a: np.ndarray, b: np.ndarray) -> float:
    """Pearson correlation of two equal-size thumbnails at the best of the eight
    alignments of ``a``."""
    bc = b - b.mean()
    best = -1.0
    for g in alignments(a):
        gc = g - g.mean()
        den = np.sqrt((gc * gc).sum() * (bc * bc).sum())
        best = max(best, float((gc * bc).sum() / den) if den else 1.0)
    return best


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _fingerprint(item: tuple[str, str]) -> Fingerprint:
    stem, path = item
    return Fingerprint(stem, sha256_file(Path(path)),
                       dihedral_hashes(thumbnail(Path(path), HASH_THUMB)))


def hamming_to(hashes: np.ndarray, query: Sequence[int]) -> np.ndarray:
    """Minimum Hamming distance from each hash in ``hashes`` (uint64 [N]) to any
    of the ``query`` hashes."""
    q = np.asarray(query, dtype=np.uint64)[:, None]
    return np.bitwise_count(hashes[None, :] ^ q).min(axis=0)


def _match(fp: Fingerprint, others: Sequence[Fingerprint], other_hash: np.ndarray,
           correlate: Callable[[str, str], float], max_distance: int,
           screen_distance: int, min_correlation: float) -> dict | None:
    """The first of ``others`` that is the same photograph as ``fp``, as a record,
    or None. Screened by hash, judged by hash distance or thumbnail correlation."""
    if not len(others):
        return None
    dist = hamming_to(other_hash, fp.hashes)
    best = None
    for j in np.nonzero(dist <= screen_distance)[0]:
        d = int(dist[j])
        corr = correlate(fp.stem, others[j].stem)
        if d <= max_distance or corr >= min_correlation:
            rec = {"match": others[j].stem, "distance": d, "correlation": round(corr, 4)}
            if best is None or (corr, -d) > (best["correlation"], -best["distance"]):
                best = rec
    return best


def audit(cands: Sequence[Fingerprint], train: Sequence[Fingerprint],
          correlate: Callable[[str, str], float], max_distance: int = 4,
          screen_distance: int = 12, min_correlation: float = 0.85,
          ) -> tuple[list[str], list[dict], dict[int, int]]:
    """Admit or drop each candidate, in order. Returns (kept stems, dropped
    records, histogram of each candidate's nearest-train hash distance)."""
    train_hash = np.asarray([t.hashes[0] for t in train], dtype=np.uint64)
    train_sha = {}
    for t in train:
        train_sha.setdefault(t.sha256, t.stem)
    kept: list[Fingerprint] = []
    kept_sha: dict[str, str] = {}
    dropped: list[dict] = []
    histogram: dict[int, int] = {}
    for fp in cands:
        nearest = int(hamming_to(train_hash, fp.hashes).min()) if len(train) else 64
        histogram[nearest] = histogram.get(nearest, 0) + 1
        if fp.sha256 in train_sha:
            dropped.append({"stem": fp.stem, "reason": "exact_train",
                            "match": train_sha[fp.sha256], "distance": 0, "correlation": 1.0})
            continue
        rec = _match(fp, train, train_hash, correlate, max_distance, screen_distance,
                     min_correlation)
        if rec:
            dropped.append({"stem": fp.stem, "reason": "near_duplicate_train", **rec})
            continue
        if fp.sha256 in kept_sha:
            dropped.append({"stem": fp.stem, "reason": "exact_pool",
                            "match": kept_sha[fp.sha256], "distance": 0, "correlation": 1.0})
            continue
        rec = _match(fp, kept, np.asarray([k.hashes[0] for k in kept], dtype=np.uint64),
                     correlate, max_distance, screen_distance, min_correlation)
        if rec:
            dropped.append({"stem": fp.stem, "reason": "near_duplicate_pool", **rec})
            continue
        kept.append(fp)
        kept_sha[fp.sha256] = fp.stem
    return [k.stem for k in kept], dropped, histogram


def class_presence(mask_path: Path) -> list[int]:
    from PIL import Image

    with Image.open(mask_path) as m:
        counts = np.bincount(np.asarray(m).ravel(), minlength=CHANNEL_COUNT)
    if len(counts) > CHANNEL_COUNT:
        raise SystemExit(f"{mask_path} has class ids >= {CHANNEL_COUNT}")
    return [int(c) for c in np.nonzero(counts)[0]]


def _palette_names() -> list[str]:
    mapping = json.loads(
        Path(__file__).resolve().with_name("class_mapping_foodseg103.json").read_text())
    return [c["name"] for c in sorted(mapping["target_channels"], key=lambda c: c["index"])]


def source_of(stem: str, split: str) -> str:
    return f"{'foodrec2022' if stem.startswith(FR22_PREFIX) else 'foodseg103'}_{split}"


def class_counts(presence: dict[str, list[int]], names: Sequence[str]) -> dict[str, int]:
    counts = np.zeros(CHANNEL_COUNT, dtype=int)
    for present in presence.values():
        counts[present] += 1
    return {names[i]: int(counts[i]) for i in range(CHANNEL_COUNT)}


def image_index(split_dir: Path) -> dict[str, Path]:
    """stem -> image path for one split, from a single directory listing (a
    per-stem glob over 45k entries is quadratic)."""
    index: dict[str, Path] = {}
    for p in (split_dir / "images").iterdir():
        if p.stem in index:
            raise SystemExit(f"two images for {p.stem} in {split_dir}")
        index[p.stem] = p
    return index


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--corpus",
                        default="/Users/r/repos/medata/data/merged_foodseg_foodrec2022")
    parser.add_argument("--name", default="heldout_leakfree_v3")
    parser.add_argument("--candidate-splits", nargs="+", default=["heldout", "val"])
    parser.add_argument("--screen-distance", type=int, default=12)
    parser.add_argument("--max-distance", type=int, default=4)
    parser.add_argument("--min-correlation", type=float, default=0.85)
    parser.add_argument("--workers", type=int, default=12)
    args = parser.parse_args(argv)

    corpus = Path(args.corpus)
    splits = json.loads((corpus / "splits.json").read_text())
    if splits.get("channel_count") != CHANNEL_COUNT:
        raise SystemExit(f"{corpus} is not a {CHANNEL_COUNT}-channel corpus")
    files = splits["files"]
    if args.name in files:
        raise SystemExit(f"--name {args.name} is a corpus split; the output dir is replaced")
    train_stems = list(files["train"])
    cand: list[tuple[str, str]] = [(s, sp) for sp in args.candidate_splits for s in files[sp]]
    if {s for s, _ in cand} & set(train_stems):
        raise SystemExit("candidate stems are listed in train")
    split_of = dict(cand)

    index = {sp: image_index(corpus / sp) for sp in ["train", *args.candidate_splits]}
    path_of = {s: index["train"][s].resolve() for s in train_stems}
    path_of.update({s: index[sp][s].resolve() for s, sp in cand})
    print(f"[anchor] fingerprinting {len(train_stems)} train + {len(cand)} candidates …",
          flush=True)
    with Pool(args.workers) as pool:
        train_fp = pool.map(_fingerprint, [(s, str(path_of[s])) for s in train_stems],
                            chunksize=64)
        cand_fp = pool.map(_fingerprint, [(s, str(path_of[s])) for s, _ in cand],
                           chunksize=64)

    thumbs: dict[str, np.ndarray] = {}

    def correlate(a: str, b: str) -> float:
        for s in (a, b):
            if s not in thumbs:
                thumbs[s] = thumbnail(path_of[s], CORR_THUMB)
        return aligned_correlation(thumbs[a], thumbs[b])

    kept, dropped, histogram = audit(cand_fp, train_fp, correlate, args.max_distance,
                                     args.screen_distance, args.min_correlation)
    for rec in dropped:
        print(f"[anchor] drop {rec['stem']} ({rec['reason']}: {rec['match']} "
              f"d={rec['distance']} r={rec['correlation']})")

    out = corpus / args.name
    if out.exists():
        shutil.rmtree(out)
    (out / "images").mkdir(parents=True)
    (out / "masks").mkdir()
    names = _palette_names()
    presence: dict[str, list[int]] = {}
    digest = hashlib.sha256()
    for stem in sorted(kept):
        image = path_of[stem]
        mask = (corpus / split_of[stem] / "masks" / f"{stem}.png").resolve()
        (out / "images" / f"{stem}{image.suffix}").symlink_to(image)
        (out / "masks" / f"{stem}.png").symlink_to(mask)
        presence[stem] = class_presence(mask)
        for p in (image, mask):
            digest.update(f"{stem}{p.suffix}".encode())
            digest.update(p.read_bytes())

    sources: dict[str, dict[str, int]] = {}
    for stem, split in cand:
        sources.setdefault(source_of(stem, split), {"candidates": 0, "kept": 0})["candidates"] += 1
    by_source: dict[str, dict[str, list[int]]] = {}
    for stem in kept:
        src = source_of(stem, split_of[stem])
        sources[src]["kept"] += 1
        by_source.setdefault(src, {})[stem] = presence[stem]
    per_class = class_counts(presence, names)
    readable = [n for n in names if n != "background" and per_class[n] >= READABLE_IMAGES]
    reasons = [r["reason"] for r in dropped]
    manifest = {
        "name": args.name,
        "corpus": str(corpus),
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "candidate_splits": args.candidate_splits,
        "n_images": len(kept),
        "sources": sources,
        "readable_bar_images": READABLE_IMAGES,
        "readable_classes": readable,
        "per_class_images": per_class,
        "per_class_images_by_source": {k: class_counts(v, names)
                                       for k, v in sorted(by_source.items())},
        "leak_audit": {
            "train_images": len(train_stems),
            "candidates": len(cand),
            "stem_overlap": 0,
            "exact_sha256_train": reasons.count("exact_train"),
            "near_duplicate_train": reasons.count("near_duplicate_train"),
            "duplicate_within_pool": reasons.count("exact_pool")
            + reasons.count("near_duplicate_pool"),
            "rule": {"phash_bits": HASH_SIZE * HASH_SIZE,
                     "screen_distance": args.screen_distance,
                     "max_distance": args.max_distance,
                     "min_correlation": args.min_correlation,
                     "correlation_thumbnail": CORR_THUMB,
                     "alignments": "8 rotations/mirrors of the candidate, EXIF applied"},
            "nearest_train_distance_histogram": {str(k): histogram[k]
                                                 for k in sorted(histogram)},
            "dropped": dropped,
        },
        "sha256": digest.hexdigest(),
        "stems": sorted(kept),
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"[anchor] {len(kept)} of {len(cand)} candidates kept -> {out}")
    print(f"[anchor] readable (>= {READABLE_IMAGES} images): {len(readable)} classes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
