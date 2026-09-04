"""Build-lineage manifest tests (model-production task 3, Req 1.3)."""

import json

import pytest

import export  # torch-free import: heavy deps are lazy
import lineage


def test_model_version_is_first_12_hex_of_sha256(tmp_path):
    ckpt = tmp_path / "checkpoint.pt"
    ckpt.write_bytes(b"deterministic-bytes")
    sha = lineage.checkpoint_sha256(ckpt)
    assert len(sha) == 64
    assert lineage.model_version(sha) == sha[:12]
    assert len(lineage.model_version(sha)) == lineage.MODEL_VERSION_HEX_LEN == 12


def test_build_lineage_fields_and_class_mapping_defaults(tmp_path):
    ckpt = tmp_path / "checkpoint.pt"
    ckpt.write_bytes(b"x")
    manifest = lineage.build_lineage(
        ckpt, train_config={"epochs": 60, "lr": 1e-3}, split_seed=42,
    )
    assert manifest["checkpoint_sha256"] == lineage.checkpoint_sha256(ckpt)
    assert manifest["model_version"] == manifest["checkpoint_sha256"][:12]
    assert manifest["split_seed"] == 42
    assert manifest["train_config"] == {"epochs": 60, "lr": 1e-3}
    # Defaults sourced from the committed class-mapping file.
    assert manifest["palette_version"] == "v0"
    assert manifest["class_mapping_version"] == "foodseg103_to_palette"
    assert manifest["foodseg103_source"] == "FoodSeg103"
    # Metrics are placeholders until the validation step (task 9) fills them.
    assert manifest["metrics"] == {
        "mean_iou": None, "per_class_iou": None, "carb_priority_iou": None,
    }


def test_explicit_args_override_class_mapping_defaults(tmp_path):
    ckpt = tmp_path / "c.pt"
    ckpt.write_bytes(b"y")
    manifest = lineage.build_lineage(
        ckpt, train_config={}, foodseg103_source="FoodSeg103@abc",
        palette_version="v0", class_mapping_version="custom",
    )
    assert manifest["foodseg103_source"] == "FoodSeg103@abc"
    assert manifest["palette_version"] == "v0"
    assert manifest["class_mapping_version"] == "custom"


def test_write_lineage_round_trips(tmp_path):
    ckpt = tmp_path / "c.pt"
    ckpt.write_bytes(b"z")
    manifest = lineage.build_lineage(ckpt, train_config={})
    out = lineage.write_lineage(manifest, tmp_path / "build" / "lineage.json")
    assert out.is_file()
    assert json.loads(out.read_text())["model_version"] == manifest["model_version"]


def test_preserve_metrics_carries_recorded_metrics_for_same_checkpoint(tmp_path):
    ckpt = tmp_path / "checkpoint.pt"
    ckpt.write_bytes(b"same-model")
    recorded = lineage.build_lineage(ckpt, train_config={})
    recorded["metrics"] = {"mean_iou": 0.42, "export_eligible": False,
                           "release_override": {"allowed": True, "reason": "dev-phase",
                                                "authorised_by": "developer"}}
    path = tmp_path / "lineage.json"
    lineage.write_lineage(recorded, path)

    fresh = lineage.build_lineage(ckpt, train_config={})
    lineage.preserve_metrics(fresh, path)
    assert fresh["metrics"] == recorded["metrics"]


def test_preserve_metrics_ignores_a_different_checkpoint(tmp_path):
    old = tmp_path / "old.pt"
    old.write_bytes(b"old-model")
    recorded = lineage.build_lineage(old, train_config={})
    recorded["metrics"] = {"mean_iou": 0.42}
    path = tmp_path / "lineage.json"
    lineage.write_lineage(recorded, path)

    new = tmp_path / "new.pt"
    new.write_bytes(b"new-model")
    fresh = lineage.build_lineage(new, train_config={})
    lineage.preserve_metrics(fresh, path)
    assert fresh["metrics"] == lineage.empty_metrics()


