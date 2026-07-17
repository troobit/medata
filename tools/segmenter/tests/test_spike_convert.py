"""spike_convert candidate-registry tests (snaq-parity task 23, Req 5.1-5.3).

``spike_convert.py`` generalises the task-20 SegFormer spike to the full
bake-off shortlist. Per candidate the registry records the weights source, the
conversion toolchain, and the 35-channel head graft; the four ordered
stop-on-fail criteria and the ``build/spike_<candidate>.json`` verdict shape
(with size/latency margins — Req 5.3 headroom) are shared.

Two verdicts must never blur (Req 5.2): ``reject`` is MODEL evidence (a
criterion measurably failed); ``blocked-toolchain`` is a HARNESS limit
(PP-MobileSeg is PaddlePaddle-native — our torch→Core ML chain cannot even
attempt it), and must not masquerade as model evidence. The latency criterion
is emitted as ``"pending"`` — the 16 Pro measurement is human-gated and its
budget derives from the Req 4.2 tail-profile derivation, not the nominal
250 ms figure.

Only the light halves run here (torch-free, the spike_segformer pattern);
conversion runs are human-gated in the venv (prerequisites.md).
"""

from __future__ import annotations

import json

import pytest

import export
import spike_convert


SHORTLIST = ("segformer_b0", "efficientvit_b0", "efficientvit_b1",
             "seaformer_base", "ppmobileseg_base")


# ── Candidate registry ──────────────────────────────────────────────────────────

def test_registry_holds_the_shortlist():
    assert tuple(spike_convert.CANDIDATES) == SHORTLIST


def test_every_candidate_records_source_toolchain_and_graft():
    for name in SHORTLIST:
        cand = spike_convert.get_candidate(name)
        assert cand.name == name
        assert cand.weights_source  # where the public checkpoint comes from
        assert cand.toolchain in ("hf_transformers", "pytorch_github",
                                  "paddlepaddle")
        assert cand.head_graft  # how the 35-channel head is grafted
        assert isinstance(cand.toolchain_supported, bool)


def test_unknown_candidate_is_rejected_by_name():
    with pytest.raises(ValueError, match="mobilevit"):
        spike_convert.get_candidate("mobilevit")


def test_ppmobileseg_is_toolchain_blocked_not_loadable():
    cand = spike_convert.get_candidate("ppmobileseg_base")
    assert cand.toolchain == "paddlepaddle"
    assert cand.toolchain_supported is False
    for name in SHORTLIST:
        if name != "ppmobileseg_base":
            assert spike_convert.get_candidate(name).toolchain_supported is True


def test_verdict_path_is_per_candidate():
    assert str(spike_convert.verdict_path_for("efficientvit_b0")).endswith(
        "build/spike_efficientvit_b0.json"
    )


# ── Verdict shape (Req 5.2/5.3) ─────────────────────────────────────────────────

def _passing_verdict(name="segformer_b0"):
    return spike_convert.assemble_verdict(
        spike_convert.get_candidate(name),
        converts=True, artefact_bytes=8_000_000,
        budget_bytes=export.WEIGHTS_MAX_BYTES, size_ok=True,
        oracle_max_abs_err=0.12, oracle_argmax_agreement=0.998, oracle_ok=True,
    )


def test_verdict_shape_carries_candidate_provenance_and_margins():
    v = _passing_verdict()
    assert v["schema"] == "spike_convert.v1"
    assert v["candidate"] == "segformer_b0"
    assert v["weights_source"] == spike_convert.get_candidate(
        "segformer_b0").weights_source
    assert v["toolchain"] == "hf_transformers"
    assert v["target_size"] == 513
    assert v["num_classes"] == 35
    m = v["measurements"]
    assert m["artefact_bytes"] == 8_000_000
    assert m["weights_max_bytes"] == export.WEIGHTS_MAX_BYTES
    # Req 5.3 headroom: margins recorded so future device floors can re-rank
    # candidates without re-running the spikes.
    assert m["size_margin_bytes"] == export.WEIGHTS_MAX_BYTES - 8_000_000
    assert m["latency_ms"] is None
    assert m["latency_budget_ms"] is None
    assert m["latency_margin_ms"] is None


