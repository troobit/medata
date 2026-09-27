"""Tests for train.py --boundary-weight (MD-29 re-scope to mask quality:
boundary F at 2 px sat at 0.45–0.46 for every recipe tried, so the per-pixel
CE term is told about edges).

Skips without torch/torchvision like test_train_seed.py; runs one CPU epoch at
the toy size. The map arithmetic is covered torch-free in test_loss_config.py;
this checks the wiring — the Dataset yields a third tensor only when the flag
is on, the weighted reduction collapses to the plain one under an all-ones
map, the flags reach the checkpoint and lineage, and the resume drift-check
rejects a mismatch.
"""

from __future__ import annotations

import json

import pytest

torch = pytest.importorskip("torch")
pytest.importorskip("torchvision")

import loss_config
import train
from test_train_resume import NUM_CLASSES, TARGET_SIZE, _argv, _sidecar_for


@pytest.fixture
def dataset_root(tmp_path):
    """Same tiny PIL-generated train split as test_train_resume.py."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed=0)
    split = tmp_path / "data" / "train"
    (split / "images").mkdir(parents=True)
    (split / "masks").mkdir(parents=True)
    for i in range(2):
        rgb = rng.integers(0, 256, (TARGET_SIZE, TARGET_SIZE, 3), dtype=np.uint8)
        Image.fromarray(rgb, "RGB").save(split / "images" / f"img{i}.png")
        ids = rng.integers(0, NUM_CLASSES, (TARGET_SIZE, TARGET_SIZE), dtype=np.uint8)
        Image.fromarray(ids, "L").save(split / "masks" / f"img{i}.png")
    return tmp_path / "data"


def test_dataset_yields_a_third_tensor_only_with_the_flag(dataset_root):
    plain = train.FoodSegDataset(dataset_root / "train", TARGET_SIZE)
    assert len(plain[0]) == 2
    weighted = train.FoodSegDataset(dataset_root / "train", TARGET_SIZE,
                                    boundary_weight=3.0, boundary_band_px=1)
    _image, mask, weights = weighted[0]
    assert weights.dtype == torch.float32 and weights.shape == mask.shape
    assert set(weights.unique().tolist()) <= {1.0, 3.0}


@pytest.mark.parametrize("loss,weighting", [
    ("ce", "none"), ("combined", "none"), ("combined", "sqrt_inverse"),
    ("focal", "none"), ("weighted_ce", "sqrt_inverse"),
])
def test_all_ones_map_reproduces_the_plain_reduction(loss, weighting):
    torch.manual_seed(0)
    logits = torch.randn(2, NUM_CLASSES, 8, 8)
    targets = torch.randint(0, NUM_CLASSES, (2, 8, 8))
    spec = loss_config.resolve_loss_spec(loss, class_weighting=weighting)
    weights = None
    if loss_config.loss_uses_class_weights(loss, weighting):
        weights = [1.0 + 0.1 * c for c in range(NUM_CLASSES)]
    plain = train._build_criterion(spec, weights, torch.device("cpu"))
    boundary = train._build_criterion(spec, weights, torch.device("cpu"), boundary=True)
    ones = torch.ones(2, 8, 8)
    assert boundary(logits, targets, ones).item() == pytest.approx(
        plain(logits, targets).item(), rel=1e-5)
    # A non-uniform map changes the value: the term is not silently ignored.
    bumped = ones.clone()
    bumped[:, :4] = 3.0
    assert boundary(logits, targets, bumped).item() != pytest.approx(
        plain(logits, targets).item(), rel=1e-5)


def test_flags_land_in_checkpoint_and_lineage(dataset_root, tmp_path):
    out = tmp_path / "a" / "checkpoint.pt"
    argv = _argv(dataset_root, out, epochs=1,
                 **{"--boundary-weight": "3", "--loss": "combined", "--seed": "3"})
    assert train.main(argv) == 0
    checkpoint = torch.load(out, map_location="cpu")
    lineage = json.loads((out.parent / "lineage.json").read_text())
    assert checkpoint["boundary_weight"] == 3.0
    assert checkpoint["boundary_band_px"] == loss_config.DEFAULT_BOUNDARY_BAND_PX
    assert checkpoint["seed"] == 3 and checkpoint["loss"] == "combined"
    assert lineage["train_config"]["boundary_weight"] == 3.0
    assert lineage["train_config"]["boundary_band_px"] == loss_config.DEFAULT_BOUNDARY_BAND_PX


def test_omitted_flag_records_nothing(dataset_root, tmp_path):
    out = tmp_path / "checkpoint.pt"
    assert train.main(_argv(dataset_root, out, epochs=1)) == 0
    checkpoint = torch.load(out, map_location="cpu")
    lineage = json.loads((out.parent / "lineage.json").read_text())
    assert "boundary_weight" not in checkpoint
    assert "boundary_band_px" not in checkpoint
    assert "boundary_weight" not in lineage["train_config"]
    assert "boundary_band_px" not in lineage["train_config"]


def test_resume_rejects_boundary_weight_mismatch(dataset_root, tmp_path):
    out = tmp_path / "checkpoint.pt"
    sidecar = _sidecar_for(out)
    torch.save(
        {
            "model": {},
            "optimizer": {},
            "epoch": 1,
            "num_classes": NUM_CLASSES,
            "target_size": TARGET_SIZE,
            "palette_version": train.PALETTE_VERSION,
            "lr": 1e-3,
            "batch_size": 2,
            "augment": True,
            "loss": "ce",
            "photometric_augment": False,
            "init_checkpoint": None,
            "arch": "deeplab_mnv3",
            "class_weighting": "none",
            "seed": None,
            "pretrained": False,
            "last_food_class_miou": float("nan"),
            # No boundary keys: a legacy sidecar means off.
        },
        sidecar,
    )
    with pytest.raises(SystemExit, match="resume mismatch on boundary_weight"):
        train.main(_argv(dataset_root, out, epochs=2,
                         **{"--resume": str(sidecar), "--boundary-weight": "3"}))
