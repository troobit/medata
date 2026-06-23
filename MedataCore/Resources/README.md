# MedataCore/Resources

Bundled resources loaded at runtime by `MedataCore`:

- `food_segmenter.mlpackage/` — Core ML segmenter (decision 27, task 23 output).
  Produced by `tools/segmenter/export.py` from a PyTorch checkpoint.
  Filename must match the `PipelineFactory` loader.
  Not committed; built locally or by CI and bundled at build time.
- `cofid_db.sqlite` + `afcd_db.sqlite` — CoFID + AFCD food databases
  (decision 27, decision 39, task 74 output; IFCDB overlay removed).

This directory exists so the app/swift-package targets can reference a
stable resource root. Heavy artefacts (.mlpackage, SQLite) are excluded
from version control via `.gitignore`.
