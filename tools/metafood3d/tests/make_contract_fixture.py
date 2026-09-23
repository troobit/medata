"""Regenerate the committed run_summary contract fixture (Decision 17).

``fixtures/run_summary_contract.json`` is produced by the REAL emitter
(``ingest._summary_doc``) on fixed synthetic inputs, so the Python emitter
and the Swift decoder (``CalibrateRun.loadIngestSummary``) share one
committed artefact and cannot drift silently again:

- ``test_mf3d_ingest.py::TestRunSummaryContract`` regenerates the document
  and diffs it against the committed file — an emitter key change goes red
  here first;
- ``MedataCore/Tests/HarnessCLITests/EndToEndCalibrateBakeTests.swift``
  feeds the SAME committed file to the built HarnessCLI binary, whose
  loader exits 1 on any missing contract key — a decoder change (or a
  stale fixture) goes red there.

Regenerate after an intentional contract change::

    tools/metafood3d/.venv/bin/python tools/metafood3d/tests/make_contract_fixture.py

The fixed inputs mirror the end-to-end test's constants: snapshot
``abc123def456``, mapping version ``c0ffee123456``, the PINNED render
config (640x480 at plane depth 385 mm — the InjectedPlaneTests scene
plane), an empty ingest tally.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

import mf3d_testkit  # noqa: E402

FIXTURE_PATH = _HERE / "fixtures" / "run_summary_contract.json"

# Pinned synthetic inputs — keep in lockstep with
# EndToEndCalibrateBakeTests.swift (snapshot / mappingVersion constants).
SNAPSHOT = "abc123def456"
MAPPING_VERSION = "c0ffee123456"


def contract_doc() -> dict:
    ingest = mf3d_testkit.load_tool("ingest")
    return ingest._summary_doc(
        ingest.RunSummary(),
        source_dataset=f"{ingest.DATASET_NAME}@{SNAPSHOT}",
        snapshot_id=SNAPSHOT,
        mapping_version=MAPPING_VERSION,
        categories_source="curated_rules_only",
        cfg=ingest.PINNED_RENDER_CONFIG,
        scale_check_failed=False,
    )


def contract_text() -> str:
    # Exactly the serialisation ingest.py writes to disk.
    return json.dumps(contract_doc(), indent=2) + "\n"


def main() -> int:
    FIXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_PATH.write_text(contract_text())
    print(f"wrote {FIXTURE_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
