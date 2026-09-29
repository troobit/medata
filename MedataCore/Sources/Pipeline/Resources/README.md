# Pipeline bundled resources

This directory is the `Pipeline` target's resource bundle (`Bundle.module`),
declared as `.copy("Resources")` in the root `Package.swift`.

## `segmenter.mlpackage`

The on-device Core ML segmentation model is **not** committed to git (it is a
large, generated binary — see `.gitignore`). `tools/segmenter/export.py` writes
it to:

    MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage

When present, a Release build bundles it and `Pipeline.makeSegmenter` loads it
via `Bundle.module`. When absent — the state today, before the model is
trained — `Pipeline.resolveBundledSegmenterURL` throws
`PipelineFactoryError.segmenterModelMissing`. Debug builds use the
`DEV_STUB_SEGMENTER` engine and never touch this file.

This `README.md` is the committed marker that keeps the directory (and therefore
`Bundle.module`) present in clean checkouts that do not yet have the model. See
model-production spec Decision 7.
