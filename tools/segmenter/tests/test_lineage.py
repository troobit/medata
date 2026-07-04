"""Build-lineage manifest tests (model-production task 3, Req 1.3)."""

import json

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
    assert manifest["palette_version"] == "v1"
    assert manifest["class_mapping_version"] == "foodseg103_to_palette_v1"
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
        palette_version="v2", class_mapping_version="custom",
    )
    assert manifest["foodseg103_source"] == "FoodSeg103@abc"
    assert manifest["palette_version"] == "v2"
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
