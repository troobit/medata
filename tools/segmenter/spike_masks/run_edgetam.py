#!/usr/bin/env python3
"""EdgeTAM image-mode promptable segmentation over the anchor, two prompt regimes.

  app         one box + centre point per component of deeplab's food mask
              (out/prompts_app.json) — what the app could produce today
  app_labels  the same, per component of deeplab's argmax LABEL map (class-aware,
              so a plate of touching foods is several prompts, not one blob)
  oracle      one box + centre point per GT region (out/prompts_oracle.json)

A regime may carry a prompt-style suffix: ``app:box`` (box only), ``app:point``
(centre point only), ``app:multi`` (box + point, multimask output, keep the
highest-scoring mask). The default is box + point, single mask.

Per regime, writes the union mask out/edgetam_<regime>/<stem>.png (scoring
space) and out/edgetam_<regime>_prompts.json with, per prompt, the IoU against
its best-overlap GT region, that region's class, and whether the class is in
the top-3 of deeplab's probabilities mean-pooled inside the EdgeTAM mask
(option (i) of the research note: class from deeplab, mask from EdgeTAM).

Usage: run_edgetam.py [regime[:style] ...]   (default: app oracle)   CPU only.
"""

from __future__ import annotations

import sys
import time

import numpy as np
import torch

import scoring as S

HERE = S.OUT.parent
TOPK = 3


def build_predictor():
    sys.path.insert(0, str(HERE / "EdgeTAM"))
    from sam2.build_sam import build_sam2
    from sam2.sam2_image_predictor import SAM2ImagePredictor

    model = build_sam2("configs/edgetam.yaml", str(HERE / "EdgeTAM/checkpoints/edgetam.pt"), device="cpu")
    return SAM2ImagePredictor(model)


def shortlist_hit(probs4: np.ndarray, mask: np.ndarray, cls: int) -> bool:
    pooled = probs4[:, mask[::4, ::4]].mean(1) if mask[::4, ::4].any() else np.zeros(probs4.shape[0])
    pooled[S.BACKGROUND] = -1
    return cls in np.argsort(-pooled)[:TOPK].tolist()


def label_map_prompts() -> dict:
    """One prompt per class-aware component of deeplab's argmax label map."""
    from PIL import Image
    from run_deeplab import prompt_for

    out = {}
    for stem in S.stems():
        labels = np.asarray(Image.open(S.OUT / "deeplab_labels" / f"{stem}.png"))
        out[stem] = [prompt_for(c) for cls in np.unique(labels) if cls != S.BACKGROUND
                     for c in S.components(labels == cls, S.MIN_REGION_PX)]
    S.write_json(out, S.OUT / "prompts_app_labels.json")
    return out


def run(regime: str, predictor) -> None:
    import json

    name, _, style = regime.partition(":")
    prompts = label_map_prompts() if name == "app_labels" else json.loads((S.OUT / f"prompts_{name}.json").read_text())
    tag = regime.replace(":", "_")
    report, t_encode, t_prompt = {}, [], []
    for stem in S.stems():
        img = S.load_image(stem)
        sw, sh = S.score_shape(*img.size)
        scale = img.size[0] / sw  # scoring space -> native
        arr = np.asarray(img)
        t0 = time.perf_counter()
        with torch.inference_mode():
            predictor.set_image(arr)
        t_encode.append(time.perf_counter() - t0)

        gt = S.load_gt_labels(stem)
        regions = S.gt_regions(gt)
        probs4 = np.load(S.OUT / "deeplab_probs" / f"{stem}.npy").astype(np.float32)
        union = np.zeros((sh, sw), dtype=bool)
        rows = []
        for i, p in enumerate(prompts[stem]):
            box = np.array(p["box"], dtype=np.float32) * scale if style != "point" else None
            point = np.array([p["point"]], dtype=np.float32) * scale if style != "box" else None
            t0 = time.perf_counter()
            with torch.inference_mode():
                masks, scores, _ = predictor.predict(point_coords=point, box=box,
                                                     point_labels=None if point is None else np.array([1]),
                                                     multimask_output=style == "multi")
            t_prompt.append(time.perf_counter() - t0)
            best = int(np.argmax(scores))
            mask = S.to_score_space(masks[best] > 0, sw, sh)
            union |= mask
            # oracle prompt i IS region i; app prompts match by best overlap
            if name == "oracle":
                cls, region = regions[i]
            else:
                cls, region = max(regions, key=lambda r: (r[1] & mask).sum(), default=(None, None))
            rows.append({"iou": S.iou(mask, region) if region is not None else 0.0,
                         "cls": cls, "score": float(scores[best]),
                         "hit": shortlist_hit(probs4, mask, cls) if cls is not None else None})
        S.save_mask(union, S.OUT / f"edgetam_{tag}" / f"{stem}.png")
        report[stem] = rows
        print(f"{regime} {stem} encode {t_encode[-1]*1000:.0f} ms, {len(rows)} prompts, "
              f"mean prompt IoU {np.mean([r['iou'] for r in rows]) if rows else float('nan'):.3f}")

    S.write_json({"prompts": report,
                  "timing": {"encode_ms": float(np.mean(t_encode)) * 1000,
                             "prompt_ms": float(np.mean(t_prompt)) * 1000}},
                 S.OUT / f"edgetam_{tag}_prompts.json")
    flat = [r for v in report.values() for r in v]
    print(f"{regime}: {len(flat)} prompts, mean per-prompt IoU {np.mean([r['iou'] for r in flat]):.3f}, "
          f"shortlist hit {np.mean([r['hit'] for r in flat if r['hit'] is not None]):.3f}, "
          f"encode {np.mean(t_encode)*1000:.0f} ms, prompt {np.mean(t_prompt)*1000:.0f} ms")


if __name__ == "__main__":
    torch.set_num_threads(4)
    predictor = build_predictor()
    for regime in sys.argv[1:] or ["app", "oracle"]:
        run(regime, predictor)
