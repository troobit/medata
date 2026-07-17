#!/usr/bin/env python3
"""Build-lineage manifest for the segmenter (model-production task 3, Req 1.3).

Records the provenance needed to reproduce a bundled segmenter to *metric* level
(a re-run meets the same mIoU bar), not byte-identity (design §3.3):

  - checkpoint_sha256      SHA-256 of the trained PyTorch checkpoint. The JOIN
                           KEY: its first 12 hex form ``model_version``, which
                           ``export.py`` stamps into the Core ML user metadata
                           (task 7) and ``CoreMLInferenceEngine`` reads back
                           (task 5) so a persisted meal traces to its build.
  - model_version          first 12 hex of ``checkpoint_sha256``.
  - foodseg103_source      dataset source/version (FoodSeg103, Apache 2.0).
  - split_seed             dataset split seed (from ``prepare_dataset.py``).
  - class_mapping_version  schema id of ``class_mapping_foodseg103_v1.json``.
  - palette_version        v1 palette edition (must match ``ClassPalette.version``).
  - train_config           epochs / lr / batch / target_size / num_classes / etc.
  - code_commit            git HEAD at build time.
  - metrics                {mean_iou, per_class_iou, carb_priority_iou} — the
                           validation step (task 9) populates these; null
                           placeholders here.
  - pretrained_checkpoint  {source_url, licence, sha256} of the published
                           checkpoint the run initialised from (segmenter-
                           foundation Req 2.2 / Decision 17); null when the
                           run did not record one.
  - co_stats_sha256        SHA-256 of the co_stats.json the co-occurrence loss
                           consumed (segmenter-foundation design §4.3); null
                           when the loss did not use one.

This manifest is BUILD PROVENANCE: it is written under ``tools/segmenter/build/``
and is NOT shipped inside the app bundle. This module is pure stdlib (no torch),
so it imports and runs without the training dependencies installed.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

# First 12 hex of the checkpoint SHA-256 form the model version (the join key
# read back by CoreMLInferenceEngine.resolveModelVersion — keep both in step).
MODEL_VERSION_HEX_LEN = 12
DEFAULT_LINEAGE_PATH = Path("tools/segmenter/build/lineage.json")
_MAPPING_PATH = Path(__file__).resolve().with_name("class_mapping_foodseg103_v1.json")


def file_sha256(path: str | Path) -> str:
    """Streaming SHA-256 of any file (checkpoints, co_stats.json, mappings)."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def checkpoint_sha256(checkpoint_path: str | Path) -> str:
    """Streaming SHA-256 of the checkpoint file (handles multi-hundred-MB .pt)."""
    return file_sha256(checkpoint_path)


def model_version(sha256_hex: str) -> str:
    """First 12 hex of the checkpoint SHA-256 — the ``modelVersion`` join key."""
    return sha256_hex[:MODEL_VERSION_HEX_LEN]


def code_commit() -> str:
    """git HEAD at build time, or ``"unknown"`` outside a working tree."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
            cwd=Path(__file__).resolve().parent,
        )
        return out.stdout.strip() or "unknown"
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return "unknown"


def _class_mapping_meta() -> dict[str, str]:
    """Read palette/source/schema from the committed class-mapping file."""
    try:
        d = json.loads(_MAPPING_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return {
        "class_mapping_version": str(d.get("schema", "")),
        "palette_version": str(d.get("palette_version", "")),
        "foodseg103_source": str(d.get("source_dataset", "")),
    }


def empty_metrics() -> dict[str, Any]:
    """Metric placeholders; the validation step (task 9) fills these."""
    return {"mean_iou": None, "per_class_iou": None, "carb_priority_iou": None}


def build_lineage(
    checkpoint_path: str | Path,
    *,
    train_config: dict[str, Any],
    split_seed: int | None = None,
    foodseg103_source: str | None = None,
    palette_version: str | None = None,
    class_mapping_version: str | None = None,
    metrics: dict[str, Any] | None = None,
    pretrained_checkpoint: dict[str, Any] | None = None,
    co_stats_sha256: str | None = None,
    co_stats_provenance: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Assemble the lineage manifest for a saved checkpoint.

    Fields not passed explicitly fall back to the committed class-mapping meta,
    then to ``"unknown"``, so the manifest is always complete and self-describing.
    ``pretrained_checkpoint`` is a ``{source_url, licence, sha256}`` object for
    the published initialisation (segmenter-foundation Req 2.2, model-production
    Req 1.3); ``co_stats_sha256`` anchors the co-occurrence statistics the loss
    consumed (design §4.3); ``co_stats_provenance`` is the ``{source,
    ingredient_mapping_sha256, palette_coverage}`` object for EXTERNAL
    (corpus-derived) statistics (snaq-parity Req 6.1). All are null when the
    run did not record them.
    """
    sha = checkpoint_sha256(checkpoint_path)
    meta = _class_mapping_meta()
    return {
        "checkpoint_sha256": sha,
        "model_version": model_version(sha),
        "foodseg103_source": foodseg103_source or meta.get("foodseg103_source") or "unknown",
        "split_seed": split_seed,
        "class_mapping_version":
            class_mapping_version or meta.get("class_mapping_version") or "unknown",
        "palette_version": palette_version or meta.get("palette_version") or "unknown",
        "train_config": train_config,
        "code_commit": code_commit(),
        "metrics": metrics or empty_metrics(),
        "pretrained_checkpoint": pretrained_checkpoint,
        "co_stats_sha256": co_stats_sha256,
        "co_stats_provenance": co_stats_provenance,
    }


def preserve_metrics(
    manifest: dict[str, Any], existing_path: str | Path = DEFAULT_LINEAGE_PATH
) -> dict[str, Any]:
    """Carry recorded metrics forward when re-emitting lineage for the SAME checkpoint.

    ``emit_lineage`` (export.py) rebuilds the manifest with null metrics; without
    this, a re-export would silently wipe a validation result (and any release
    override) already recorded for the identical checkpoint SHA. The training-run
    provenance fields (``pretrained_checkpoint``, ``co_stats_sha256``) are carried
    forward on the same rule — they belong to the checkpoint, and a re-export
    must not null them. Different SHA → the null placeholders stand, as those
    values belong to another model. Mutates and returns ``manifest``.
    """
    path = Path(existing_path)
    if not path.is_file():
        return manifest
    try:
        existing = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return manifest
    if existing.get("checkpoint_sha256") == manifest.get("checkpoint_sha256"):
        recorded = existing.get("metrics")
        if isinstance(recorded, dict):
            manifest["metrics"] = recorded
        for key in ("pretrained_checkpoint", "co_stats_sha256",
                    "co_stats_provenance"):
            if manifest.get(key) is None and existing.get(key) is not None:
                manifest[key] = existing[key]
    return manifest


def write_lineage(lineage: dict[str, Any], out_path: str | Path = DEFAULT_LINEAGE_PATH) -> Path:
    """Write the manifest as pretty JSON, creating the build dir if needed."""
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(lineage, indent=2, sort_keys=True) + "\n")
    return out
