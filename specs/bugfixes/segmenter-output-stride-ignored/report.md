# Bugfix Report: segmenter-output-stride-ignored

**Date:** 2026-07-23
**Status:** In progress

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

_To be completed after the fix._

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
| `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` | `unpackLogits` made static internal (test seam); stride-aware fix to follow |
| `MedataCore/Tests/SegmentationTests/CoreMLSegmenterTests.swift` | Added failing stride regression tests |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Pending: re-deploy Release to the `you` iPhone and re-capture the Weetabix
  bowl; expect the mask overlay to trace the food and the argmax histogram of
  the new capture bundle to be predominantly background.

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
