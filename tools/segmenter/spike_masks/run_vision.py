#!/usr/bin/env python3
"""Apple Vision foreground baseline: write EXIF-upright anchor images in scoring
space to out/vision_input/, compile and run vision_foreground.swift over them,
masks land in out/vision/ and timings in out/vision_timing.json."""

from __future__ import annotations

import json
import subprocess

import scoring as S

HERE = S.OUT.parent
IN, BIN = S.OUT / "vision_input", S.OUT / "vision_foreground"

IN.mkdir(parents=True, exist_ok=True)
for stem in S.stems():
    img = S.load_image(stem)
    img.resize(S.score_shape(*img.size)).save(IN / f"{stem}.png")

subprocess.run(["swiftc", "-O", str(HERE / "vision_foreground.swift"), "-o", str(BIN)], check=True)
result = subprocess.run([str(BIN), str(IN), str(S.OUT / "vision")], check=True, capture_output=True, text=True)
timing = json.loads(result.stdout)
S.write_json(timing, S.OUT / "vision_timing.json")
print(f"{len(timing)} images, mean {sum(timing.values()) / len(timing) * 1000:.0f} ms/image")
