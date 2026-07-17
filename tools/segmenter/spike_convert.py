#!/usr/bin/env python3
"""Architecture bake-off conversion spike (snaq-parity Req 5.1-5.3, Decision 12).

Generalises the task-20 SegFormer spike (``spike_segformer.py``) to the full
shortlist behind one per-candidate registry: weights source, conversion
toolchain, and 35-channel head graft. The four ordered stop-on-fail criteria
of segmenter-foundation design §5.1 are unchanged, as is the reuse of
``export.py``'s shipping gates (``WEIGHTS_MAX_BYTES``, ``reference_input``,
``oracle_agreement`` — Decision 7):

  1. Converts to Core ML?      coremltools.convert() of the public checkpoint
                               with a 35-channel head grafted, FP16, 513x513.
  2. FP16 artefact <= 24 MiB?  export.WEIGHTS_MAX_BYTES — the shipping budget.
  3. Within the latency budget, ANE-resident?
                               NOT MEASURED HERE — emitted as ``"pending"``.
                               Human-gated: Xcode Core ML performance report on
                               the iPhone 16 Pro (Decision 22 floor), against
                               the budget DERIVED from the measured tail
                               profile (Req 4.2) — not the nominal 250 ms.
  4. Matches PyTorch outputs?  export.oracle_agreement thresholds.

Verdicts (Req 5.2 — evidence must never blur):

  - ``reject``            a measured criterion failed: MODEL evidence; the
                          candidate gets no further training investment.
  - ``blocked-toolchain`` the conversion chain cannot even attempt the
                          candidate (PP-MobileSeg is PaddlePaddle-native; this
                          torch→Core ML harness has no Paddle ingest): a
                          HARNESS limit, recorded distinctly so it is never
                          laundered as model evidence.
  - ``pending``           every measured criterion passed; the human-gated
                          latency half decides. Conversion feasibility alone
                          is NOT adoption (Req 5.4).

Each verdict JSON (``build/spike_<candidate>.json``) records the measured
numbers AND the margins — size and latency headroom (Req 5.3) — so future
device floors can re-rank candidates without re-running the spikes.

Usage::

    pip install -r tools/segmenter/requirements.txt
    python tools/segmenter/spike_convert.py --candidate segformer_b0

Heavy deps (torch, transformers, coremltools, candidate model zoos) are
imported lazily; ``--help``, the registry, verdict assembly, and the
blocked-toolchain path all run torch-free (registry-fixture testable).
A missing optional package (e.g. the efficientvit zoo) aborts the run with an
install message and writes NO verdict — an environment gap is neither model
evidence nor a toolchain block.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional

# The shipping contract every candidate must slot into (pipeline Decision 11).
TARGET_SIZE = 513
NUM_CLASSES = 35

VERDICT_SCHEMA = "spike_convert.v1"
BUILD_DIR = Path("tools/segmenter/build")

# Explanation stamped on criterion 3 while it is pending: the measurement is
# human-gated on the physical iPhone 16 Pro (Decision 22 floor) and judged
# against the Req 4.2-derived budget, which must be recorded in the decision
# log before any candidate verdict is acted on.
LATENCY_PENDING_NOTE = (
    "criterion 3 (latency within budget, ANE-resident) is human-gated: measure "
    "with Xcode's Core ML performance report on the iPhone 16 Pro (Decision 22 "
    "floor) against the budget derived from the measured tail profile "
    "(Req 4.2) — not the nominal 250 ms — then complete this JSON and record "
    "the verdict in the decision log"
)

BLOCKED_TOOLCHAIN_NOTE = (
    "blocked-toolchain: the conversion harness cannot attempt this candidate — "
    "a harness limit, NOT model evidence (Req 5.2); revisit if a supported "
    "conversion path appears"
)


def _load_sibling(name: str):
    """Import a sibling module by NAME via sys.path (the loss_config pattern)
    so the spike shares the same module instances — budget constant, oracle
    helpers, SegFormer loader — as the shipping chain (Decision 7)."""
    tools_dir = str(Path(__file__).resolve().parent)
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    import importlib
    return importlib.import_module(name)


# ── Candidate registry ──────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Candidate:
    """One bake-off candidate: provenance plus the (lazy, heavy) loader that
    returns a traceable module emitting logits for a [1, 3, 513, 513] input."""

    name: str
    weights_source: str        # where the public checkpoint comes from
    toolchain: str             # hf_transformers | pytorch_github | paddlepaddle
    head_graft: str            # how the 35-channel head is grafted
    toolchain_supported: bool  # False -> blocked-toolchain, never reject
    loader: Optional[Callable[[], Any]] = None  # heavy; None when blocked


def _load_segformer_b0():
    """Reuse the task-20 spike's loader: SegFormer-B0 with the decode head's
    classifier conv re-grafted to 35 channels (spike_segformer._load_spike_model)."""
    spike_segformer = _load_sibling("spike_segformer")
    return spike_segformer._load_spike_model(spike_segformer.DEFAULT_CHECKPOINT)


def _graft_last_conv_head(model, num_classes: int):
    """Generic 35-channel head graft for zoo models: replace the LAST Conv2d
    (the segmentation classifier in the shortlisted architectures) with a
    fresh 1x1 conv. Accuracy is irrelevant to the spike — only conversion
    mechanics are measured — but the channel contract must hold."""
    import torch

    convs = [(name, m) for name, m in model.named_modules()
             if isinstance(m, torch.nn.Conv2d)]
    if not convs:
        raise SystemExit("[spike] no Conv2d found to graft the head onto")
    name, last = convs[-1]
    parent = model
    *path, attr = name.split(".")
    for part in path:
        parent = getattr(parent, part)
    setattr(parent, attr,
            torch.nn.Conv2d(last.in_channels, num_classes, kernel_size=1))
    return model


def _load_efficientvit(variant: str):
    """EfficientViT-Seg from the mit-han-lab zoo (pip install from the GitHub
    repo). ADE20K weights; the head is re-grafted to 35 channels."""
    try:
        from efficientvit.seg_model_zoo import create_seg_model
    except ImportError as exc:
        raise SystemExit(
            "[spike] the efficientvit package is required for this candidate. "
            "Install with:\n"
            "  pip install git+https://github.com/mit-han-lab/efficientvit\n"
            "(environment gap — no verdict written)"
        ) from exc
    import torch

    model = create_seg_model(name=variant, dataset="ade20k")
    model = _graft_last_conv_head(model, NUM_CLASSES)
    model.eval()

    class LogitsOnly(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            out = self.m(x)
            return out["segout"] if isinstance(out, dict) else out

    return LogitsOnly(model).eval()


def _load_seaformer_base():
    """SeaFormer-Base (fudan-zvg/SeaFormer). No pip package: the repo must be
    on PYTHONPATH with its ADE20K checkpoint downloaded."""
    try:
        import seaformer  # noqa: F401
    except ImportError as exc:
        raise SystemExit(
            "[spike] the SeaFormer repo is required for this candidate: clone "
            "github.com/fudan-zvg/SeaFormer, add its seg/ tree to PYTHONPATH, "
            "and download the SeaFormer-Base ADE20K checkpoint "
            "(environment gap — no verdict written)"
        ) from exc
    import torch

    model = seaformer.build_seaformer_base()
    model = _graft_last_conv_head(model, NUM_CLASSES)
    return model.eval()


CANDIDATES: dict[str, Candidate] = {
    c.name: c for c in (
        Candidate(
            name="segformer_b0",
            weights_source="hf:nvidia/segformer-b0-finetuned-ade-512-512",
            toolchain="hf_transformers",
            head_graft="decode_head.classifier Conv2d re-grafted to 35 channels "
                       "(spike_segformer._load_spike_model)",
            toolchain_supported=True,
            loader=_load_segformer_b0,
        ),
        Candidate(
            name="efficientvit_b0",
            weights_source="github.com/mit-han-lab/efficientvit "
                           "(efficientvit-seg b0, ADE20K checkpoint)",
            toolchain="pytorch_github",
            head_graft="final classifier Conv2d replaced with a fresh 1x1 conv "
                       "to 35 channels (_graft_last_conv_head)",
            toolchain_supported=True,
            loader=lambda: _load_efficientvit("efficientvit-seg-b0"),
        ),
        Candidate(
            name="efficientvit_b1",
            weights_source="github.com/mit-han-lab/efficientvit "
                           "(efficientvit-seg b1, ADE20K checkpoint)",
            toolchain="pytorch_github",
            head_graft="final classifier Conv2d replaced with a fresh 1x1 conv "
                       "to 35 channels (_graft_last_conv_head)",
            toolchain_supported=True,
            loader=lambda: _load_efficientvit("efficientvit-seg-b1"),
        ),
        Candidate(
            name="seaformer_base",
            weights_source="github.com/fudan-zvg/SeaFormer "
                           "(SeaFormer-Base, ADE20K checkpoint)",
            toolchain="pytorch_github",
            head_graft="final classifier Conv2d replaced with a fresh 1x1 conv "
                       "to 35 channels (_graft_last_conv_head)",
            toolchain_supported=True,
            loader=_load_seaformer_base,
        ),
        Candidate(
            name="ppmobileseg_base",
            weights_source="github.com/PaddlePaddle/PaddleSeg "
                           "(PP-MobileSeg-Base, ADE20K checkpoint)",
            toolchain="paddlepaddle",
            head_graft="not attempted — PaddlePaddle-native graph; no "
                       "torch-side head to graft",
            toolchain_supported=False,  # blocked-toolchain, never reject
            loader=None,
        ),
    )
}


def get_candidate(name: str) -> Candidate:
    """Look up a candidate; unknown names raise with the shortlist listed."""
    if name not in CANDIDATES:
        raise ValueError(
            f"unknown candidate {name!r}; choose one of {', '.join(CANDIDATES)}"
        )
    return CANDIDATES[name]


def verdict_path_for(name: str) -> Path:
    """Default ``build/spike_<candidate>.json`` location (Req 5.2 evidence)."""
    return BUILD_DIR / f"spike_{get_candidate(name).name}.json"


def mlpackage_path_for(name: str) -> Path:
    return BUILD_DIR / f"spike_{get_candidate(name).name}.mlpackage"


# ── Verdict assembly (pure; unit-tested without the heavy deps) ─────────────────

def overall_verdict(*, blocked: bool, converts: Optional[bool],
                    size_ok: Optional[bool], oracle_ok: Optional[bool]) -> str:
    """Fold the measured criteria into the recorded verdict (Req 5.2):
    ``blocked-toolchain`` (harness limit, nothing measured), ``reject`` (a
    measured criterion failed — model evidence), or ``pending`` (autonomous
    half passed; the human-gated latency half decides)."""
    if blocked:
        return "blocked-toolchain"
    if converts is False or size_ok is False or oracle_ok is False:
        return "reject"
    return "pending"


def assemble_verdict(
    candidate: Candidate,
    *,
    blocked: bool = False,
    converts: Optional[bool] = None,
    artefact_bytes: Optional[int] = None,
    budget_bytes: Optional[int] = None,
    size_ok: Optional[bool] = None,
    oracle_max_abs_err: Optional[float] = None,
    oracle_argmax_agreement: Optional[float] = None,
    oracle_ok: Optional[bool] = None,
    notes: Optional[list[str]] = None,
) -> dict[str, Any]:
    """Assemble the verdict JSON. Stop-on-fail semantics: criteria never
    reached stay ``None`` (a failed conversion leaves 2 and 4 null, not
    false); criterion 3 is always the string ``"pending"`` here — the
    human-gated half replaces it with a boolean when the 16 Pro measurement
    lands. Margins (Req 5.3) record headroom so future device floors can
    re-rank without re-running."""
    if blocked or not converts:
        size_ok = None
        oracle_ok = None
    size_margin = (None if artefact_bytes is None or budget_bytes is None
                   else budget_bytes - artefact_bytes)
    all_notes = [LATENCY_PENDING_NOTE]
    if blocked:
        all_notes.append(BLOCKED_TOOLCHAIN_NOTE)
    all_notes.extend(notes or [])
    return {
        "schema": VERDICT_SCHEMA,
        "candidate": candidate.name,
        "weights_source": candidate.weights_source,
        "toolchain": candidate.toolchain,
        "head_graft": candidate.head_graft,
        "target_size": TARGET_SIZE,
        "num_classes": NUM_CLASSES,
        "criteria": {
            "1_converts_to_coreml": None if blocked else converts,
            "2_fp16_artefact_within_budget": size_ok,
            "3_latency_within_budget_ane_resident": "pending",
            "4_matches_pytorch_oracle": oracle_ok,
        },
        "verdict": overall_verdict(blocked=blocked, converts=converts,
                                   size_ok=size_ok, oracle_ok=oracle_ok),
        "measurements": {
            "artefact_bytes": artefact_bytes,
            "weights_max_bytes": budget_bytes,
            "size_margin_bytes": size_margin,
            "oracle_max_abs_err": oracle_max_abs_err,
            "oracle_argmax_agreement": oracle_argmax_agreement,
            # Latency slots stay null until the human-gated measurement lands;
            # the budget itself is the Req 4.2 derivation, recorded in the
            # decision log before any verdict is acted on.
            "latency_ms": None,
            "latency_budget_ms": None,
            "latency_margin_ms": None,
        },
        "notes": all_notes,
    }


def write_verdict(verdict: dict[str, Any], path: str | Path) -> Path:
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(verdict, indent=2) + "\n", encoding="utf-8")
    return out


# ── Spike execution (heavy beyond the blocked-toolchain short-circuit) ──────────

def run_spike(candidate_name: str, out_mlpackage: Optional[str] = None,
              verdict_path: Optional[str] = None,
              reference_image: Optional[str] = None) -> dict[str, Any]:
    """Criteria 1, 2 and 4 in order, stop-on-fail; writes the verdict JSON.

    The blocked-toolchain short-circuit runs BEFORE any heavy import — the
    harness limit is known a priori and needs no torch to record."""
    candidate = get_candidate(candidate_name)
    out_mlpackage = out_mlpackage or str(mlpackage_path_for(candidate_name))
    verdict_path = verdict_path or str(verdict_path_for(candidate_name))

    if not candidate.toolchain_supported:
        verdict = assemble_verdict(candidate, blocked=True)
        write_verdict(verdict, verdict_path)
        print(f"[spike] {candidate.name}: blocked-toolchain "
              f"({candidate.toolchain}) — harness limit recorded, "
              "not model evidence")
        return verdict

    try:
        import torch
        import coremltools as ct
    except ImportError as exc:
        raise SystemExit(
            "The spike needs torch and coremltools (plus the candidate's "
            "model zoo). Install with:\n"
            "  pip install -r tools/segmenter/requirements.txt"
        ) from exc
    import numpy as np

    export = _load_sibling("export")
    notes: list[str] = []
    assert candidate.loader is not None
    wrapped = candidate.loader()

    # ── Criterion 1: converts to Core ML? ────────────────────────────────────
    example = torch.randn(1, 3, TARGET_SIZE, TARGET_SIZE, dtype=torch.float32)
    try:
        with torch.no_grad():
            traced = torch.jit.trace(wrapped, example, strict=False)
        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="input", shape=example.shape,
                                  dtype=np.float16)],
            outputs=[ct.TensorType(name="logits", dtype=np.float16)],
            compute_precision=ct.precision.FLOAT16,
            compute_units=ct.ComputeUnit.ALL,
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS17,
        )
        out = Path(out_mlpackage)
        out.parent.mkdir(parents=True, exist_ok=True)
        mlmodel.save(str(out))
    except Exception as exc:  # a hard conversion failure ends the spike
        notes.append(f"conversion failed: {type(exc).__name__}: {exc}")
        verdict = assemble_verdict(candidate, converts=False, notes=notes)
        write_verdict(verdict, verdict_path)
        print(f"[spike] {candidate.name}: criterion 1 FAILED — {exc}",
              file=sys.stderr)
        return verdict
    print(f"[spike] {candidate.name}: criterion 1 ok — {out_mlpackage}")

    # ── Criterion 2: FP16 artefact within the shipping budget? ───────────────
    size = export.mlpackage_weight_bytes(out_mlpackage)
    budget = export.WEIGHTS_MAX_BYTES
    size_ok = size <= budget
    print(f"[spike] {candidate.name}: criterion 2 "
          f"{'ok' if size_ok else 'FAILED'} — {size} bytes (budget {budget})")
    if not size_ok:
        verdict = assemble_verdict(candidate, converts=True,
                                   artefact_bytes=size, budget_bytes=budget,
                                   size_ok=False, notes=notes)
        write_verdict(verdict, verdict_path)
        return verdict

    # ── Criterion 4: equivalence oracle (Decision 7 reuse) ───────────────────
    x = export.reference_input(TARGET_SIZE, reference_image)
    oracle_out = export.run_pytorch(wrapped, x)
    coreml_out = export.run_coreml(out_mlpackage, x)
    err, agree, oracle_ok = export.oracle_agreement(oracle_out, coreml_out)
    print(f"[spike] {candidate.name}: criterion 4 "
          f"{'ok' if oracle_ok else 'FAILED'} — max abs err = {err:.4f}, "
          f"argmax agree = {agree:.4f}")
    if not oracle_ok:
        notes.append(
            "oracle mismatch — log the numeric deviation (design §5.1.4); do "
            "not widen the thresholds"
        )

    verdict = assemble_verdict(
        candidate, converts=True,
        artefact_bytes=size, budget_bytes=budget, size_ok=True,
        oracle_max_abs_err=err, oracle_argmax_agreement=agree,
        oracle_ok=bool(oracle_ok), notes=notes,
    )
    write_verdict(verdict, verdict_path)
    return verdict


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--candidate", required=True,
                        choices=tuple(CANDIDATES),
                        help="Shortlisted candidate to spike (Req 5.1).")
    parser.add_argument("--out", default=None,
                        help="Where to save the converted .mlpackage "
                             "(default build/spike_<candidate>.mlpackage).")
    parser.add_argument("--verdict", default=None,
                        help="Where to write the verdict JSON "
                             "(default build/spike_<candidate>.json).")
    parser.add_argument("--reference-image", default=None,
                        help="Optional image for the equivalence oracle; "
                             "otherwise export.reference_input's deterministic "
                             "synthetic input is used.")
    args = parser.parse_args(argv)

    verdict = run_spike(args.candidate, args.out, args.verdict,
                        args.reference_image)
    print(f"[spike] verdict -> "
          f"{args.verdict or verdict_path_for(args.candidate)} "
          f"({verdict['verdict']}; criterion 3 pending — human-gated "
          "iPhone 16 Pro measurement)")
    return 0 if verdict["verdict"] == "pending" else 1


if __name__ == "__main__":
    sys.exit(main())
