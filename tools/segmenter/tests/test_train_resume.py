"""Tests for train.py --resume (specs/estimation/resumable-segmenter-training).

The rest of this suite runs torch-free (see conftest.py); resume behaviour
exercises the real training loop, so the whole module skips unless torch and
torchvision are installed (the tools/segmenter/.venv from docs/ml-training.md §1).

The happy path simulates an interrupt by making the final checkpoint save raise:
the per-epoch sidecar written before the "crash" must survive (a completed run
deletes it — smolspec requirement), then a --resume invocation continues the
epoch sequence, produces an export.load_checkpoint-compatible artifact, and
cleans the sidecar up.
"""

from __future__ import annotations

import json

import pytest

torch = pytest.importorskip("torch")
pytest.importorskip("torchvision")

import export  # noqa: E402  (sys.path set up by conftest.py)
import train  # noqa: E402

# Small enough for seconds-scale CPU epochs; ASPP tolerates 64 (bump to 128 if
# a torchvision upgrade ever rejects it — smolspec risk note).
TARGET_SIZE = 64
NUM_CLASSES = 8


@pytest.fixture
def dataset_root(tmp_path):
    """Tiny PIL-generated train split (2 image/mask pairs); no val split."""
    from PIL import Image
    import numpy as np

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


def _argv(data_root, out, epochs, **overrides):
    opts = {
        "--data": str(data_root),
        "--num-classes": str(NUM_CLASSES),
        "--target-size": str(TARGET_SIZE),
        "--epochs": str(epochs),
        "--batch-size": "2",
        "--lr": "1e-3",
        "--out": str(out),
        "--limit": "2",
        "--num-workers": "0",
        "--device": "cpu",
    }
    opts.update(overrides)
    argv = ["--no-pretrained"]
    for flag, value in opts.items():
        argv += [flag, value]
    return argv


def _sidecar_for(out):
    return out.parent / (out.name + ".resume.pt")


def test_interrupt_then_resume_completes_run(dataset_root, tmp_path, monkeypatch, capsys):
    out = tmp_path / "checkpoint.pt"
    sidecar = _sidecar_for(out)

    # --- epoch 1, interrupted before the final save: sidecar must survive ---
    def crash(*args, **kwargs):
        raise RuntimeError("simulated interrupt before final save")

    monkeypatch.setattr(train, "_save_checkpoint", crash)
    with pytest.raises(RuntimeError, match="simulated interrupt"):
        train.main(_argv(dataset_root, out, epochs=1))
    monkeypatch.undo()

    assert sidecar.is_file(), "per-epoch sidecar missing after interrupted run"
    state = torch.load(sidecar, map_location="cpu")
    assert state["epoch"] == 1
    assert state["num_classes"] == NUM_CLASSES
    assert state["target_size"] == TARGET_SIZE
    assert state["palette_version"] == train.PALETTE_VERSION
    assert state["pretrained"] is False
    assert "optimizer" in state
    capsys.readouterr()  # drop interrupted-run output

    # --- resume to --epochs 2: only epoch 2 runs ---
    rc = train.main(_argv(dataset_root, out, epochs=2, **{"--resume": str(sidecar)}))
    assert rc == 0
    output = capsys.readouterr().out
    assert "epoch 2/2" in output
    assert "epoch 1/2" not in output

    # Final artifact stays byte-compatible with the export path.
    model = export.load_checkpoint(NUM_CLASSES, str(out))
    assert model is not None
    checkpoint = torch.load(out, map_location="cpu")
    assert checkpoint["pretrained"] is False  # carried from the sidecar

    # Lineage records the resume so provenance never claims one uninterrupted run.
    lineage = json.loads((out.parent / "lineage.json").read_text())
    assert lineage["train_config"]["resumed_from_epoch"] == 1

    # Completed run leaves no stale state.
    assert not sidecar.exists()


def test_resume_rejects_hyperparameter_mismatch(dataset_root, tmp_path, monkeypatch):
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
            "pretrained": False,
            "last_food_class_miou": float("nan"),
        },
        sidecar,
    )

    # Validation must happen BEFORE the model is built (smolspec requirement).
    def built_too_early(*args, **kwargs):
        pytest.fail("build_model called before sidecar validation")

    monkeypatch.setattr(train, "build_model", built_too_early)

    with pytest.raises(SystemExit) as excinfo:
        train.main(
            _argv(
                dataset_root, out, epochs=2,
                **{"--resume": str(sidecar), "--num-classes": str(NUM_CLASSES + 1)},
            )
        )
    message = str(excinfo.value.code)
    assert excinfo.value.code != 0
    assert message.startswith("[train]")
    assert str(NUM_CLASSES) in message  # sidecar value
    assert str(NUM_CLASSES + 1) in message  # invocation value


def test_missing_resume_file_exits_with_train_message(dataset_root, tmp_path):
    out = tmp_path / "checkpoint.pt"
    with pytest.raises(SystemExit) as excinfo:
        train.main(
            _argv(dataset_root, out, epochs=1, **{"--resume": str(tmp_path / "nope.pt")})
        )
    assert excinfo.value.code != 0
    assert str(excinfo.value.code).startswith("[train]")


def test_refuses_to_start_over_existing_sidecar(dataset_root, tmp_path):
    out = tmp_path / "checkpoint.pt"
    sidecar = _sidecar_for(out)
    sidecar.write_bytes(b"stale interrupted-run state")

    with pytest.raises(SystemExit) as excinfo:
        train.main(_argv(dataset_root, out, epochs=1))
    assert excinfo.value.code != 0
    message = str(excinfo.value.code)
    assert message.startswith("[train]")
    assert "--resume" in message
