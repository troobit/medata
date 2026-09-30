#!/usr/bin/env python3
"""Held-out validation run (model-production stage 9): per-class IoU → lineage.

Runs a trained checkpoint over a remapped split (default ``heldout``), computes
per-class IoU by palette name, and records the metrics + export-eligibility
decision into ``build/lineage.json`` via ``validation.update_lineage_file``.

A second pass over the same split records the class-agnostic mask-quality
numbers (MD-29, segmenter-foundation Decision 37; ``mask_quality.py``) under
``metrics.mask_quality`` — food IoU, region IoU, boundary F at 2 px, top-3
shortlist hit. Record only: no gate reads them yet. ``--mask-quality-only``
re-scores an existing checkpoint into its lineage file without touching the
class metrics (for re-validating old runs).

Exit codes: 0 when the strict gate passes (or a below-gate release was
explicitly allowed), 1 when it fails without an override.

Developer-phase release override (Decision 11): ``--allow-below-gate --reason
"..."`` records an attributable override in lineage so a below-gate model can
ship for normal-use testing while the model improves. ``export_eligible``
stays truthful either way.

Usage::

    python tools/segmenter/run_validation.py \\
        --checkpoint tools/segmenter/build/checkpoint.pt \\
        --data data/foodseg103_remapped_v2 --split heldout
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
    mapping_path = Path(__file__).resolve().with_name("class_mapping_foodseg103.json")
    mapping = json.loads(mapping_path.read_text())
    channels = sorted(mapping["target_channels"], key=lambda c: c["index"])
    return [c["name"] for c in channels]


def per_class_iou_by_name(model, loader, device, names: list[str],
                          forward_logits=None) -> dict[str, float]:
    """IoU per palette class over a split, keyed by name. Classes with no GT and
    no prediction are OMITTED (validation.shortfall treats an absent staple as
    unprovable, which is the intended semantics). ``forward_logits`` is the arch
    registry's output normaliser (default: torchvision ``["out"]``)."""
    import torch

    if forward_logits is None:
        forward_logits = _load_sibling("archs").dict_out_logits
    num_classes = len(names)
    inter = torch.zeros(num_classes, dtype=torch.float64)
    union = torch.zeros(num_classes, dtype=torch.float64)

    model.eval()
    with torch.no_grad():
        for images, masks in loader:
            images = images.to(device)
            masks = masks.to(device)
            preds = forward_logits(model, images).argmax(dim=1)
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


def _content_shapes(dataset, target_size: int) -> list[tuple[int, int]]:
    """(sw, sh) of each sample's content inside the letterbox, in loader order,
    so the mask metrics score the image and not the background padding. The
    mask file's size is the EXIF-rotated image's size (train.py docstring)."""
    from PIL import Image

    shapes = []
    for _, mask_path in dataset.pairs:
        with Image.open(mask_path) as m:
            shapes.append(mask_quality_module().content_shape(*m.size, target_size))
    return shapes


def mask_quality_module():
    return _load_sibling("mask_quality")


def mask_quality_over_loader(model, loader, device, content_shapes, non_food,
                             forward_logits=None) -> list[dict]:
    """Per-image ``mask_quality.score_image`` over a split: softmax on the device,
    cropped to each sample's content, scored in numpy on the CPU."""
    import torch

    mq = mask_quality_module()
    if forward_logits is None:
        forward_logits = _load_sibling("archs").dict_out_logits
    per_image = []
    i = 0
    model.eval()
    with torch.no_grad():
        for images, masks in loader:
            probs = torch.softmax(forward_logits(model, images.to(device)), dim=1).cpu().numpy()
            gts = masks.numpy()
            for b in range(probs.shape[0]):
                sw, sh = content_shapes[i]
                i += 1
                p = probs[b, :, :sh, :sw]
                gt = gts[b, :sh, :sw].astype("uint8")
                per_image.append(mq.score_image(gt, p.argmax(0).astype("uint8"), p, non_food))
    return per_image


def _print_mask_quality(block: dict) -> None:
    def fmt(v):
        return "absent" if v is None else f"{v:.4f}"
    print(f"[validate] mask food IoU = {fmt(block['food_iou'])}")
    print(f"[validate] mask region IoU = {fmt(block['region_iou'])}")
    print(f"[validate] mask boundary F@2px = {fmt(block['boundary_f2'])}")
    print(f"[validate] mask top-3 shortlist hit = {fmt(block['shortlist_top3_hit'])} "
          f"({block['n_regions']} regions, {block['n_images']} images)")


