"""SegFormer-B0 spike script tests (segmenter-foundation task 14, design §5.2).

Only the light halves are testable without torch/transformers/coremltools:
verdict-JSON assembly (stop-on-fail semantics, pending latency criterion) and
the size check against a stub artefact. The conversion run itself is exercised
by executing the script in the gated session, not by this suite.
"""

from __future__ import annotations

import json

import pytest

import export
import spike_segformer


# ── Verdict assembly ────────────────────────────────────────────────────────────

def test_verdict_has_four_criteria_with_latency_always_pending():
    v = spike_segformer.assemble_verdict(
        checkpoint="nvidia/segformer-b0-finetuned-ade-512-512",
        converts=True, artefact_bytes=8_000_000,
        budget_bytes=export.WEIGHTS_MAX_BYTES, size_ok=True,
        oracle_max_abs_err=0.12, oracle_argmax_agreement=0.998, oracle_ok=True,
    )
    assert v["schema"] == "spike_segformer.v1"
    assert v["target_size"] == 513
    assert v["num_classes"] == 35
    assert v["criteria"] == {
        "1_converts_to_coreml": True,
        "2_fp16_artefact_within_budget": True,
        "3_latency_ane_resident": None,  # human-gated half (Decision 16)
        "4_matches_pytorch_oracle": True,
    }
    assert v["measurements"]["artefact_bytes"] == 8_000_000
    assert v["measurements"]["weights_max_bytes"] == export.WEIGHTS_MAX_BYTES
    # Decision 22 hardware floor: the pending note names the iPhone 16 Pro.
    assert any("iPhone 16 Pro" in n for n in v["notes"])


def test_failed_conversion_leaves_later_criteria_null_not_false():
    v = spike_segformer.assemble_verdict(
        checkpoint="x", converts=False, size_ok=True, oracle_ok=True,
        notes=["conversion failed: unsupported op"],
    )
    assert v["criteria"]["1_converts_to_coreml"] is False
    # Stop-on-fail: criteria never reached are null, not false.
    assert v["criteria"]["2_fp16_artefact_within_budget"] is None
    assert v["criteria"]["4_matches_pytorch_oracle"] is None
    assert "conversion failed: unsupported op" in v["notes"]


def test_write_verdict_round_trips(tmp_path):
    v = spike_segformer.assemble_verdict(checkpoint="x", converts=False)
    out = spike_segformer.write_verdict(v, tmp_path / "build" / "verdict.json")
    assert json.loads(out.read_text()) == v


# ── Criterion 2: size check against a stub artefact ─────────────────────────────

def test_artefact_size_check_uses_the_shipping_budget(tmp_path):
    stub = tmp_path / "stub.mlpackage"
    stub.mkdir()
    (stub / "weights.bin").write_bytes(b"\x00" * 1024)
    ok, size, budget = spike_segformer.artefact_within_budget(stub)
    assert ok is True
    assert size == 1024
    assert budget == export.WEIGHTS_MAX_BYTES  # 24 MiB — the same gate as export


def test_artefact_over_budget_fails(tmp_path):
    stub = tmp_path / "stub.mlpackage"
    stub.mkdir()
    (stub / "weights.bin").write_bytes(b"\x00" * 2048)
    ok, size, budget = spike_segformer.artefact_within_budget(stub, max_bytes=1024)
    assert ok is False
    assert size == 2048
    assert budget == 1024


def test_missing_artefact_raises_the_export_gate_error(tmp_path):
    with pytest.raises(export.ExportGateError):
        spike_segformer.artefact_within_budget(tmp_path / "absent.mlpackage")


# ── CLI surface (torch-free) ────────────────────────────────────────────────────

def test_help_runs_without_heavy_deps(capsys):
    with pytest.raises(SystemExit) as exc:
        spike_segformer.main(["--help"])
    assert exc.value.code == 0
    out = capsys.readouterr().out
    assert "human-gated" in out  # --help self-documents the pending half
