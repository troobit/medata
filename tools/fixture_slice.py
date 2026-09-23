#!/usr/bin/env python3
"""Cut a depth-only regression slice out of a full `.fixture` capture bundle.

`specs/estimation/support-plane-reference/` Reqs 6.2, 7.1 and 7.2 name capture
bundles that live on the device, not in the repository. They are ~195 MB each and
almost all of that is the segmentation probability tensor (199 MB of the 204 MB in
`1785135663727-success.fixture`) plus the PNG colour frame. None of it is needed to
select a support plane: the fitter reads the native depth map and a food mask, and
nothing else.

This tool writes the part that IS needed — the 256x192 Float32 depth map, its
confidence bytes, and the food mask reduced onto the same grid — as a ~290 KB
`.depthslice` that can be committed, so Req 6.2 is executable by anyone rather than
only by whoever holds the device.

The mask reduction reproduces `SupportRegion.downsampleFoodMask` exactly: a depth
pixel is food when ANY colour pixel it covers is food, so ambiguity resolves towards
exclusion (Req 2.1). Applying it here rather than in the test is what makes the slice
small; the fitter's own downsample then runs as the identity.

Usage:
    tools/fixture_slice.py <bundle.fixture> <out.depthslice>
"""

import struct
import sys
from pathlib import Path

MAGIC = b"MDSLICE1"

# PbMealFixture field numbers (MedataCore/Sources/PortableContracts/Schemas/MealFixture.proto).
F_FIXTURE_ID = 1
F_PALETTE_VERSION = 3
F_NADIR_DEPTH = 8
F_NADIR_ARGMAX = 11
F_NADIR_INTRINSICS = 13
F_GRAVITY = 16

# Solid-food class count per palette version (ClassPalette.swift). A pixel is food
# when its argmax index is below this — liquids and the three sentinels are not.
# "v2" is the expunged pre-release label (pipeline Decision 50): bundles recorded
# by pre-expunge binaries carry it immutably and describe the SAME 25-solid
# palette. Reading them is not baking — the bake lock still rejects "v2".
FOOD_CLASS_COUNT = {"v0": 25, "v2": 25}


def read_varint(buf, i):
    value = shift = 0
    while True:
        byte = buf[i]
        i += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if not byte & 0x80:
            return value, i


def fields(buf):
    """Yield (field_number, payload) for a proto3 message, payload decoded by wire type."""
    i = 0
    while i < len(buf):
        key, i = read_varint(buf, i)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, i = read_varint(buf, i)
            yield number, value
        elif wire == 1:
            yield number, buf[i:i + 8]
            i += 8
        elif wire == 2:
            length, i = read_varint(buf, i)
            yield number, buf[i:i + length]
            i += length
        elif wire == 5:
            yield number, struct.unpack_from("<f", buf, i)[0]
            i += 4
        else:
            raise ValueError(f"unsupported wire type {wire} for field {number}")


def first(buf, number):
    for n, payload in fields(buf):
        if n == number:
            return payload
    return None


def parse_intrinsics(buf):
    """CameraIntrinsics.proto — fx, fy, cx, cy are floats; the dims are varints."""
    out = {"fx": 0.0, "fy": 0.0, "cx": 0.0, "cy": 0.0, "width": 0, "height": 0}
    keys = {1: "fx", 2: "fy", 3: "cx", 4: "cy", 6: "width", 7: "height"}
    for n, payload in fields(buf):
        if n in keys:
            out[keys[n]] = payload
    return out


def parse_depth(buf):
    """DepthMap.proto — depth bytes, confidence bytes and the grid dims."""
    out = {"depth": b"", "confidence": b"", "width": 0, "height": 0}
    keys = {1: "depth", 2: "confidence", 3: "width", 4: "height"}
    for n, payload in fields(buf):
        if n in keys:
            out[keys[n]] = payload
    return out


