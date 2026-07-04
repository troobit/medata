#!/usr/bin/env python3
"""Held-out validation run (model-production stage 9): per-class IoU → lineage.

Runs a trained checkpoint over a remapped split (default ``heldout``), computes
per-class IoU by palette name, and records the metrics + export-eligibility
decision into ``build/lineage.json`` via ``validation.update_lineage_file``.

Exit codes: 0 when the strict gate passes (or a below-gate release was
explicitly allowed), 1 when it fails without an override.

Developer-phase release override (Decision 11): ``--allow-below-gate --reason
"..."`` records an attributable override in lineage so a below-gate model can
ship for normal-use testing while the model improves. ``export_eligible``
stays truthful either way.

Usage::

    python tools/segmenter/run_validation.py \\
        --checkpoint tools/segmenter/build/checkpoint.pt \\
        --data data/foodseg103_remapped --split heldout
"""

from __future__ import annotations

import argparse
import importlib
import json
import sys
from pathlib import Path


_TOOLS_DIR = str(Path(__file__).resolve().parent)


def _load_sibling(name: str):
    """Import a sibling module via sys.path (the conftest.py pattern), NOT
    spec_from_file_location: spawn-based DataLoader workers re-import
    FoodSegDataset's module by its ``__module__`` name, so the name must be
    importable in a fresh interpreter (sys.path is inherited by workers)."""
    if _TOOLS_DIR not in sys.path:
        sys.path.insert(0, _TOOLS_DIR)
    return importlib.import_module(name)


def _channel_names() -> list[str]:
    """Palette names in channel-index order from the committed class mapping."""
    mapping_path = Path(__file__).resolve().with_name("class_mapping_foodseg103_v1.json")
    mapping = json.loads(mapping_path.read_text())
    channels = sorted(mapping["target_channels"], key=lambda c: c["index"])
    return [c["name"] for c in channels]


def per_class_iou_by_name(model, loader, device, names: list[str]) -> dict[str, float]:
    """IoU per palette class over a split, keyed by name. Classes with no GT and
    no prediction are OMITTED (validation.shortfall treats an absent staple as
    unprovable, which is the intended semantics)."""
    import torch

    num_classes = len(names)
    inter = torch.zeros(num_classes, dtype=torch.float64)
    union = torch.zeros(num_classes, dtype=torch.float64)

    model.eval()
    with torch.no_grad():
        for images, masks in loader:
            images = images.to(device)
            masks = masks.to(device)
            preds = model(images)["out"].argmax(dim=1)
            for cls in range(num_classes):
                pred_c = preds == cls
                gt_c = masks == cls
                inter[cls] += (pred_c & gt_c).sum().item()
                union[cls] += (pred_c | gt_c).sum().item()

    return {
        names[cls]: (inter[cls] / union[cls]).item()
        for cls in range(num_classes)
        if union[cls] > 0
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", default="tools/segmenter/build/checkpoint.pt")
    parser.add_argument("--data", default="data/foodseg103_remapped")
    parser.add_argument("--split", default="heldout",
                        help="Split directory under --data to evaluate (default heldout).")
    parser.add_argument("--lineage", default="tools/segmenter/build/lineage.json")
    parser.add_argument("--target-size", type=int, default=513)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--limit", type=int, default=None,
                        help="Cap evaluated samples for smoke runs.")
    parser.add_argument("--allow-below-gate", action="store_true",
                        help="Record a developer-phase release override when the "
                             "strict gate fails (requires --reason).")
    parser.add_argument("--reason", default=None,
                        help="Attributable reason for --allow-below-gate.")
    args = parser.parse_args(argv)

    if args.allow_below_gate and not (args.reason and args.reason.strip()):
        parser.error("--allow-below-gate requires --reason")

    train = _load_sibling("train")
    export = _load_sibling("export")
    validation = _load_sibling("validation")

    names = _channel_names()
    model = export.load_checkpoint(len(names), args.checkpoint)
    device = train._resolve_device(args.device)
    model.to(device)
    print(f"[validate] device = {device}")

    dataset = train.FoodSegDataset(Path(args.data) / args.split, args.target_size,
                                   limit=args.limit)
    loader = train._make_loader(dataset, args.batch_size, False, args.num_workers)
    print(f"[validate] {args.split} samples = {len(dataset)}")

    iou = per_class_iou_by_name(model, loader, device, names)
    lineage = validation.update_lineage_file(iou, args.lineage)
    metrics = lineage["metrics"]

    print(f"[validate] mean food-class IoU = {metrics['mean_iou']:.4f} "
          f"(bar {validation.MEAN_IOU_BAR})")
    for name, value in sorted(metrics["carb_priority_iou"].items()):
        print(f"[validate]   staple {name} = {value:.4f} (floor {validation.CARB_PRIORITY_IOU_BAR})")
    for item in metrics["shortfall"]:
        got = "absent" if item["iou"] is None else f"{item['iou']:.4f}"
        print(f"[validate] SHORT: {item['class']} = {got} < {item['bar']}")

    if metrics["export_eligible"]:
        print("[validate] export-eligible: strict gate PASSED")
        return 0

    if args.allow_below_gate:
        validation.record_release_override(lineage, args.reason)
        Path(args.lineage).write_text(json.dumps(lineage, indent=2, sort_keys=True) + "\n")
        print(f"[validate] strict gate FAILED — release override recorded: {args.reason.strip()}")
        return 0

    print("[validate] strict gate FAILED — not export-eligible "
          "(pass --allow-below-gate --reason '...' for a developer-phase release)",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