def test_latency_criterion_is_emitted_as_pending():
    v = _passing_verdict()
    assert v["criteria"]["3_latency_within_budget_ane_resident"] == "pending"
    # The pending note names the human gate and the Req 4.2-derived budget.
    joined = " ".join(v["notes"])
    assert "iPhone 16 Pro" in joined
    assert "Req 4.2" in joined


def test_autonomous_pass_is_pending_never_pass():
    # All measured criteria green still cannot be "pass": the latency half is
    # human-gated, and conversion feasibility alone must not read as adoption.
    assert _passing_verdict()["verdict"] == "pending"


def test_failed_conversion_is_a_reject_with_later_criteria_null():
    v = spike_convert.assemble_verdict(
        spike_convert.get_candidate("segformer_b0"),
        converts=False, notes=["conversion failed: unsupported op"],
    )
    assert v["verdict"] == "reject"
    assert v["criteria"]["1_converts_to_coreml"] is False
    # Stop-on-fail: criteria never reached are null, not false.
    assert v["criteria"]["2_fp16_artefact_within_budget"] is None
    assert v["criteria"]["4_matches_pytorch_oracle"] is None


def test_size_failure_is_a_reject():
    v = spike_convert.assemble_verdict(
        spike_convert.get_candidate("efficientvit_b1"),
        converts=True, artefact_bytes=30_000_000,
        budget_bytes=export.WEIGHTS_MAX_BYTES, size_ok=False,
    )
    assert v["verdict"] == "reject"
    assert v["measurements"]["size_margin_bytes"] < 0  # headroom stays honest
    assert v["criteria"]["4_matches_pytorch_oracle"] is None


def test_oracle_failure_is_a_reject():
    v = spike_convert.assemble_verdict(
        spike_convert.get_candidate("segformer_b0"),
        converts=True, artefact_bytes=8_000_000,
        budget_bytes=export.WEIGHTS_MAX_BYTES, size_ok=True,
        oracle_max_abs_err=3.2, oracle_argmax_agreement=0.41, oracle_ok=False,
    )
    assert v["verdict"] == "reject"


# ── blocked-toolchain is distinct from reject (Req 5.2) ─────────────────────────

def test_blocked_toolchain_verdict_is_not_a_reject():
    v = spike_convert.assemble_verdict(
        spike_convert.get_candidate("ppmobileseg_base"), blocked=True,
    )
    assert v["verdict"] == "blocked-toolchain"
    assert v["verdict"] != "reject"
    # No criterion was measured — all null, none false.
    assert v["criteria"]["1_converts_to_coreml"] is None
    assert v["criteria"]["2_fp16_artefact_within_budget"] is None
    assert v["criteria"]["4_matches_pytorch_oracle"] is None
    joined = " ".join(v["notes"])
    assert "harness" in joined.lower() or "toolchain" in joined.lower()


def test_run_spike_short_circuits_blocked_toolchain_without_heavy_deps(tmp_path):
    # Runnable torch-free: the blocked-toolchain path must not import torch,
    # transformers, or coremltools — the harness limit is known a priori.
    verdict = spike_convert.run_spike(
        "ppmobileseg_base",
        out_mlpackage=str(tmp_path / "spike.mlpackage"),
        verdict_path=str(tmp_path / "build" / "spike_ppmobileseg_base.json"),
    )
    assert verdict["verdict"] == "blocked-toolchain"
    on_disk = json.loads(
        (tmp_path / "build" / "spike_ppmobileseg_base.json").read_text())
    assert on_disk == verdict


def test_write_verdict_round_trips(tmp_path):
    v = _passing_verdict()
    out = spike_convert.write_verdict(v, tmp_path / "build" / "v.json")
    assert json.loads(out.read_text()) == v


# ── CLI surface (torch-free) ────────────────────────────────────────────────────

def test_help_lists_candidates_and_the_human_gate(capsys):
    with pytest.raises(SystemExit) as exc:
        spike_convert.main(["--help"])
    assert exc.value.code == 0
    out = capsys.readouterr().out
    assert "--candidate" in out
    assert "human-gated" in out


def test_unknown_candidate_flag_is_an_argparse_error(capsys):
    with pytest.raises(SystemExit) as exc:
        spike_convert.main(["--candidate", "mobilevit"])
    assert exc.value.code == 2
    assert "--candidate" in capsys.readouterr().err
