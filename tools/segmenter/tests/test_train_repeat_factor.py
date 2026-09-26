"""Tests for train.py --repeat-factor-threshold (estimation-quality, segmenter
training pipeline task 15: LVIS repeat-factor sampling, research note §4.4).

Skips without torch/torchvision like test_train_seed.py; runs one CPU epoch at
the toy size. The pure arithmetic is covered torch-free in test_loss_config.py;
this checks the wiring — the flag reaches the checkpoint and lineage, the
presence cache is written and reused, and the resume drift-check rejects a
mismatch.
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


@pytest.fixture(autouse=True)
def presence_cache(tmp_path, monkeypatch):
    """Keep the presence cache out of tools/segmenter/build during tests."""
    cache_dir = tmp_path / "class_presence"
    monkeypatch.setattr(train, "PRESENCE_CACHE_DIR", cache_dir)
    return cache_dir


def test_flag_lands_in_checkpoint_and_lineage_and_cache_is_reused(
        dataset_root, tmp_path, presence_cache, capsys):
    out = tmp_path / "a" / "checkpoint.pt"
    argv = _argv(dataset_root, out, epochs=1,
                 **{"--repeat-factor-threshold": "0.9", "--seed": "3"})
    assert train.main(argv) == 0
    checkpoint = torch.load(out, map_location="cpu")
    lineage = json.loads((out.parent / "lineage.json").read_text())
    assert checkpoint["repeat_factor_threshold"] == 0.9
    assert checkpoint["seed"] == 3
    assert lineage["train_config"]["repeat_factor_threshold"] == 0.9
    assert "scanned 2 train masks" in capsys.readouterr().out
    assert len(list(presence_cache.glob("*.json"))) == 1

    # Second run reads the cache instead of rescanning.
    out2 = tmp_path / "b" / "checkpoint.pt"
    assert train.main(_argv(dataset_root, out2, epochs=1,
                            **{"--repeat-factor-threshold": "0.9"})) == 0
    assert "class presence from cache" in capsys.readouterr().out


def test_omitted_flag_records_nothing(dataset_root, tmp_path):
    out = tmp_path / "checkpoint.pt"
    assert train.main(_argv(dataset_root, out, epochs=1)) == 0
    checkpoint = torch.load(out, map_location="cpu")
    lineage = json.loads((out.parent / "lineage.json").read_text())
    assert "repeat_factor_threshold" not in checkpoint
    assert "repeat_factor_threshold" not in lineage["train_config"]


def test_resume_rejects_repeat_factor_threshold_mismatch(dataset_root, tmp_path):
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
            # No repeat_factor_threshold key: a legacy sidecar means off.
        },
        sidecar,
    )
    with pytest.raises(SystemExit, match="resume mismatch on repeat_factor_threshold"):
        train.main(_argv(dataset_root, out, epochs=2,
                         **{"--resume": str(sidecar),
                            "--repeat-factor-threshold": "0.9"}))
