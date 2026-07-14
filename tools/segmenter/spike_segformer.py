#!/usr/bin/env python3
"""SegFormer-B0 Core ML conversion spike — the AUTONOMOUS half (criteria 1, 2, 4).

segmenter-foundation design §5.1–5.2 (Decisions 7, 16), Reqs 3.1/3.2. Answers,
in order, stopping at the first failure:

  1. Converts to Core ML?      coremltools.convert() of a public SegFormer-B0
                               checkpoint (accuracy irrelevant — only conversion
                               mechanics are measured) with a 35-channel head
                               grafted on, FP16, 513x513 input. A hard
                               conversion failure (unsupported op) ends the
                               spike immediately (Req 3.2).
  2. FP16 artefact <= 24 MiB?  export.py WEIGHTS_MAX_BYTES — the same budget
                               the shipping model is gated on.
  3. <= 250 ms ANE-resident?   NOT MEASURED HERE. Human-gated: Xcode Core ML
                               performance report on the iPhone 16 Pro
                               (v1 hardware floor, Decision 16). Recorded as
                               null/pending in the verdict JSON.
  4. Matches PyTorch outputs?  The existing equivalence oracle — export.py
                               oracle_agreement() thresholds (argmax > 99%,
                               max abs logit error < 0.5, model-production
                               Req 4.3 as amended; Decision 7 records the
                               reuse). If SegFormer's attention numerics show
                               materially different FP16 drift, log the
                               deviation — do not widen the thresholds here.

The verdict JSON (default ``tools/segmenter/build/spike_segformer.json``)
carries the four criterion booleans (criterion 3 null until the human-gated
half runs) plus the measured numbers; the decision-log entry transcribes it.
BOTH halves are required before any spike verdict is logged — completing only
this half is "incomplete", not "pass" (design §5.2).

Usage::

    pip install -r tools/segmenter/requirements.txt   # transformers is spike-only
    python tools/segmenter/spike_segformer.py \\
        --checkpoint nvidia/segformer-b0-finetuned-ade-512-512 \\
        --out tools/segmenter/build/spike_segformer.mlpackage \\
        --verdict tools/segmenter/build/spike_segformer.json

Heavy deps (torch, transformers, coremltools) are imported lazily so ``--help``
and the verdict-assembly unit tests run without them installed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Optional

# Public SegFormer-B0 checkpoint for the spike. ADE20K-finetuned — the task is
# irrelevant (the head is re-grafted to 35 channels anyway); what matters is
# that the MiT-B0 encoder graph is the real one (overlap patch embedding +
# spatial-reduction attention, the ops with the least Core ML precedent).
DEFAULT_CHECKPOINT = "nvidia/segformer-b0-finetuned-ade-512-512"

# The shipping contract the candidate must slot into (pipeline Decision 11):
# 513x513 input, 35-channel logits.
TARGET_SIZE = 513
NUM_CLASSES = 35

DEFAULT_MLPACKAGE = "tools/segmenter/build/spike_segformer.mlpackage"
DEFAULT_VERDICT = "tools/segmenter/build/spike_segformer.json"

VERDICT_SCHEMA = "spike_segformer.v1"

# Explanation stamped on criterion 3 while it is pending (design §5.2,
# Decision 16): needs Xcode's Core ML performance report on the physical
# iPhone 16 Pro (floor per Decision 22) — not runnable from this script.
LATENCY_PENDING_NOTE = (
    "criterion 3 (<= 250 ms per 513x513 inference, ANE-resident) is "
    "human-gated: measure with Xcode's Core ML performance report on the "
    "iPhone 16 Pro (v1 hardware floor, Decision 22), then record the "
    "result in the decision log alongside this JSON"
)


def _load_export_module():
    """Import the sibling export.py by NAME via sys.path (the loss_config
    pattern) so the spike reuses the SAME module instance — and hence the same
    budget constant, oracle helpers, and ExportGateError class — the shipping
    model is gated on (WEIGHTS_MAX_BYTES, reference_input, oracle_agreement;
    Decision 7)."""
    tools_dir = str(Path(__file__).resolve().parent)
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    import export
    return export


def _import_heavy():
    """torch + transformers + coremltools, or a clear install message."""
    try:
        import torch
        import coremltools as ct
        from transformers import SegformerForSemanticSegmentation
    except ImportError as exc:
        raise SystemExit(
            "The spike needs torch, coremltools and transformers (spike-only "
            "dependency). Install with:\n"
            "  pip install -r tools/segmenter/requirements.txt"
        ) from exc
    return torch, ct, SegformerForSemanticSegmentation


# ── Pure helpers (unit-tested without the heavy deps) ───────────────────────────

def artefact_within_budget(path: str | Path, max_bytes: Optional[int] = None
                           ) -> tuple[bool, int, int]:
    """Criterion 2: FP16 artefact size against export.py's WEIGHTS_MAX_BYTES.

    Returns ``(ok, measured_bytes, budget_bytes)``. ``max_bytes`` overrides the
    budget for tests only — the spike itself always uses the shipping budget.
    """
    export = _load_export_module()
    budget = export.WEIGHTS_MAX_BYTES if max_bytes is None else max_bytes
    size = export.mlpackage_weight_bytes(str(path))
    return size <= budget, size, budget


def assemble_verdict(
    *,
    checkpoint: str,
    converts: bool,
    artefact_bytes: Optional[int] = None,
    budget_bytes: Optional[int] = None,
    size_ok: Optional[bool] = None,
    oracle_max_abs_err: Optional[float] = None,
    oracle_argmax_agreement: Optional[float] = None,
    oracle_ok: Optional[bool] = None,
    notes: Optional[list[str]] = None,
) -> dict[str, Any]:
    """Assemble the verdict JSON (design §5.2): four criterion booleans plus
    measurements. Stop-on-fail semantics are encoded as ``None`` for criteria
    never reached (a failed conversion leaves 2 and 4 null, not false);
    criterion 3 (latency) is ALWAYS null here — it is the human-gated half.
    """
    if not converts:
        size_ok = None
        oracle_ok = None
    return {
        "schema": VERDICT_SCHEMA,
        "checkpoint": checkpoint,
        "target_size": TARGET_SIZE,
        "num_classes": NUM_CLASSES,
        "criteria": {
            "1_converts_to_coreml": converts,
            "2_fp16_artefact_within_budget": size_ok,
            "3_latency_ane_resident": None,  # pending — human-gated half
            "4_matches_pytorch_oracle": oracle_ok,
        },
        "measurements": {
            "artefact_bytes": artefact_bytes,
            "weights_max_bytes": budget_bytes,
            "oracle_max_abs_err": oracle_max_abs_err,
            "oracle_argmax_agreement": oracle_argmax_agreement,
        },
        "notes": [LATENCY_PENDING_NOTE] + (notes or []),
    }


def write_verdict(verdict: dict[str, Any], path: str | Path) -> Path:
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(verdict, indent=2) + "\n", encoding="utf-8")
    return out


# ── Heavy half (needs torch + transformers + coremltools) ───────────────────────

def _load_spike_model(checkpoint: str):
    """Load SegFormer-B0 and graft a 35-channel head (design §5.1: the public
    checkpoint's task/accuracy is irrelevant; the conversion mechanics of the
    MiT-B0 graph are what the spike measures). Returns a module whose forward
    yields the raw logits tensor (H/4 x W/4 — SegFormer's native output
    stride; the oracle compares like with like on both sides)."""
    torch, _, SegformerForSemanticSegmentation = _import_heavy()

    model = SegformerForSemanticSegmentation.from_pretrained(checkpoint)
    head = model.decode_head.classifier
    model.decode_head.classifier = torch.nn.Conv2d(
        head.in_channels, NUM_CLASSES, kernel_size=1
    )
    model.eval()

    class LogitsOnly(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            return self.m(pixel_values=x).logits

    return LogitsOnly(model).eval()


def run_spike(checkpoint: str, out_mlpackage: str, verdict_path: str,
              reference_image: Optional[str] = None) -> dict[str, Any]:
    """Criteria 1, 2 and 4 in order, stop-on-fail; writes the verdict JSON."""
    import numpy as np

    torch, ct, _ = _import_heavy()
    export = _load_export_module()
    notes: list[str] = []

    wrapped = _load_spike_model(checkpoint)

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
    except Exception as exc:  # a hard conversion failure ends the spike (Req 3.2)
        notes.append(f"conversion failed: {type(exc).__name__}: {exc}")
        verdict = assemble_verdict(checkpoint=checkpoint, converts=False,
                                   notes=notes)
        write_verdict(verdict, verdict_path)
        print(f"[spike] criterion 1 FAILED — {exc}", file=sys.stderr)
        return verdict
    print(f"[spike] criterion 1 ok — converted to {out_mlpackage}")

    # ── Criterion 2: FP16 artefact within the shipping budget? ───────────────
    size_ok, size, budget = artefact_within_budget(out_mlpackage)
    print(f"[spike] criterion 2 {'ok' if size_ok else 'FAILED'} — "
          f"{size} bytes (budget {budget})")
    if not size_ok:
        verdict = assemble_verdict(checkpoint=checkpoint, converts=True,
                                   artefact_bytes=size, budget_bytes=budget,
                                   size_ok=False, notes=notes)
        write_verdict(verdict, verdict_path)
        return verdict

    # ── Criterion 4: equivalence oracle (Decision 7 reuse) ───────────────────
    x = export.reference_input(TARGET_SIZE, reference_image)
    oracle_out = export.run_pytorch(wrapped, x)
    coreml_out = export.run_coreml(out_mlpackage, x)
    err, agree, oracle_ok = export.oracle_agreement(oracle_out, coreml_out)
    print(f"[spike] criterion 4 {'ok' if oracle_ok else 'FAILED'} — "
          f"max abs err = {err:.4f}, argmax agree = {agree:.4f}")
    if not oracle_ok:
        notes.append(
            "oracle mismatch — if attention numerics show materially "
            "different FP16 drift, log the deviation (design §5.1.4); do not "
            "widen the thresholds"
        )

    verdict = assemble_verdict(
        checkpoint=checkpoint, converts=True,
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
    parser.add_argument("--checkpoint", default=DEFAULT_CHECKPOINT,
                        help="Public SegFormer-B0 checkpoint (HF id or local "
                             "path); the task it was finetuned on is "
                             "irrelevant to the spike.")
    parser.add_argument("--out", default=DEFAULT_MLPACKAGE,
                        help="Where to save the converted .mlpackage.")
    parser.add_argument("--verdict", default=DEFAULT_VERDICT,
                        help="Where to write the verdict JSON that the "
                             "decision-log entry transcribes.")
    parser.add_argument("--reference-image", default=None,
                        help="Optional image for the equivalence oracle; "
                             "otherwise a deterministic synthetic input is "
                             "used (export.reference_input).")
    args = parser.parse_args(argv)

    verdict = run_spike(args.checkpoint, args.out, args.verdict,
                        args.reference_image)
    criteria = verdict["criteria"]
    autonomous_pass = (
        criteria["1_converts_to_coreml"]
        and criteria["2_fp16_artefact_within_budget"]
        and criteria["4_matches_pytorch_oracle"]
    )
    print(f"[spike] verdict -> {args.verdict} "
          f"(autonomous half {'PASS' if autonomous_pass else 'FAIL'}; "
          "criterion 3 pending on-device measurement)")
    return 0 if autonomous_pass else 1


if __name__ == "__main__":
    sys.exit(main())
