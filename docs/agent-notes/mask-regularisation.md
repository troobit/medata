# Mask regularisation (`regulariseLabelMap`)

`MedataCore/Sources/Segmentation/PostProcessing.swift`. Runs once per view on the
argmax label map, after σ_seg / silhouette / perClassMeanProb are computed from the
raw argmax and before the candidate-evidence pass. It reshapes only the label map;
the probability tensor is untouched.

## Two rules, one scan

Every 4-connected component is discovered in raster order with a LIFO flood fill.
Every reassignment reads the ORIGINAL labels, so results do not depend on the order
components are visited. Ties between bordering classes go to the lowest class id.

1. **Sliver rule** (unknown-food-nameable Req 10, `MaskRegularisationConfig.sliverFraction`).
   One histogram of the original labels before the scan. A class is a sliver when it
   is food-like (`ClassPalette.isVolumetricClass`: solid, liquid, or `unknownFood`)
   and its total count is strictly under `sliverFraction × (food-like total)`. Judged
   per class, not per component — thirty separate pea clumps are one large class and
   survive; a thin `cheese` fringe on a large unknown region is one small class and
   joins whatever it borders. A sliver component is relabelled to its dominant
   bordering NON-sliver class. Background is never a sliver and is a valid absorber.
   A frame with one food-like class has no slivers (explicit guard, so a fraction
   above 1 cannot make it one).
2. **Speckle rule** (`minRegionArea`). Components under the threshold are relabelled
   to their dominant bordering class of any kind.

Order per component: sliver rule first; if the component's class is a sliver but it
borders only other slivers (or nothing), it falls through to the speckle rule
unchanged. That is what keeps `sliverFraction: 0` byte-identical to the speckle-only
pass — the sliver set is empty and every component takes the old path.

## Gotchas

- `regulariseLabelMap` takes the `ClassPalette`; the sliver set cannot be derived
  from the label bytes alone.
- `.disabled` is the only true passthrough (`isPassthrough` needs both rules off).
  `MaskRegularisationConfig(minRegionArea: 12, sliverFraction: 0)` is "today's
  speckle-only output", not passthrough.
- `.standard` carries the shipped sliver fraction, **0.05** since the task 3 sweep
  (unknown-food-nameable Decision 3). Every `process(...)` call without an explicit
  `regularisation:` gets it — including, since that task, the two offline entry
  points (see below).
- A component bordered only by sliver classes in 2D means the union of slivers
  touches nothing but the frame edge; the unit test realises it as a strip along the
  top edge whose only neighbour is another sliver strip.

## Replay runs it too (unknown-food-nameable task 3)

`process(...)` is the device path and owns the logits. Replay has neither logits nor
a call into `process`, so until task 3 the offline tools scored an UNregularised
label map while the device produced a regularised one:

- `SegBench.sample` argmaxed the stored probability tensor and scored that directly.
- `FixtureRunner` passed the fixture's stored argmax straight into the volume stage.

Both now take `regularisation:` (default `.standard`) and go through the public
`SegmenterPostProcessor.regularise(argmax:width:height:palette:config:)`, which is a
thin wrapper over the same internal `regulariseLabelMap`. `HarnessCLI seg-bench` and
`HarnessCLI accuracy` take `--sliver-fraction <f>` to substitute the sliver fraction
into `.standard` (the speckle strength is not swept), and both print the fraction in
use to stderr. `seg-bench` also writes it into its JSON as `sliver_fraction`.

Consequences worth knowing:

- Offline numbers recorded before 2026-09-24 are not comparable with ones after it.
- `SegBench.sample` regularises the PREDICTION only. Ground truth is the yardstick
  and is never reshaped.
- Tests that assert a raw decode must pass `.disabled` explicitly. A 1×2 or other
  tiny fixture is entirely below `minRegionArea: 12`, so `.standard` rewrites all of
  it — this is what broke `testWellFormedFixtureBuildsSampleWithDecodedArgmax`.
- Re-regularising an already-regularised map is close to a no-op: the five bundles in
  `tmp/device_captures` replay byte-identically at fractions 0, 0.05 and 0.10, because
  their stored argmax was cleaned on device before it was written.

## Measuring a fraction

The corpus is NOT Nutrition5k, whatever the spec text says — N5k has no truth masks
and no probability tensors (see `n5k-calibration-harness.md`). Use the segmenter's
leak-free held-out split:

```sh
python tools/segmenter/make_fixtures.py \
    --checkpoint tools/segmenter/build/checkpoint_merged_v2.pt \
    --heldout data/foodseg103_remapped_v2/heldout_leakfree \
    --out tmp/segbench_fixtures --reference-out tmp/segbench_reference.png
swift build -c release --product HarnessCLI
./.build/release/HarnessCLI seg-bench --fixtures-dir tmp/segbench_fixtures \
    --checkpoint-sha256 $(shasum -a 256 tools/segmenter/build/checkpoint_merged_v2.pt | cut -d' ' -f1) \
    --sliver-fraction 0.05 --output tmp/segbench_0.05.json
```

182 fixtures, about 3.3 GB (513×513×36 FP16 per fixture), a few minutes end to end.
`make_fixtures.py` needs torch; `tools/segmenter/.venv` is gitignored and the venv
needs `protobuf` at least as new as the system `protoc` (a stale runtime fails with
`VersionError: Detected incompatible Protobuf Gencode/Runtime versions`).

`seg-bench` reports mIoU, which the current checkpoint
is — write the report with `--output` and read the file, do not rely on the exit code.

**Read the mean with the denominator.** `SegBench` drops a class whose IoU
denominator is 0, so absorbing a class out of the output entirely REMOVES it from the
mean rather than scoring it 0. At fraction 0 two phantom liquid classes (`water`,
`milk`) score 0.0000 on this split and at 0.05 they are gone, which lifts the reported
mean by 0.029 without any retained class improving. Compare over the classes present
at every fraction or the sweep will mislead you — that fixed-denominator comparison is
what put the shipped fraction at 0.05 rather than 0.10.
