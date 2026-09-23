# Bugfix Report: segmenter-output-stride-ignored

**Date:** 2026-07-23
**Status:** Fixed

## Description of the Issue

Every on-device capture with the real Core ML segmenter (`coreml_24e0b022241a`)
produced garbage segmentation: the result screen showed several food rows, none
matching the meal, and mask overlays appeared sheared. A capture of 2.5
Weetabix in a white bowl produced rows for milk, pork, mashed potato, mixed
vegetables, salad leaves, white rice, lentils and pasta.

**Reproduction steps:**
1. Deploy a Release build with the real Core ML model (`make deploy-release`).
2. Capture any meal (e.g. dry Weetabix in a bowl on a white table).
3. Observe wrong food rows on the result screen; pull the capture bundle from
   `Documents/captures/` and histogram `nadir_argmax` — 87–99 % of the frame is
   `unsupported_liquid` with ~0.2 % background, and the rendered argmax plane
   shows diagonal sheared streaks.

**Impact:** Total loss of segmentation quality on device — every estimate from
the real-model path is meaningless (wrong classes, wrong volumes, wrong carbs).
The bundled model, the export pipeline, and the harness replays are unaffected;
the same photo through the same checkpoint (PyTorch and `.mlpackage` via
coremltools) on the Mac yields a sane 90.7 % background / 9.2 % unknown_food.

## Investigation Summary

- **Symptoms examined:** three full-size field capture bundles
  (2026-07-21/22), all with an 87–99 % `unsupported_liquid` flood and near-zero
  background; the rendered device argmax plane shows content smeared into
  diagonal lines (progressive per-row shift — the "shearing" seen on device).
- **Code inspected:** `CoreMLSegmenter.swift` (inference engine, logit
  unpacking), `PostProcessing.swift` (softmax/crop/resize/argmax),
  `PreProcessing.swift` letterbox contract, `tools/segmenter/export.py`
  (equivalence oracle).
- **Hypotheses tested:**
  - *Model/domain gap* — ruled out: Mac replay of the exact capture photo
    through `checkpoint_letterbox.pt` (SHA prefix `24e0b022241a`, matching the
    bundle stamp) and through the exported `segmenter.mlpackage` both produce
    ~91 % background.
  - *Broken export artefact* — ruled out by the same `.mlpackage` replay.
  - *Corrupt camera input* — ruled out: the RGB photo recorded in the bundle
    is clean.
  - *Stride mismatch in logit unpacking* — confirmed: a standalone Swift probe
    loading `segmenter.mlpackage` shows the output `MLMultiArray` has
    `strides=[9767520, 279072, 544, 1]` for `shape=[1, 35, 513, 513]` (dense
    would be `[9210915, 263169, 513, 1]`) on BOTH `.cpuOnly` and `.all`
    compute units on an M-series Mac.

## Discovered Root Cause

`CoreMLInferenceEngine.unpackLogits` (`MedataCore/Sources/Segmentation/CoreMLSegmenter.swift`)
reads the output `MLMultiArray`'s raw buffer with dense linear indexing
(`c*h*w + y*w + x`), ignoring `MLMultiArray.strides`. Core ML pads output rows
for alignment (513-wide rows come back with a 544-element stride), so every row
read shifts 31 elements further into the buffer — the logit planes shear
diagonally, the per-pixel class vectors are assembled from unrelated spatial
positions, and the argmax degenerates into an `unsupported_liquid` flood with
junk islands.

**Defect type:** Missing stride handling when reading a strided tensor buffer.

**Why it occurred:** The export-time equivalence oracle validates the
`.mlpackage` via coremltools (which honours strides), and all Swift tests drive
the pipeline through `StubInferenceEngine`/`CannedInferenceEngine`, which
return dense Swift arrays. No test ever presented a non-contiguous
`MLMultiArray` to the unpack path, and `MLMultiArray.withUnsafeBytes` exposes
the padded backing buffer without any warning.