def test_preserve_metrics_tolerates_missing_or_corrupt_file(tmp_path):
    ckpt = tmp_path / "checkpoint.pt"
    ckpt.write_bytes(b"m")
    fresh = lineage.build_lineage(ckpt, train_config={})
    lineage.preserve_metrics(fresh, tmp_path / "absent.json")
    corrupt = tmp_path / "corrupt.json"
    corrupt.write_text("{not json")
    lineage.preserve_metrics(fresh, corrupt)
    assert fresh["metrics"] == lineage.empty_metrics()


# ── pretrained_checkpoint + co_stats_sha256 (segmenter-foundation task 12) ──────

def test_lineage_round_trips_pretrained_checkpoint_and_co_stats(tmp_path):
    ckpt = tmp_path / "c.pt"
    ckpt.write_bytes(b"recipe-upgraded")
    pretrained = {
        "source_url": "https://download.pytorch.org/models/mobilenet_v3_large-5c1a4163.pth",
        "licence": "BSD-3-Clause",
        "sha256": "5c1a4163" + "0" * 56,
    }
    manifest = lineage.build_lineage(
        ckpt, train_config={},
        pretrained_checkpoint=pretrained,
        co_stats_sha256="cd" * 32,
    )
    out = lineage.write_lineage(manifest, tmp_path / "build" / "lineage.json")
    loaded = json.loads(out.read_text())
    assert loaded["pretrained_checkpoint"] == pretrained
    assert loaded["co_stats_sha256"] == "cd" * 32


def test_lineage_new_fields_default_to_null(tmp_path):
    ckpt = tmp_path / "c.pt"
    ckpt.write_bytes(b"plain")
    manifest = lineage.build_lineage(ckpt, train_config={})
    assert manifest["pretrained_checkpoint"] is None
    assert manifest["co_stats_sha256"] is None


def test_preserve_metrics_carries_provenance_fields_for_same_checkpoint(tmp_path):
    ckpt = tmp_path / "c.pt"
    ckpt.write_bytes(b"same-model")
    recorded = lineage.build_lineage(
        ckpt, train_config={},
        pretrained_checkpoint={"source_url": "u", "licence": "MIT", "sha256": "s"},
        co_stats_sha256="ef" * 32,
    )
    path = tmp_path / "lineage.json"
    lineage.write_lineage(recorded, path)

    # A re-export (emit_lineage) rebuilds with nulls; the recorded training-run
    # provenance must survive for the identical checkpoint SHA.
    fresh = lineage.build_lineage(ckpt, train_config={})
    lineage.preserve_metrics(fresh, path)
    assert fresh["pretrained_checkpoint"] == recorded["pretrained_checkpoint"]
    assert fresh["co_stats_sha256"] == "ef" * 32


def test_file_sha256_matches_checkpoint_sha256(tmp_path):
    f = tmp_path / "co_stats.json"
    f.write_bytes(b"{}")
    assert lineage.file_sha256(f) == lineage.checkpoint_sha256(f)


# ── emit_lineage recipe reconstruction (torch-gated) ────────────────────────────

def test_emit_lineage_preserves_recipe_keys_from_the_checkpoint(tmp_path):
    """A re-export must reconstruct the FULL recipe train_config from the
    checkpoint's top-level provenance keys (train.py _save_checkpoint
    recipe_extras) — notably the weighting scheme — not just the historical
    subset, or a re-exported lineage would silently drop the recipe."""
    torch = pytest.importorskip("torch")

    ckpt = tmp_path / "checkpoint.pt"
    torch.save(
        {
            "model": {},
            "num_classes": 35,
            "target_size": 513,
            "palette_version": "stale",
            "epochs": 60,
            "lr": 1e-3,
            "lr_schedule": "poly",
            "augment": True,
            "pretrained": True,
            "loss": "combined",
            "dice_weight": 0.5,
            "weighting": "sqrt_inverse",
            "photometric_augment": True,
            "init_checkpoint": "build/init.pt",
        },
        ckpt,
    )
    out = tmp_path / "lineage.json"
    export.emit_lineage(str(ckpt), str(out))
    config = json.loads(out.read_text())["train_config"]
    assert config["loss"] == "combined"
    assert config["weighting"] == "sqrt_inverse"
    assert config["dice_weight"] == 0.5
    assert config["photometric_augment"] is True
    assert config["init_checkpoint"] == "build/init.pt"
    # The historical keys still come through alongside the recipe.
    assert config["epochs"] == 60
    assert config["augment"] is True
