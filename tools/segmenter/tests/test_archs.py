"""Architecture-registry tests (snaq-parity task 17, design lane C / Decision 12+14).

The registry (``archs.py``) is the single seam through which train.py,
export.load_checkpoint, and run_validation.py build models, load checkpoints,
and normalise forward outputs — without it a bake-off winner could be trained
but never judged or exported (snaq-parity Decision 14). Contract per arch:
model constructor, checkpoint loader, and a forward-output normaliser to the
``["out"]``-at-input-resolution convention.

The registry surface, lineage resolution, and consumer delegation run
torch-free (the loss_config pattern); the deeplab_mnv3 parity and the
plain-tensor upsampling normaliser are torch-gated per test.
"""

from __future__ import annotations

import json

import pytest

import archs
import export
import run_validation
import train  # torch-free import: heavy deps are lazy


# ── Registry surface (torch-free) ───────────────────────────────────────────────

def test_default_arch_is_deeplab_mnv3():
    assert archs.DEFAULT_ARCH == "deeplab_mnv3"
    assert "deeplab_mnv3" in archs.ARCH_CHOICES


def test_get_returns_the_full_per_arch_contract():
    spec = archs.get("deeplab_mnv3")
    assert spec.name == "deeplab_mnv3"
    assert callable(spec.build)            # (num_classes, pretrained) -> model
    assert callable(spec.load_checkpoint)  # (num_classes, path|None) -> model
    assert callable(spec.forward_logits)   # (model, images) -> [B, C, H, W] logits
    assert spec.output == "dict_out"       # torchvision {"out": ...} convention


def test_unknown_arch_is_rejected_by_name():
    with pytest.raises(ValueError, match="segnet"):
        archs.get("segnet")


def test_normalise_arch_name_defaults_none():
    assert archs.normalise_arch_name(None) == archs.DEFAULT_ARCH
    assert archs.normalise_arch_name("deeplab_mnv3") == "deeplab_mnv3"


# ── Fixture-arch registration (the seam the bake-off winner lands through) ──────

def _fixture_spec(name="fixture_arch", **overrides):
    fields = dict(
        name=name,
        output="plain_tensor",
        build=lambda num_classes, pretrained: ("built", num_classes, pretrained),
        load_checkpoint=lambda num_classes, path: ("loaded", num_classes, path),
        forward_logits=lambda model, images: ("logits", model),
    )
    fields.update(overrides)
    return archs.ArchSpec(**fields)


def test_register_makes_a_fixture_arch_retrievable():
    spec = _fixture_spec()
    archs.register(spec)
    try:
        assert archs.get("fixture_arch") is spec
        assert "fixture_arch" in archs.ARCH_CHOICES
    finally:
        archs.unregister("fixture_arch")
    assert "fixture_arch" not in archs.ARCH_CHOICES


def test_register_rejects_a_duplicate_name():
    with pytest.raises(ValueError, match="deeplab_mnv3"):
        archs.register(_fixture_spec(name="deeplab_mnv3"))


# ── Lineage / checkpoint arch resolution (torch-free) ───────────────────────────

def test_arch_resolves_from_lineage_train_config():
    manifest = {"train_config": {"arch": "fixture_arch", "epochs": 60}}
    assert archs.arch_from_lineage(manifest) == "fixture_arch"


def test_absent_arch_in_lineage_means_the_default():
    # Every pre-registry lineage was a deeplab_mnv3 run; absence is not unknown.
    assert archs.arch_from_lineage({"train_config": {"epochs": 60}}) == "deeplab_mnv3"
    assert archs.arch_from_lineage({}) == "deeplab_mnv3"


def test_checkpoint_arch_stamp_reads_presence_and_absence(tmp_path):
    torch = pytest.importorskip("torch")

    stamped = tmp_path / "stamped.pt"
    torch.save({"model": {}, "arch": "fixture_arch"}, stamped)
    assert archs.checkpoint_arch_stamp(stamped) == "fixture_arch"
    assert archs.arch_from_checkpoint(stamped) == "fixture_arch"

    # Absence of the key — or of the file — is a None stamp; arch_from_checkpoint
    # maps that to the historical deeplab_mnv3.
    legacy = tmp_path / "legacy.pt"
    torch.save({"model": {}}, legacy)
    assert archs.checkpoint_arch_stamp(legacy) is None
    assert archs.arch_from_checkpoint(legacy) == "deeplab_mnv3"
    assert archs.checkpoint_arch_stamp(None) is None
    assert archs.checkpoint_arch_stamp(tmp_path / "missing.pt") is None


def test_run_validation_rejects_stale_lineage_arch_mismatch(tmp_path):
    """export.py resolves the arch from the checkpoint's own stamp while
    run_validation resolves from lineage — a stale lineage beside a
    non-default-arch checkpoint would build the wrong model and strict=False
    would silently load nothing, so the disagreement must fail fast."""
    torch = pytest.importorskip("torch")

    checkpoint = tmp_path / "checkpoint.pt"
    torch.save({"model": {}, "arch": "fixture_arch"}, checkpoint)
    lineage_path = tmp_path / "lineage.json"
    lineage_path.write_text(json.dumps({"train_config": {}}))  # → deeplab_mnv3

    with pytest.raises(SystemExit) as excinfo:
        run_validation.main(["--checkpoint", str(checkpoint),
                             "--lineage", str(lineage_path)])
    message = str(excinfo.value.code)
    assert message.startswith("[validate]")
    assert "fixture_arch" in message
    assert "deeplab_mnv3" in message


# ── Consumer delegation (torch-free, via a registered fixture arch) ─────────────