def parse_vec3(buf):
    out = [0.0, 0.0, 0.0]
    for n, payload in fields(buf):
        if 1 <= n <= 3:
            out[n - 1] = payload
    return out


def reduce_mask(argmax, colour_w, colour_h, depth_w, depth_h, food_classes):
    """Colour-grid argmax -> depth-grid food mask, resolving towards exclusion.

    Mirrors `SupportRegion.downsampleFoodMask`: depth pixel (dx, dy) covers the
    half-open colour block [dx*sx, (dx+1)*sx) x [dy*sy, (dy+1)*sy), and is food when
    any pixel in it is.
    """
    mask = bytearray(depth_w * depth_h)
    sx = colour_w / depth_w
    sy = colour_h / depth_h
    for dy in range(depth_h):
        y0 = max(0, int(dy * sy))
        y1 = min(colour_h - 1, _ceil((dy + 1) * sy) - 1)
        if y0 > y1:
            continue
        for dx in range(depth_w):
            x0 = max(0, int(dx * sx))
            x1 = min(colour_w - 1, _ceil((dx + 1) * sx) - 1)
            if x0 > x1:
                continue
            found = False
            for y in range(y0, y1 + 1):
                row = y * colour_w
                for x in range(x0, x1 + 1):
                    if argmax[row + x] < food_classes:
                        found = True
                        break
                if found:
                    break
            mask[dy * depth_w + dx] = 1 if found else 0
    return bytes(mask)


def _ceil(value):
    whole = int(value)
    return whole if whole == value else whole + 1


def slice_bundle(bundle_path, out_path):
    raw = Path(bundle_path).read_bytes()
    fixture_id = first(raw, F_FIXTURE_ID).decode()
    palette_version = first(raw, F_PALETTE_VERSION).decode()
    food_classes = FOOD_CLASS_COUNT.get(palette_version)
    if food_classes is None:
        raise SystemExit(f"unknown palette version {palette_version!r}")

    depth_buf = first(raw, F_NADIR_DEPTH)
    if depth_buf is None:
        raise SystemExit(f"{fixture_id}: no nadir depth — not a single-view LiDAR capture")
    depth = parse_depth(depth_buf)
    intrinsics = parse_intrinsics(first(raw, F_NADIR_INTRINSICS))
    gravity = parse_vec3(first(raw, F_GRAVITY))
    argmax = first(raw, F_NADIR_ARGMAX)

    colour_w, colour_h = intrinsics["width"], intrinsics["height"]
    if len(argmax) != colour_w * colour_h:
        raise SystemExit(
            f"{fixture_id}: argmax is {len(argmax)} bytes, expected {colour_w * colour_h}"
        )
    mask = reduce_mask(argmax, colour_w, colour_h,
                       depth["width"], depth["height"], food_classes)

    confidence = depth["confidence"]
    expected = depth["width"] * depth["height"]
    if len(confidence) not in (0, expected):
        raise SystemExit(f"{fixture_id}: confidence is {len(confidence)} bytes, expected {expected}")
    if not confidence:
        # No confidence map (N5k RealSense) — record it as uniformly valid, which is
        # how `SupportRegion.prepare` treats its absence.
        confidence = bytes([255]) * expected

    name = fixture_id.encode()
    out = bytearray()
    out += MAGIC
    out += struct.pack("<i", len(name))
    out += name
    out += struct.pack("<iiii", depth["width"], depth["height"], colour_w, colour_h)
    out += struct.pack("<ffff", intrinsics["fx"], intrinsics["fy"],
                       intrinsics["cx"], intrinsics["cy"])
    out += struct.pack("<fff", *gravity)
    out += depth["depth"]
    out += confidence
    out += mask
    Path(out_path).write_bytes(bytes(out))

    food = sum(mask)
    print(f"{fixture_id}: {depth['width']}x{depth['height']} depth, "
          f"{food} food samples of {expected}, {len(out)} bytes")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    slice_bundle(sys.argv[1], sys.argv[2])
