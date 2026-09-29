#!/usr/bin/env python3
"""Baseline: the deeplab_mnv3 checkpoint of record over the 182-image anchor.

Writes, per image (all in scoring space, see scoring.py):
  out/deeplab/<stem>.png         binary food mask (argmax != background)
  out/deeplab_labels/<stem>.png  argmax label map
  out/deeplab_probs/<stem>.npy   softmax probabilities, uint8, stride-4 subsample
and once:
  out/prompts_app.json     one box + centre point per component of the food mask
  out/prompts_oracle.json  one box + centre point per GT region
  out/deeplab_shortlist.json  per-GT-region top-3 hit under mean-probability pooling
  out/deeplab_timing.json

Preprocessing is train.py's val path (EXIF transpose, letterbox to 513 top-left,
ImageNet normalisation) re-implemented here so this spike imports nothing a
live training run reads from disk except the torch-free archs.py registry.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from scipy import ndimage

import scoring as S

SEGMENTER = S.REPO / "tools/segmenter"
CHECKPOINT = SEGMENTER / "build/checkpoint_r3_combined_noweight.pt"
MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
TOPK = 3


def load_model():
    sys.path.insert(0, str(SEGMENTER))
    import archs  # torch-free at import; builds the shipping deeplab_mnv3

    names = json.loads((SEGMENTER / "class_mapping_foodseg103.json").read_text())["target_channels"]
    return archs.get("deeplab_mnv3").load_checkpoint(len(names), CHECKPOINT), [c["name"] for c in sorted(names, key=lambda c: c["index"])]


def letterbox(img: Image.Image) -> tuple[torch.Tensor, int, int]:
    sw, sh = S.score_shape(*img.size)
    canvas = Image.new("RGB", (S.SCORE_SIZE, S.SCORE_SIZE), (0, 0, 0))
    canvas.paste(img.resize((sw, sh), Image.BILINEAR), (0, 0))
    arr = (np.asarray(canvas, dtype=np.float32) / 255.0 - MEAN) / STD
    return torch.from_numpy(arr.transpose(2, 0, 1)[None]), sw, sh


def prompt_for(region: np.ndarray) -> dict:
    """Box + a centre point guaranteed inside the region (distance-transform peak)."""
    ys, xs = np.nonzero(region)
    dist = ndimage.distance_transform_edt(region)
    py, px = np.unravel_index(int(dist.argmax()), dist.shape)
    return {"box": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
            "point": [int(px), int(py)], "area": int(region.sum())}


def main() -> None:
    torch.set_num_threads(4)
    model, names = load_model()
    prompts_app, prompts_oracle, shortlist, timing = {}, {}, {}, {}
    for stem in S.stems():
        img = S.load_image(stem)
        x, sw, sh = letterbox(img)
        t0 = time.perf_counter()
        with torch.inference_mode():
            probs = torch.softmax(model(x)["out"][0], dim=0).numpy()
        timing[stem] = time.perf_counter() - t0
        probs = probs[:, :sh, :sw]
        labels = probs.argmax(0).astype(np.uint8)
        food = labels != S.BACKGROUND
        S.save_mask(food, S.OUT / "deeplab" / f"{stem}.png")
        for d in ("deeplab_labels", "deeplab_probs"):
            (S.OUT / d).mkdir(parents=True, exist_ok=True)
        Image.fromarray(labels).save(S.OUT / "deeplab_labels" / f"{stem}.png")
        np.save(S.OUT / "deeplab_probs" / f"{stem}.npy", (probs[:, ::4, ::4] * 255).round().astype(np.uint8))

        prompts_app[stem] = [prompt_for(c) for c in S.components(food, S.MIN_REGION_PX)]
        gt = S.load_gt_labels(stem)
        regions = S.gt_regions(gt)
        prompts_oracle[stem] = [dict(prompt_for(r), cls=cls) for cls, r in regions]
        hits = []
        for cls, r in regions:
            pooled = probs[:, r].mean(1)
            pooled[S.BACKGROUND] = -1
            top = np.argsort(-pooled)[:TOPK].tolist()
            hits.append({"cls": cls, "top": top, "hit": cls in top})
        shortlist[stem] = hits
        print(f"{stem} {timing[stem]*1000:.0f} ms  food_px={int(food.sum())} prompts={len(prompts_app[stem])} regions={len(regions)}")

    S.write_json(prompts_app, S.OUT / "prompts_app.json")
    S.write_json(prompts_oracle, S.OUT / "prompts_oracle.json")
    S.write_json(shortlist, S.OUT / "deeplab_shortlist.json")
    S.write_json(timing, S.OUT / "deeplab_timing.json")
    flat = [h for v in shortlist.values() for h in v]
    print(f"top-{TOPK} shortlist hit rate over {len(flat)} GT regions: {np.mean([h['hit'] for h in flat]):.3f}")
    print(f"mean forward {np.mean(list(timing.values()))*1000:.0f} ms/image (CPU, 4 threads)")


if __name__ == "__main__":
    main()