def test_export_load_checkpoint_delegates_to_the_registry(monkeypatch):
    spec = _fixture_spec()
    archs.register(spec)
    try:
        model = export.load_checkpoint(35, None, arch="fixture_arch")
        assert model == ("loaded", 35, None)
    finally:
        archs.unregister("fixture_arch")


def test_train_cli_lists_and_validates_arch(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--help"])
    assert excinfo.value.code == 0
    assert "--arch" in capsys.readouterr().out

    with pytest.raises(SystemExit) as excinfo:
        train.main(["--arch", "segnet"])
    assert excinfo.value.code == 2  # argparse choice error, not a torch ImportError
    assert "--arch" in capsys.readouterr().err


# ── deeplab_mnv3 parity (torch-gated) ───────────────────────────────────────────

def test_deeplab_build_matches_the_reference_construction():
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    from torchvision.models.segmentation import deeplabv3_mobilenet_v3_large
    from torchvision.models.segmentation.deeplabv3 import DeepLabHead

    # The reference is the pre-registry construction (export.py load_checkpoint /
    # train._build_uninitialised): torchvision model, head swapped for 35 classes.
    reference = deeplabv3_mobilenet_v3_large(weights=None, aux_loss=False)
    in_ch = reference.classifier[0].convs[0][0].in_channels
    reference.classifier = DeepLabHead(in_ch, 35)

    built = archs.get("deeplab_mnv3").build(35, pretrained=False)

    ref_state = reference.state_dict()
    built_state = built.state_dict()
    assert set(built_state) == set(ref_state)
    assert all(built_state[k].shape == ref_state[k].shape for k in ref_state)


def test_deeplab_forward_logits_is_the_dict_out_convention():
    torch = pytest.importorskip("torch")

    class DictOut(torch.nn.Module):
        def forward(self, x):
            return {"out": x + 1.0, "aux": x}

    spec = archs.get("deeplab_mnv3")
    images = torch.zeros(1, 3, 4, 4)
    logits = spec.forward_logits(DictOut(), images)
    assert torch.equal(logits, images + 1.0)


# ── Plain-tensor normalisation (SegFormer-class architectures) ──────────────────

def test_plain_tensor_logits_upsamples_to_input_resolution():
    torch = pytest.importorskip("torch")

    class QuarterRes(torch.nn.Module):
        """SegFormer-style: plain tensor at input/4 spatial resolution."""
        def forward(self, x):
            b, _, h, w = x.shape
            return torch.randn(b, 35, h // 4, w // 4)

    images = torch.zeros(2, 3, 64, 64)
    logits = archs.plain_tensor_logits(QuarterRes(), images)
    assert logits.shape == (2, 35, 64, 64)


def test_plain_tensor_logits_passes_full_resolution_through():
    torch = pytest.importorskip("torch")

    class FullRes(torch.nn.Module):
        def forward(self, x):
            return x * 2.0

    images = torch.ones(1, 3, 8, 8)
    logits = archs.plain_tensor_logits(FullRes(), images)
    assert torch.equal(logits, images * 2.0)


# ── Resume drift-check and lineage gain the arch field (torch-gated) ────────────

TARGET_SIZE = 64
NUM_CLASSES = 35


def _sidecar_state():
    return {
        "model": {},
        "optimizer": {},
        "epoch": 1,
        "num_classes": NUM_CLASSES,
        "target_size": TARGET_SIZE,
        "palette_version": train.PALETTE_VERSION,
        "lr": 1e-3,
        "batch_size": 2,
        "augment": True,
        "pretrained": False,
        "last_food_class_miou": float("nan"),
    }


def _argv(tmp_path, out, **overrides):
    opts = {
        "--data": str(tmp_path / "data"),
        "--num-classes": str(NUM_CLASSES),
        "--target-size": str(TARGET_SIZE),
        "--epochs": "2",
        "--batch-size": "2",
        "--lr": "1e-3",
        "--out": str(out),
        "--num-workers": "0",
        "--device": "cpu",
    }
    opts.update(overrides)
    argv = ["--no-pretrained"]
    for flag, value in opts.items():
        argv += [flag, value]
    return argv


def test_resume_rejects_arch_drift(tmp_path, monkeypatch):
    torch = pytest.importorskip("torch")

    out = tmp_path / "checkpoint.pt"
    sidecar = out.parent / (out.name + ".resume.pt")
    state = _sidecar_state()
    state["arch"] = "deeplab_mnv3"
    torch.save(state, sidecar)

    monkeypatch.setattr(
        train, "build_model",
        lambda *a, **k: pytest.fail("build_model called before sidecar validation"),
    )
    archs.register(_fixture_spec())
    try:
        with pytest.raises(SystemExit) as excinfo:
            train.main(_argv(tmp_path, out,
                             **{"--resume": str(sidecar), "--arch": "fixture_arch"}))
    finally:
        archs.unregister("fixture_arch")
    assert "arch" in str(excinfo.value.code)


def test_legacy_sidecar_without_arch_means_deeplab(tmp_path):
    """A pre-registry sidecar (no arch key) must pass the drift check under the
    default arch — absence is the historical deeplab_mnv3, not drift."""
    import argparse

    torch = pytest.importorskip("torch")

    sidecar = tmp_path / "checkpoint.pt.resume.pt"
    torch.save(_sidecar_state(), sidecar)  # no "arch" key

    args = argparse.Namespace(
        resume=str(sidecar), num_classes=NUM_CLASSES, target_size=TARGET_SIZE,
        lr=1e-3, batch_size=2, no_augment=False, loss=None,
        photometric_augment=False, init_checkpoint=None,
        arch=archs.DEFAULT_ARCH, class_weighting="none",
    )
    state = train._load_resume_state(args)
    assert state["epoch"] == 1  # drift check passed; legacy default applied