**Contributing factors:** The pre-shutter path and Debug builds use the stub
segmenter, so the defect only manifests on Release + real-model captures — the
least-observed configuration until the capture-bundle recorder landed.

## Resolution for the Issue

**Changes made:**
- `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` — `unpackLogits` now
  reads `MLMultiArray.shape`/`.strides` and derives the (class, row, column)
  element strides for both CHW and HWC layouts; `writeLogits` became a single
  strided gather (`y*sH + x*sW + c*sC`) → dense `[H, W, C]`, replacing the
  dense dual-branch copy. A shape/strides count mismatch throws
  `modelInferenceFailed` instead of reading garbage.

**Approach rationale:** Indexing through the array's own strides is the
minimal, layout-agnostic correction — dense arrays are the special case where
the strides happen to be dense, so no behaviour changes for contiguous
outputs (the full suite stays green).

**Alternatives considered:**
- Convert via `MLShapedArray(_:)`, which densifies internally — rejected: an
  extra full-tensor copy per inference on the hot path, and it hides rather
  than documents the stride contract.
- Reformat with vImage/BNNS — rejected: heavier dependency for what is a
  three-line indexing change.

## Verification (end-to-end, Mac)

The captured Weetabix photo, preprocessed with the runtime letterbox contract
and run through the bundled `segmenter.mlpackage` with the stride-aware unpack
(`computeUnits = .all`), reproduces the coremltools reference within FP16
noise: background 90.65 %, unknown_food 9.21 %, coffee 0.14 % (reference:
90.65 % / 9.21 % / 0.14 %). The pre-fix device output for the same scene was
93.2 % unsupported_liquid with 0.19 % background.

## Regression Test

**Test file:** `MedataCore/Tests/SegmentationTests/CoreMLSegmenterTests.swift`
**Test names:** `CoreMLLogitsUnpackStrideTests.testUnpackLogitsHonoursPaddedRowStride_CHW`,
`…_HWC`

**What it verifies:** `unpackLogits` returns the correct dense HWC logits when
the input `MLMultiArray` has row-padded strides (NaN sentinels fill the
padding, so a dense read cannot pass by accident). Covers both CHW and HWC
output layouts.

**Run command:** `swift test --filter CoreMLLogitsUnpackStrideTests`

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` | `unpackLogits` made static internal (test seam) and stride-aware; stale "under investigation" comment resolved |
| `MedataCore/Tests/SegmentationTests/CoreMLSegmenterTests.swift` | Added stride regression tests (red before fix, green after) |

## Verification

**Automated:**
- [x] Regression test passes (`swift test --filter CoreMLLogitsUnpackStrideTests`)
- [x] Full test suite passes (XCTest 502, 3 skipped, 0 failures; swift-testing 151 in 21 suites)
- [x] Linters/validators pass (`make spell` clean)

**Manual verification:**
- Mac end-to-end replay of the field capture through the bundled model with
  the fixed unpack matches the coremltools reference (see above).
- On-device re-capture (2026-07-23, `you`, bundle `1784736336616-success`):
  2 Weetabix on a plate segmented as one coherent `bread_white` region —
  argmax histogram 75.37 % background / 24.63 % bread_white, no liquid flood,
  no shear. The result row read "bread white, ~100 g carbs": the class is the
  palette's closest match (no cereal class exists — a separate palette gap),
  and the carb overestimate is the known uncalibrated β = 1.0 behaviour, not
  this bug.

## Prevention

**Recommendations to avoid similar bugs:**
- Never read `MLMultiArray` backing memory with dense indexing; always index
  via `strides` (or use `MLShapedArray`, which copies to a dense layout).
- When an inference integration is validated only through a Python-side
  oracle, add at least one Swift-side test with a deliberately non-contiguous
  tensor.

## Related

- Field capture bundles: `1784684140604-success` (Weetabix), `1784596899795-refused`,
  `1784684499134-refused` (all checkpoint `24e0b022241a`).
- `docs/agent-notes/device-build-and-test.md` (Release-only capture testing),
  `docs/agent-notes/estimation-diagnostics.md` (capture-bundle recorder).
