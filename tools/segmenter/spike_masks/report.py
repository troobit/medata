#!/usr/bin/env python3
"""Score every method's masks with scoring.py, print the results table
(Markdown), write out/results.json, and render six side-by-side examples
(image | GT | deeplab | EdgeTAM app) — the 3 largest EdgeTAM wins and the 3
largest losses by food IoU — into examples/."""

from __future__ import annotations

import json

import numpy as np
from PIL import Image, ImageDraw

import scoring as S

EXAMPLES = S.OUT.parent / "examples"
METHODS = {  # table label -> mask dir; every out/edgetam_* regime is appended
    "deeplab_mnv3 (argmax != background)": "deeplab",
    "Vision foreground (all instances)": "vision",
}
EDGETAM_LABELS = {
    "app": "app prompts: box + point per deeplab food-mask component",
    "app_box": "app prompts, box only",
    "app_point": "app prompts, centre point only",
    "app_multi": "app prompts, box + point, multimask best-score",
    "app_labels": "app prompts: box + point per deeplab LABEL-MAP component",
    "app_labels_multi": "app label-map prompts, multimask best-score",
    "oracle": "oracle prompts: box + point per GT region",
}
for d in sorted(S.OUT.glob("edgetam_*/")):
    tag = d.name[len("edgetam_"):]
    METHODS[f"EdgeTAM, {EDGETAM_LABELS.get(tag, tag)}"] = d.name


def deeplab_labelmap_regions() -> dict:
    """deeplab per-region IoU with predicted components taken from the argmax
    LABEL map (class-aware) instead of the binary food mask — the components
    the app actually hands to the review screen."""
    per_image = {}
    for stem in S.stems():
        labels = np.asarray(Image.open(S.OUT / "deeplab_labels" / f"{stem}.png"))
        comps = [c for cls in np.unique(labels) if cls != S.BACKGROUND for c in S.components(labels == cls)]
        gt = S.load_gt_labels(stem)
        per_image[stem] = {"region_ious": S.region_ious(None, S.gt_regions(gt), comps)}
    regions = [v for s in per_image.values() for v in s["region_ious"]]
    return {"region_iou": float(np.mean(regions)), "regions": len(regions)}


def prompt_stats(tag: str) -> dict:
    d = json.loads((S.OUT / f"edgetam_{tag}_prompts.json").read_text())
    flat = [r for v in d["prompts"].values() for r in v]
    hits = [r["hit"] for r in flat if r["hit"] is not None]
    return {"prompts": len(flat), "per_prompt_iou": float(np.mean([r["iou"] for r in flat])),
            "shortlist_hit": float(np.mean(hits)), **d["timing"]}


def overlay(img: Image.Image, mask: np.ndarray, caption: str) -> Image.Image:
    base = np.asarray(img, dtype=np.float32)
    tint = base.copy()
    tint[mask] = 0.45 * base[mask] + 0.55 * np.array([40, 220, 60])
    edge = S.boundary(mask)
    tint[edge] = [255, 40, 40]
    panel = Image.fromarray(tint.astype(np.uint8))
    ImageDraw.Draw(panel).text((4, 4), caption, fill=(255, 255, 0))
    return panel


def render_example(stem: str, scores: dict, tag: str) -> None:
    img = S.load_image(stem)
    img = img.resize(S.score_shape(*img.size))
    gt = S.load_gt_labels(stem) != S.BACKGROUND
    panels = [overlay(img, np.zeros_like(gt), stem), overlay(img, gt, "GT food")]
    for label, d in (("deeplab", "deeplab"), ("EdgeTAM app", "edgetam_app")):
        m = S.load_mask(S.OUT / d / f"{stem}.png")
        panels.append(overlay(img, m, f"{label} IoU {scores[d]['per_image'][stem]['food_iou']:.2f}"))
    sheet = Image.new("RGB", (sum(p.width for p in panels) + 3 * 4, panels[0].height), (255, 255, 255))
    x = 0
    for p in panels:
        sheet.paste(p, (x, 0))
        x += p.width + 4
    EXAMPLES.mkdir(exist_ok=True)
    sheet.save(EXAMPLES / f"{tag}_{stem}.png")


def main() -> None:
    scores = {d: S.score_method(S.OUT / d) for d in METHODS.values()}
    results = {label: scores[d]["mean"] for label, d in METHODS.items()}
    results["deeplab_mnv3 (label-map components)"] = deeplab_labelmap_regions()
    prompts = {d[len("edgetam_"):]: prompt_stats(d[len("edgetam_"):]) for d in METHODS.values() if d.startswith("edgetam")}
    dl_short = [h for v in json.loads((S.OUT / "deeplab_shortlist.json").read_text()).values() for h in v]
    timing = {
        "deeplab_ms": float(np.mean(list(json.loads((S.OUT / "deeplab_timing.json").read_text()).values()))) * 1000,
        "vision_ms": float(np.mean(list(json.loads((S.OUT / "vision_timing.json").read_text()).values()))) * 1000,
        "edgetam": {r: {k: prompts[r][k] for k in ("encode_ms", "prompt_ms", "prompts")} for r in prompts},
    }
    shortlist = {"deeplab_gt_regions": {"regions": len(dl_short), "hit": float(np.mean([h["hit"] for h in dl_short]))},
                 **{f"edgetam_{r}_masks": p["shortlist_hit"] for r, p in prompts.items()}}
    S.write_json({"methods": results, "prompts": prompts, "timing": timing, "shortlist": shortlist},
                 S.OUT / "results.json")

    print("| Method | Food IoU | Region IoU (union mask) | Boundary F (2 px) | Per-prompt IoU |")
    print("|---|---|---|---|---|")
    for label, d in METHODS.items():
        m = results[label]
        tag = d[len("edgetam_"):]
        pp = f"{prompts[tag]['per_prompt_iou']:.3f} ({prompts[tag]['prompts']} prompts)" if d.startswith("edgetam") else "—"
        print(f"| {label} | {m['food_iou']:.3f} | {m['region_iou']:.3f} | {m['boundary_f']:.3f} | {pp} |")
    lm = results["deeplab_mnv3 (label-map components)"]
    print(f"| deeplab_mnv3 (label-map components) | — | {lm['region_iou']:.3f} | — | — |")
    print(json.dumps({"timing": timing, "shortlist": shortlist}, indent=1))

    delta = {s: scores["edgetam_app"]["per_image"][s]["food_iou"] - scores["deeplab"]["per_image"][s]["food_iou"]
             for s in S.stems()}
    ranked = sorted(delta, key=delta.get)
    for stem in ranked[-3:]:
        render_example(stem, scores, f"win_{delta[stem]:+.2f}")
    for stem in ranked[:3]:
        render_example(stem, scores, f"loss_{delta[stem]:+.2f}")
    print("delta food IoU (EdgeTAM app - deeplab): mean %.3f, wins %d, losses %d, |d|<0.01: %d" % (
        np.mean(list(delta.values())), sum(v > 0.01 for v in delta.values()),
        sum(v < -0.01 for v in delta.values()), sum(abs(v) <= 0.01 for v in delta.values())))


if __name__ == "__main__":
    main()
