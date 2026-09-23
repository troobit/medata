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
- `.standard` carries the shipped sliver fraction (0.10 until the N5k measurement in
  unknown-food-nameable task 3 fixes it). Every `process(...)` call without an
  explicit `regularisation:` gets it.
- A component bordered only by sliver classes in 2D means the union of slivers
  touches nothing but the frame edge; the unit test realises it as a strip along the
  top edge whose only neighbour is another sliver strip.