def resolve_target_size(explicit: int | None, lineage_doc: dict | None) -> int:
    """Evaluation input size: ``--target-size`` when given, else the size the
    checkpoint TRAINED at, else the historical 513.

    Scoring a checkpoint at a size it did not train at silently degrades every
    metric — R16 (trained at 641) read 0.0132 lower on mask food IoU and 0.0330
    lower on region IoU when scored at 513 than at its own size, a bigger swing
    than any recipe lever in the R8–R16 series. So the size is resolved from
    lineage for the same reason the arch already is.
    """
    if explicit is not None:
        return explicit
    recorded = (lineage_doc or {}).get("train_config", {}).get("target_size")
    return recorded or 513


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--checkpoint", default="tools/segmenter/build/checkpoint.pt")
    parser.add_argument("--data", default="data/foodseg103_remapped_v2")
    parser.add_argument("--split", default="heldout",
                        help="Split directory under --data to evaluate (default heldout).")
    parser.add_argument("--lineage", default="tools/segmenter/build/lineage.json")
    parser.add_argument("--target-size", type=int, default=None,
                        help="Evaluation input size. Default: the size the "
                             "checkpoint TRAINED at, read from the lineage's "
                             "train_config.target_size (513 when absent).")
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
    parser.add_argument("--mask-quality-only", action="store_true",
                        help="Re-score only metrics.mask_quality into --lineage; "
                             "class metrics and the gate verdict are left as recorded.")
    args = parser.parse_args(argv)

    if args.allow_below_gate and not (args.reason and args.reason.strip()):
        parser.error("--allow-below-gate requires --reason")

    train = _load_sibling("train")
    export = _load_sibling("export")
    validation = _load_sibling("validation")
    archs = _load_sibling("archs")

    # Arch resolved from lineage (snaq-parity Decision 14) so a bake-off winner
    # is judged under the same registry entry it trained with; a pre-registry
    # lineage (or none yet) means the historical deeplab_mnv3.
    arch = archs.DEFAULT_ARCH
    lineage_doc = None
    lineage_path = Path(args.lineage)
    if lineage_path.is_file():
        lineage_doc = json.loads(lineage_path.read_text())
        arch = archs.arch_from_lineage(lineage_doc)
    args.target_size = resolve_target_size(args.target_size, lineage_doc)
    # export.py resolves the arch from the checkpoint's own stamp; a stale
    # lineage beside a non-default-arch checkpoint would build the wrong model
    # and (strict=False) silently load NOTHING — fail fast when they disagree.
    stamped = archs.checkpoint_arch_stamp(args.checkpoint)
    if stamped is not None and stamped != arch:
        raise SystemExit(
            f"[validate] arch mismatch: lineage resolves {arch!r} but the "
            f"checkpoint stamps {stamped!r} — stale {args.lineage}; re-export "
            "the checkpoint (export.py emit_lineage) or pass the matching "
            "--lineage"
        )
    arch_spec = archs.get(arch)
    print(f"[validate] arch = {arch}")
    print(f"[validate] target size = {args.target_size}")

    names = _channel_names()
    # The model is built at the palette's channel count regardless of --data, and
    # every class index in a mismatched corpus is still a legal index — so without
    # this the run scores happily and reports a wrong number (bugfix
    # anchor-label-space-mismatch). Checked beside the arch fail-fast above for
    # the same reason: silent wrongness beats loudly nothing.
    validation.assert_label_space(args.data, len(names))
    model = export.load_checkpoint(len(names), args.checkpoint, arch=arch)
    device = train._resolve_device(args.device)
    model.to(device)
    print(f"[validate] device = {device}")

    dataset = train.FoodSegDataset(Path(args.data) / args.split, args.target_size,
                                   limit=args.limit)
    loader = train._make_loader(dataset, args.batch_size, False, args.num_workers)
    print(f"[validate] {args.split} samples = {len(dataset)}")

    if not args.mask_quality_only:
        iou = per_class_iou_by_name(model, loader, device, names,
                                    forward_logits=arch_spec.forward_logits)
        lineage = validation.update_lineage_file(iou, args.lineage)
        metrics = lineage["metrics"]

        print(f"[validate] mean food-class IoU = {metrics['mean_iou']:.4f} "
              f"(bar {validation.MEAN_IOU_BAR})")
        for name, value in sorted(metrics["carb_priority_iou"].items()):
            print(f"[validate]   staple {name} = {value:.4f} (floor {validation.CARB_PRIORITY_IOU_BAR})")
        for item in metrics["shortfall"]:
            got = "absent" if item["iou"] is None else f"{item['iou']:.4f}"
            print(f"[validate] SHORT: {item['class']} = {got} < {item['bar']}")

    # Class-agnostic mask quality (MD-29): a second pass, recorded beside the
    # class metrics. Record only — the gate below does not read it.
    per_image = mask_quality_over_loader(
        model, loader, device, _content_shapes(dataset, args.target_size),
        # Background only: unknown_food and unsupported_liquid ARE food for a
        # class-agnostic mask (MD-29 — a wrong class costs the user a tap, a
        # wrong mask costs the volume). This matches the spike's definition
        # (tools/segmenter/spike_masks/RESULTS.md), so its numbers carry over.
        (33,), forward_logits=arch_spec.forward_logits)
    block = mask_quality_module().lineage_block(per_image)
    lineage = validation.update_lineage_mask_quality(block, args.lineage)
    _print_mask_quality(block)

    if args.mask_quality_only:
        print("[validate] mask-quality only: class metrics and gate verdict untouched")
        return 0
    metrics = lineage["metrics"]

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
