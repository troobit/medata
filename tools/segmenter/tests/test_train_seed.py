"""Tests for train.py --seed (estimation-quality, segmenter training pipeline
task 12: the R7 repeat measured per-class run-to-run noise of up to 0.45 IoU on
an identical recipe, so recipe comparisons need the trainer's own randomness
pinned).

Skips without torch/torchvision like test_train_resume.py; runs on CPU at a
toy size so each epoch is seconds. CPU kernels are deterministic, so two runs
with the same seed must produce byte-identical weights; the same pair on MPS
is what the seeded R8/R9 runs measure.
"""

from __future__ import annotations

import json

import pytest

torch = pytest.importorskip("torch")
pytest.importorskip("torchvision")

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


def _train_once(dataset_root, out, seed=None):
    overrides = {"--seed": str(seed)} if seed is not None else {}
    assert train.main(_argv(dataset_root, out, epochs=1, **overrides)) == 0
    checkpoint = torch.load(out, map_location="cpu")
    lineage = json.loads((out.parent / "lineage.json").read_text())
    return checkpoint, lineage


def test_same_seed_gives_identical_weights_and_records_the_seed(dataset_root, tmp_path):
    a, la = _train_once(dataset_root, tmp_path / "a" / "checkpoint.pt", seed=7)
    b, lb = _train_once(dataset_root, tmp_path / "b" / "checkpoint.pt", seed=7)
    for key, tensor in a["model"].items():
        assert torch.equal(tensor, b["model"][key]), f"{key} differs between same-seed runs"
    assert a["seed"] == 7 and b["seed"] == 7
    assert la["train_config"]["seed"] == 7
    assert lb["train_config"] == la["train_config"]


def test_unseeded_run_records_no_seed(dataset_root, tmp_path):
    checkpoint, lineage = _train_once(dataset_root, tmp_path / "checkpoint.pt")
    assert "seed" not in checkpoint
    assert "seed" not in lineage["train_config"]


def test_resume_rejects_seed_mismatch(dataset_root, tmp_path):
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
            "seed": 1,
            "pretrained": False,
            "last_food_class_miou": float("nan"),
        },
        sidecar,
    )
    with pytest.raises(SystemExit, match="resume mismatch on seed"):
        train.main(_argv(dataset_root, out, epochs=2,
                         **{"--resume": str(sidecar), "--seed": "2"}))
