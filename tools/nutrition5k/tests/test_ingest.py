"""Tests for tools/nutrition5k/ingest.py core (pre-checkpoint mode).

Req 1.1/1.2/1.4 + 3.1-3.8: depth conversion with fail-loud reference checks,
required-files CLI guard, skip+record on malformed plates, and fixture
emission (single_view_lidar, pinned nominal D435 intrinsics, gravity straight
down, mixture stamp with the sentinel SHA and no probabilities).

All tests run against a tiny synthetic N5k tree (conftest.make_n5k_tree) and
a mapping artifact keyed to the synthetic ingredient CSV — no gitignored
data/ needed.
"""

import importlib.util
import io
import json
import re
from pathlib import Path

import numpy as np
import pytest

import ingest
import mapping
from n5k_testkit import (
    REPO_ROOT,
    make_n5k_tree,
    make_test_mapping_artifact,
    plate_depth,
)

_SCHEMA_DIR = (
    REPO_ROOT / "MedataCore" / "Sources" / "PortableContracts" / "Schemas"
)


def _meal_fixture_pb():
    path = REPO_ROOT / "tools" / "segmenter" / "make_fixtures.py"
    spec = importlib.util.spec_from_file_location("segmenter_make_fixtures", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module._import_meal_fixture_pb(_SCHEMA_DIR)


def run_ingest(n5k_root: Path, out_dir: Path, artifact: Path,
               extra: list[str] | None = None) -> int:
    return ingest.main([
        "--n5k-dir", str(n5k_root),
        "--out", str(out_dir),
        "--mapping", str(artifact),
        "--download-date", "2026-07-02",
        *(extra or []),
    ])


@pytest.fixture()
def n5k(tmp_path):
    """Two-good-dish tree + matching mapping artifact + out dir."""
    root = make_n5k_tree(tmp_path / "data", {
        # 150 g white rice + 40 g broccoli + 10 g soy sauce (unmapped, 5% —
        # below the 0.10 significant fraction).
        "dish_1": {"ingredients": [(26, 150.0), (27, 40.0), (508, 10.0)]},
        "dish_2": {"ingredients": [(26, 200.0)]},
    })
    artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
    out = tmp_path / "out"
    return root, out, artifact


def load_summary(out_dir: Path) -> dict:
    return json.loads((out_dir / "run_summary.json").read_text())


def load_fixture(out_dir: Path, dish_id: str):
    pb = _meal_fixture_pb()
    fx = pb.MealFixture()
    fx.ParseFromString((out_dir / f"{dish_id}.fixture").read_bytes())
    return fx


# --------------------------------------------------------------------------- #
# Depth conversion (Req 3.1/3.2).
# --------------------------------------------------------------------------- #
class TestDepthConversion:
    def test_round_trips_exactly_on_the_full_integer_grid(self):
        raw = np.arange(65536, dtype=np.uint16)
        mm = ingest.convert_depth_raw_to_mm(raw)
        assert mm.dtype == np.float32
        valid = (raw > 0) & (raw < ingest.DEPTH_CAP_RAW)
        # raw -> mm = raw/10 -> raw round-trips exactly on the integer grid.
        assert np.array_equal(np.round(mm[valid] * 10.0).astype(np.uint16),
                              raw[valid])

    def test_sentinel_and_at_cap_pixels_written_as_zero(self):
        raw = np.array([0, 1, 3999, ingest.DEPTH_CAP_RAW, 65535],
                       dtype=np.uint16)
        mm = ingest.convert_depth_raw_to_mm(raw)
        assert mm[0] == 0.0                      # sentinel invalid return
        assert mm[1] == pytest.approx(0.1)
        assert mm[2] == pytest.approx(399.9)
        assert mm[3] == 0.0                      # at the 0.4 m saturation cap
        assert mm[4] == 0.0                      # beyond the cap

    def test_cap_is_the_documented_saturation_cap(self):
        # 0.4 m at 10,000 units/metre (Req 3.1).
        assert ingest.DEPTH_CAP_RAW == 4000


# --------------------------------------------------------------------------- #
# Required-files guard (Req 1.2).
# --------------------------------------------------------------------------- #
class TestRequiredFiles:
    def test_missing_root_names_expected_path(self, tmp_path):
        missing = tmp_path / "nowhere"
        with pytest.raises(SystemExit) as exc:
            run_ingest(missing, tmp_path / "out", tmp_path / "mapping.json")
        assert str(missing) in str(exc.value)

    @pytest.mark.parametrize("relative", [
        "metadata/ingredients_metadata.csv",
        "metadata/dish_metadata_cafe1.csv",
        "dish_ids/splits/depth_test_ids.txt",
        "n5k/realsense_overhead",
    ])
    def test_missing_artifact_named(self, tmp_path, relative):
        root = make_n5k_tree(tmp_path / "data", {"dish_1": {}})
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        target = root / relative
        if target.is_dir():
            import shutil
            shutil.rmtree(target)
        else:
            target.unlink()
        with pytest.raises(SystemExit) as exc:
            run_ingest(root, tmp_path / "out", artifact)
        assert relative.rsplit("/", 1)[-1] in str(exc.value)

    def test_missing_mapping_artifact_named(self, n5k):
        root, out, _ = n5k
        missing = root / "does_not_exist.json"
        with pytest.raises(SystemExit) as exc:
            run_ingest(root, out, missing)
        assert str(missing) in str(exc.value)

    def test_stale_mapping_metadata_version_fails_loudly(self, n5k, tmp_path):
        root, out, artifact = n5k
        doc = json.loads(artifact.read_text())
        doc["n5k_metadata_version"] = "0" * 64
        stale = tmp_path / "stale_mapping.json"
        stale.write_text(json.dumps(doc))
        with pytest.raises(SystemExit) as exc:
            run_ingest(root, out, stale)
        assert "metadata" in str(exc.value)


# --------------------------------------------------------------------------- #
# Reference-depth verification (Req 3.1 — a 10x unit error must fail loudly).
# --------------------------------------------------------------------------- #
class TestReferenceChecks:
    def test_ten_x_unit_error_aborts_ingestion(self, tmp_path):
        # Depth as if the units were already mm: plate at raw 360 -> 36 mm.
        root = make_n5k_tree(tmp_path / "data", {
            "dish_1": {"depth": plate_depth(360, 340, 410)},
            "dish_2": {"depth": plate_depth(360, 340, 410)},
        })
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        with pytest.raises(SystemExit) as exc:
            run_ingest(root, tmp_path / "out", artifact)
        assert "reference" in str(exc.value).lower()

    def test_food_top_reference_out_of_band_aborts(self, tmp_path):
        # Plate level fine (~360 mm) but the food-top reference is at 80 mm —
        # the second, independent reference check must catch it.
        root = make_n5k_tree(tmp_path / "data", {
            "dish_1": {"depth": plate_depth(3600, 800)},
            "dish_2": {"depth": plate_depth(3600, 800)},
        })
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        with pytest.raises(SystemExit) as exc:
            run_ingest(root, tmp_path / "out", artifact)
        assert "reference" in str(exc.value).lower()

    def test_reference_bands_strictly_below_saturation_cap(self):
        cap_mm = ingest.DEPTH_CAP_RAW / 10.0
        assert ingest.CAMERA_TO_PLATE_BAND_MM[1] <= cap_mm
        assert ingest.FOOD_TOP_BAND_MM[1] <= cap_mm

    def test_single_out_of_band_plate_skipped_not_fatal(self, tmp_path):
        root = make_n5k_tree(tmp_path / "data", {
            "dish_1": {},
            "dish_2": {},
            "dish_3": {"depth": plate_depth(360, 340, 410)},  # 10x-off plate
        })
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        out = tmp_path / "out"
        assert run_ingest(root, out, artifact) == 0
        summary = load_summary(out)
        assert summary["ingested"] == 2
        assert "dish_3" in summary["skipped"]["depth_out_of_band"]
        assert not (out / "dish_3.fixture").exists()


# --------------------------------------------------------------------------- #
# Skip + record + continue (Req 3.4/3.8).
# --------------------------------------------------------------------------- #
class TestSkipRecord:
    def test_malformed_plates_skipped_recorded_and_run_continues(self, tmp_path):
        root = make_n5k_tree(tmp_path / "data", {
            "dish_good": {},
            "dish_lowres": {"rgb_size": (320, 240)},
            "dish_badpng": {"corrupt_depth": True},
            "dish_norgb": {"skip_rgb": True},
            "dish_nodepth": {"skip_depth": True},
            "dish_nometa": {"omit_metadata": True},
        })
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        out = tmp_path / "out"
        assert run_ingest(root, out, artifact) == 0

        summary = load_summary(out)
        assert summary["ingested"] == 1
        assert (out / "dish_good.fixture").exists()
        skipped = summary["skipped"]
        # Req 3.4: the registration check is dimensional, not geometric.
        assert "dish_lowres" in skipped["resolution_mismatch"]
        assert "dish_badpng" in skipped["malformed_depth"]
        assert "dish_norgb" in skipped["missing_rgb"]
        assert "dish_nodepth" in skipped["missing_depth"]
        assert "dish_nometa" in skipped["missing_metadata"]
        for dish in ("dish_lowres", "dish_badpng", "dish_norgb",
                     "dish_nodepth", "dish_nometa"):
            assert not (out / f"{dish}.fixture").exists()

    def test_malformed_mass_skipped(self, tmp_path):
        root = make_n5k_tree(tmp_path / "data", {"dish_good": {},
                                                 "dish_badmass": {}})
        # Corrupt dish_badmass's mass column in place.
        cafe1 = root / "metadata" / "dish_metadata_cafe1.csv"
        rows = cafe1.read_text().splitlines()
        rows = [re.sub(r"^(dish_badmass,[^,]*),[^,]*", r"\1,not_a_number", r)
                for r in rows]
        cafe1.write_text("\n".join(rows) + "\n")
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        out = tmp_path / "out"
        assert run_ingest(root, out, artifact) == 0
        summary = load_summary(out)
        assert summary["ingested"] == 1
        assert "dish_badmass" in summary["skipped"]["malformed_mass"]


# --------------------------------------------------------------------------- #
# Fixture emission (Req 3.3/3.5/3.6/3.7 + 1.1).
# --------------------------------------------------------------------------- #
class TestEmission:
    def test_pre_checkpoint_fixture_fields(self, n5k):
        root, out, artifact = n5k
        assert run_ingest(root, out, artifact) == 0
        fx = load_fixture(out, "dish_1")

        assert fx.fixture_id == "dish_1"
        assert fx.capture_path_canonical == "single_view_lidar"
        assert fx.palette_version == "v2"

        # Req 3.7 pre-checkpoint default: mixture stamp, sentinel SHA, and
        # NO probability tensor or argmax.
        assert fx.estimator_path == "mixture"
        assert fx.segmenter_checkpoint_sha256 == ingest.SENTINEL_SHA
        assert len(fx.nadir_probs) == 0
        assert len(fx.nadir_argmax) == 0

        # Req 3.5: mapped per-class mass; unmapped soy sauce excluded, never
        # reassigned; per-dish carb/protein/fat totals carried as GT.
        masses = dict(fx.ground_truth_class_mass_g)
        assert masses == {"white_rice": pytest.approx(150.0),
                          "broccoli": pytest.approx(40.0)}
        assert fx.ground_truth_total_carbs_g == pytest.approx(
            150.0 * 0.280 + 40.0 * 0.070 + 10.0 * 0.049)
        assert fx.ground_truth_protein_g == pytest.approx(
            150.0 * 0.027 + 40.0 * 0.024 + 10.0 * 0.081)
        assert fx.ground_truth_fat_g == pytest.approx(
            150.0 * 0.003 + 40.0 * 0.004 + 10.0 * 0.006)

        # Req 6.2/6.6: per-class GT macros summed from N5k per-ingredient
        # values, mapped classes only — the eval's GT basis, NOT re-derived
        # from the DB composition (that would blind the Req 6.7 cross-macro
        # check). Unmapped soy sauce contributes to no class.
        assert dict(fx.ground_truth_class_carbs_g) == {
            "white_rice": pytest.approx(150.0 * 0.280),
            "broccoli": pytest.approx(40.0 * 0.070)}
        assert dict(fx.ground_truth_class_protein_g) == {
            "white_rice": pytest.approx(150.0 * 0.027),
            "broccoli": pytest.approx(40.0 * 0.024)}
        assert dict(fx.ground_truth_class_fat_g) == {
            "white_rice": pytest.approx(150.0 * 0.003),
            "broccoli": pytest.approx(40.0 * 0.004)}

        # Req 1.4: release-stamped dataset identity.
        assert fx.source_dataset.startswith("nutrition5k@")
        assert "/" in fx.source_dataset

    def test_depth_converted_to_float32_mm(self, n5k):
        root, out, artifact = n5k
        assert run_ingest(root, out, artifact) == 0
        fx = load_fixture(out, "dish_1")
        assert fx.nadir_depth.width == 640
        assert fx.nadir_depth.height == 480
        depth = np.frombuffer(fx.nadir_depth.depth_bytes_mm,
                              dtype="<f4").reshape(480, 640)
        raw = plate_depth()
        expected = ingest.convert_depth_raw_to_mm(raw)
        assert np.array_equal(depth, expected)
        # Table beyond the 0.4 m cap excluded via zero (Req 3.2).
        assert depth[0, 0] == 0.0
        assert depth[240, 320] == pytest.approx(340.0)
        # N5k depth is pre-registered to RGB (assumption recorded in lineage),
        # so depth_from_colour must be an explicit identity — the Swift DepthMap
        # bridge requires exactly 16 floats and fails loudly on an empty field.
        identity = [1.0 if i % 5 == 0 else 0.0 for i in range(16)]
        assert list(fx.nadir_depth.depth_from_colour.m) == identity

    def test_pinned_intrinsics_identical_for_every_plate(self, n5k):
        # Req 3.3: one documented nominal camera model, no per-plate values.
        root, out, artifact = n5k
        assert run_ingest(root, out, artifact) == 0
        fx1 = load_fixture(out, "dish_1")
        fx2 = load_fixture(out, "dish_2")
        for fx in (fx1, fx2):
            k = fx.nadir_intrinsics
            assert (k.fx, k.fy, k.cx, k.cy) == ingest.PINNED_INTRINSICS[:4]
            assert (k.image_width, k.image_height) == (640, 480)

    def test_gravity_straight_down_in_nadir_frame(self, n5k):
        # Req 3.6: camera looks along -Z (Math.proto convention), so gravity
        # in the nadir frame is (0, 0, -1).
        root, out, artifact = n5k
        assert run_ingest(root, out, artifact) == 0
        g = load_fixture(out, "dish_1").gravity
        assert (g.x, g.y, g.z) == (0.0, 0.0, -1.0)

    def test_rgb_embedded_as_png(self, n5k):
        from PIL import Image

        root, out, artifact = n5k
        assert run_ingest(root, out, artifact) == 0
        fx = load_fixture(out, "dish_1")
        img = Image.open(io.BytesIO(fx.nadir_image))
        assert img.size == (640, 480)

    def test_never_writes_into_the_repository(self, n5k):
        # Req 1.1 — outputs land only in --out; nothing appears under the
        # repo's tools/nutrition5k/ from an ingestion run.
        root, out, artifact = n5k
        tool_dir = REPO_ROOT / "tools" / "nutrition5k"
        before = {p.name for p in tool_dir.iterdir()}
        assert run_ingest(root, out, artifact) == 0
        after = {p.name for p in tool_dir.iterdir()}
        assert before == after


# --------------------------------------------------------------------------- #
# Run summary + release identifier (Req 1.4).
# --------------------------------------------------------------------------- #
class TestRunSummary:
    def test_summary_contents(self, n5k):
        root, out, artifact = n5k
        assert run_ingest(root, out, artifact) == 0
        summary = load_summary(out)

        assert summary["ingested"] == 2
        assert re.fullmatch(r"[0-9a-f]{64}", summary["release_identifier"])
        assert summary["download_date"] == "2026-07-02"
        assert summary["n5k_metadata_version"] == mapping.metadata_version(
            root / "metadata" / "ingredients_metadata.csv")
        assert summary["estimator_paths"] == {"mixture": 2,
                                              "single_dominant": 0}
        # Provisional gate values documented in the run summary.
        thresholds = summary["thresholds"]
        assert thresholds["tau_route"] == 0.90
        assert thresholds["liquid_significant_fraction"] == 0.05
        assert thresholds["unmapped_significant_fraction"] == 0.10
        assert thresholds["depth_cap_raw"] == 4000

    def test_release_identifier_deterministic(self, n5k, tmp_path):
        root, out, artifact = n5k
        out2 = tmp_path / "out2"
        assert run_ingest(root, out, artifact) == 0
        assert run_ingest(root, out2, artifact) == 0
        assert (load_summary(out)["release_identifier"]
                == load_summary(out2)["release_identifier"])

    def test_mixture_fit_exclusions_recorded(self, tmp_path):
        root = make_n5k_tree(tmp_path / "data", {
            # 50% soy sauce -> unmapped fraction 0.5 > 0.10.
            "dish_unmapped_heavy": {"ingredients": [(26, 100.0), (508, 100.0)]},
            # 25% chicken soup -> liquid fraction 0.25 >= 0.05.
            "dish_liquid": {"ingredients": [(26, 150.0), (326, 50.0)]},
            "dish_clean": {"ingredients": [(26, 200.0)]},
        })
        artifact = make_test_mapping_artifact(tmp_path / "mapping.json", root)
        out = tmp_path / "out"
        assert run_ingest(root, out, artifact) == 0

        summary = load_summary(out)
        # All three still emit exactly one (mixture) fixture pre-checkpoint...
        assert summary["ingested"] == 3
        # ...but the fit-exclusion lists are recorded for the harness/report.
        assert summary["mixture_fit_excluded_unmapped"] == ["dish_unmapped_heavy"]
        assert summary["liquid_excluded"] == ["dish_liquid"]
        # Liquid-mapped mass appears keyed by its liquid class id so the
        # Swift observation builder can detect it (Req 4.7).
        fx = load_fixture(out, "dish_liquid")
        assert dict(fx.ground_truth_class_mass_g)["soup"] == pytest.approx(50.0)
