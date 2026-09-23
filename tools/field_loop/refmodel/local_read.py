#!/usr/bin/env python3
"""Read one image with the repo's own segmenter and print the response contract.

The `local_torch` adapter's other half. It runs in the SEGMENTER VENV, not in
the loop's interpreter — torch, numpy and PIL are its dependencies, and the
rest of `tools/field_loop/` stays runnable on a bare python3 (the same split
`make food-db`'s `PYTHON=` escape hatch exists for).

Its stdout is the same JSON document the VLM adapters ask their models for, so
`adapters.py` parses one shape rather than four:

    {"foods": [{"name": "white_rice", "confidence": 0.41,
                "region": {"kind": "mask", "png": "…", "pixels": 12043}}],
     "recovered_text": ""}

`confidence` is the class's share of food pixels in the argmax, not a softmax
probability: this adapter answers "what is in this image and where", and an
area share is the honest local answer to "how sure". `recovered_text` is always
empty — the segmenter reads no text, and claiming otherwise would put an empty
string where a real absence belongs.

Inference reuses `tools/segmenter/export.py` (`load_checkpoint`,
`build_reference_chw`, `run_pytorch`) rather than re-implementing preprocessing:
a second preprocessing path would make the reference reading disagree with the
pipeline it is supposed to be a reference for.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "tools" / "segmenter"))
sys.path.insert(0, str(REPO_ROOT / "tools"))


def read(image_path: Path, checkpoint: str, target_size: int, mask_dir) -> dict:
    import numpy as np
    import export  # tools/segmenter/export.py

    from candidate_probe import CLASS_NAMES, is_food

    names = export.palette_channel_names()
    model = export.load_checkpoint(len(names), checkpoint)
    chw = export.build_reference_chw(target_size, str(image_path))
    logits = export.run_pytorch(model, chw)
    argmax = np.asarray(logits).squeeze().argmax(axis=0).astype(np.uint8)

    counts = np.bincount(argmax.ravel(), minlength=len(CLASS_NAMES))
    food_pixels = int(sum(int(counts[i]) for i in range(len(counts)) if is_food(i)))

    png = None
    if mask_dir:
        from PIL import Image

        out = Path(mask_dir)
        out.mkdir(parents=True, exist_ok=True)
        png = out / ("%s.argmax.png" % Path(image_path).stem)
        Image.fromarray(argmax).save(png)

    foods = []
    for index in range(len(counts)):
        pixels = int(counts[index])
        if not pixels or not is_food(index):
            continue
        region = {"kind": "mask", "pixels": pixels, "class_index": index}
        if png is not None:
            region["png"] = str(png)
        foods.append({"name": CLASS_NAMES[index],
                      "confidence": round(pixels / food_pixels, 4)
                      if food_pixels else 0.0,
                      "region": region})
    foods.sort(key=lambda f: (-f["confidence"], f["name"]))
    return {"foods": foods, "recovered_text": ""}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--image", required=True)
    ap.add_argument("--checkpoint", default="tools/segmenter/build/checkpoint.pt")
    ap.add_argument("--target-size", type=int, default=513)
    ap.add_argument("--mask-dir", help="write the argmax PNG here (mask axis)")
    args = ap.parse_args(argv)

    document = read(Path(args.image), args.checkpoint, args.target_size,
                    args.mask_dir)
    print(json.dumps(document, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
