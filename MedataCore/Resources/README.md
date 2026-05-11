# MedataCore/Resources

Bundled resources loaded at runtime by `MedataCore`:

- `segmenter.mlpackage/` — Core ML segmenter (decision 27, task 23 output).
  Produced by `tools/segmenter/export.py` from a PyTorch checkpoint.
  Not committed; built locally or by CI and bundled at build time.
- `food_db.sqlite` — CoFID + IFCDB overlay food database (decision 27,
  task 49 output).

This directory exists so the app/swift-package targets can reference a
stable resource root. Heavy artefacts (.mlpackage, SQLite) are excluded
from version control via `.gitignore`.
