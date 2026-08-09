"""Tests for the MetaFood3D ingest (Req 1.1/1.2/1.5, Decisions 11/13/14).

Ingest reads a gitignored local MetaFood3D-layout directory (the real
dataset is request-gated and never present here — everything below runs on
synthetic trimesh meshes), renders each object's overhead depth, and emits
one **mixture** fixture per mapped object:

- ``estimator_path = "mixture"``, ``segmenter_checkpoint_sha256 =
  "no_segmenter"``, NO probability tensor (Decision 11 — a single-food
  object is a degenerate one-class mixture);
- run_summary.json carrying the excluded/unmapped ids + counts (Req 1.4),
  the render config, and the authored support-plane parameters for the
  stream-2 injected-plane branch (Decision 13);
- metafood3d_truth.json {fixture_id: mesh_volume_mm3} for the volume-fit
  diagnostic (Req 2.3);
- the metric-scale gates (Req 1.5 / Decision 14): a global unit-sanity
  band over the bbox-extent distribution (mm/m import error) and a
  per-object weight-plausibility band (bbox volume x density brackets the
  shipped gramme weight) — both abort BEFORE any fixture is emitted;
- MetaFood3D imagery/metadata is never written into the repository
  (Req 1.2): an --out inside the repo is refused.
"""

import json

import numpy as np
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

trimesh = pytest.importorskip("trimesh")

import mf3d_testkit  # noqa: E402
from mf3d_testkit import load_tool, parse_fixture, write_dataset  # noqa: E402

ingest = load_tool("ingest")
render = load_tool("render")

# Small render config keeps the per-object ray casts fast; the pinned
# default is asserted separately (test_render_config_defaults_to_pinned).
SMALL = render.RenderConfig(fx=77.125, fy=77.125, cx=39.5, cy=29.5,
                            width=80, height=60, plane_depth_mm=385.0)


@pytest.fixture(autouse=True)
def _small_render(monkeypatch):
    monkeypatch.setattr(ingest, "RENDER_CONFIG", SMALL)


def _box_mm(extents=(50.0, 50.0, 40.0)):
    """Axis-aligned box in mm units, centred at the origin (the ingest
    seats and positions it)."""
    return trimesh.creation.box(extents=extents)


def _run(tmp_path, objects, argv_extra=()):
    data_dir = write_dataset(tmp_path / "mf3d", objects)
    out_dir = tmp_path / "out"
    rc = ingest.main(["--mf3d-dir", str(data_dir),
                      "--out", str(out_dir), *argv_extra])
    assert rc == 0
    return out_dir


class TestFixtureEmission:
    def test_render_config_defaults_to_pinned(self):
        # The autouse fixture monkeypatches RENDER_CONFIG for speed; the
        # committed default must be the pinned N5k camera model (Req 2.4).
        assert ingest.PINNED_RENDER_CONFIG == render.DEFAULT_CONFIG

    def test_emits_single_class_mixture_fixture(self, tmp_path):
        # 50x50x40 mm box = 100 cm3 bbox at 60 g — inside the density band.
        out = _run(tmp_path, [("obj001", "pasta", 60.0, _box_mm())])
        fixture_path = out / "obj001.fixture"
        assert fixture_path.is_file()
        fx = parse_fixture(fixture_path.read_bytes())

        # Decision 11: degenerate one-class mixture, no segmenter.
        assert fx.estimator_path == "mixture"
        assert fx.segmenter_checkpoint_sha256 == "no_segmenter"
        assert len(fx.nadir_probs) == 0
        assert len(fx.nadir_argmax) == 0

        # Decision 15: fixtures are stamped with the live palette version.
        assert fx.palette_version == "v2"

        # Single-class GT mass map keyed by the mapped palette class name.
        assert dict(fx.ground_truth_class_mass_g) == {"pasta": pytest.approx(60.0)}

        # Provenance stamp (Req 9.1).
        assert fx.source_dataset.startswith("metafood3d@")

        # Nadir gravity convention shared with N5k fixtures.
        assert (fx.gravity.x, fx.gravity.y, fx.gravity.z) == (0.0, 0.0, -1.0)

    def test_depth_is_composited_food_on_authored_plane(self, tmp_path):
        out = _run(tmp_path, [("obj001", "pasta", 60.0, _box_mm())])
        fx = parse_fixture((out / "obj001.fixture").read_bytes())
        h, w = fx.nadir_depth.height, fx.nadir_depth.width
        assert (h, w) == (SMALL.height, SMALL.width)
        depth = np.frombuffer(fx.nadir_depth.depth_bytes_mm,
                              dtype="<f4").reshape(h, w)
        # Plane everywhere the food is not; food strictly nearer (positive
        # height-above-plane, so no pixel dies in max(0, .)).
        assert (depth > 0).all()
        food = depth < SMALL.plane_depth_mm
        assert food.any()
        assert (depth[~food] == np.float32(SMALL.plane_depth_mm)).all()
        # Box top face: 40 mm proud of the plane.
        assert depth[food].min() == pytest.approx(
            SMALL.plane_depth_mm - 40.0, abs=0.5)
        # Fixture intrinsics carry the render camera model.
        assert fx.nadir_intrinsics.fx == pytest.approx(SMALL.fx)
        assert fx.nadir_intrinsics.image_width == SMALL.width

    def test_run_summary_counts_unmapped_and_ambiguous(self, tmp_path):
        out = _run(tmp_path, [
            ("obj001", "pasta", 60.0, _box_mm()),
            ("obj002", "pizza", 60.0, _box_mm()),     # no palette mapping
            ("obj003", "potato", 60.0, _box_mm()),    # cooking-method ambiguous
        ])
        assert (out / "obj001.fixture").is_file()
        assert not (out / "obj002.fixture").exists()
        assert not (out / "obj003.fixture").exists()

        summary = json.loads((out / "run_summary.json").read_text())
        assert summary["ingested"] == 1
        assert summary["unmapped_excluded"] == {"pizza": ["obj002"]}
        assert summary["ambiguous_excluded"] == {"potato": ["obj003"]}
        assert summary["unmapped_excluded_count"] == 1
        assert summary["ambiguous_excluded_count"] == 1

    def test_run_summary_carries_render_config_plane_and_licence(self, tmp_path):
        out = _run(tmp_path, [("obj001", "pasta", 60.0, _box_mm())])
        summary = json.loads((out / "run_summary.json").read_text())
        assert summary["dataset"] == "metafood3d"
        assert summary["licence"] == "CC BY-NC 4.0"
        # Req 9.1 lineage keys, canonical Swift-decoder names (Decision 17):
        # `snapshot` + `mapping_version`, never `snapshot_identifier`.
        assert summary["snapshot"]
        assert summary["source_dataset"] == \
            f"metafood3d@{summary['snapshot'][:12]}"
        mapping_artifact = ingest.mapping.DEFAULT_ARTIFACT
        assert summary["mapping_version"] == \
            ingest.mapping_artifact_version(mapping_artifact)
        # Req 2.4/2.5/9.1: recorded camera config incl. the noise-free note,
        # under the canonical key names the Swift decoder reads.
        rc = summary["render_config"]
        assert rc["plane_depth_mm"] == SMALL.plane_depth_mm
        assert rc["image_width"] == SMALL.width
        assert rc["image_height"] == SMALL.height
        assert rc["seating_rule"] == ingest.SEATING_RULE
        assert rc["noise"] == "noise_free_render"
        # Decision 13: authored plane parameters for the injected-plane
        # branch (stream 2 consumes these; the fixture proto has no
        # support-plane field).
        plane = summary["authored_support_plane"]
        assert plane["plane_depth_mm"] == SMALL.plane_depth_mm
        assert "convention" in plane
        # Mapping artifact provenance (Req 9.1).
        assert summary["mapping_categories_source"]

    def test_truth_sidecar_records_mesh_volume_mm3(self, tmp_path):
        out = _run(tmp_path, [("obj001", "pasta", 60.0,
                               _box_mm((50.0, 50.0, 40.0)))])
        truth = json.loads((out / "metafood3d_truth.json").read_text())
        assert truth["obj001"] == pytest.approx(50.0 * 50.0 * 40.0, rel=1e-6)


class TestRunSummaryContract:
    """Decision 17: the committed contract fixture is emitter-generated.

    ``fixtures/run_summary_contract.json`` is the SAME file the Swift
    end-to-end test (EndToEndCalibrateBakeTests) feeds to the built
    HarnessCLI binary, whose loader exits 1 on missing contract keys. This
    test regenerates the document through the real emitter and diffs it,
    so an emitter change that would break the Swift decoder goes red here
    before it ships a summary the harness cannot read."""

    def test_committed_fixture_matches_emitter_output(self):
        import make_contract_fixture

        committed = make_contract_fixture.FIXTURE_PATH.read_text()
        regenerated = make_contract_fixture.contract_text()
        assert committed == regenerated, (
            "run_summary_contract.json no longer matches ingest.py's "
            "emitter. If the contract change is intentional, regenerate "
            "with tools/metafood3d/tests/make_contract_fixture.py AND "
            "update the Swift decoder + EndToEndCalibrateBakeTests "
            "(Decision 17)."
        )

    def test_committed_fixture_carries_the_swift_decoder_keys(self):
        import make_contract_fixture

        doc = json.loads(make_contract_fixture.FIXTURE_PATH.read_text())
        # The exact keys CalibrateRun.loadIngestSummary requires on a
        # metafood3d summary (exit 1 when absent).
        assert doc["dataset"] == "metafood3d"
        for key in ("snapshot", "mapping_version", "licence"):
            assert doc[key], key
        rc = doc["render_config"]
        for key in ("plane_depth_mm", "intrinsics_model", "image_width",
                    "image_height", "seating_rule"):
            assert rc[key], key


class TestMetricScaleGates:
    def test_metre_scale_import_trips_unit_sanity_and_emits_nothing(self, tmp_path):
        # The same box authored in metres (0.05 m) read as mm: the bbox
        # distribution collapses to toy scale — Decision 14 gate (a).
        data_dir = write_dataset(tmp_path / "mf3d", [
            ("obj001", "pasta", 60.0, _box_mm((0.05, 0.05, 0.04))),
        ])
        out_dir = tmp_path / "out"
        with pytest.raises(SystemExit, match="unit"):
            ingest.main(["--mf3d-dir", str(data_dir), "--out", str(out_dir)])
        assert not list(out_dir.glob("*.fixture"))
        # Abort is recorded, id + measured-vs-expected (design §Error
        # Handling).
        summary = json.loads((out_dir / "run_summary.json").read_text())
        assert summary["scale_check_failed"]

    def test_weight_implausible_object_aborts(self, tmp_path):
        # 100 cm3 bbox claiming 2 kg: no food density reaches 20 g/cm3 —
        # Decision 14 gate (b).
        data_dir = write_dataset(tmp_path / "mf3d", [
            ("obj001", "pasta", 2000.0, _box_mm()),
        ])
        out_dir = tmp_path / "out"
        with pytest.raises(SystemExit, match="obj001"):
            ingest.main(["--mf3d-dir", str(data_dir), "--out", str(out_dir)])
        assert not list(out_dir.glob("*.fixture"))

    def test_plausible_candidates_pass(self):
        ingest.check_metric_scale([
            ingest.ScaleCandidate("a", (50.0, 50.0, 40.0), 60.0),
            ingest.ScaleCandidate("b", (120.0, 90.0, 35.0), 200.0),
        ])

    @settings(max_examples=30, deadline=None)
    @given(k=st.one_of(st.floats(min_value=2.5, max_value=8.0),
                       st.floats(min_value=0.125, max_value=0.4)))
    def test_k_scaled_mesh_with_unchanged_weight_is_caught(self, k):
        # Hypothesis property (design §Testing / Decision 14): uniform
        # geometric scaling leaves the shipped weight untouched, so the
        # implied bbox density leaves the band (or the extent distribution
        # leaves the unit-sanity band) — either way the check aborts.
        base = (50.0, 50.0, 40.0)  # 100 cm3, weight 50 g => 0.5 g/cm3
        scaled = tuple(e * k for e in base)
        with pytest.raises(ingest.ScaleError):
            ingest.check_metric_scale(
                [ingest.ScaleCandidate("scaled", scaled, 50.0)])


class TestRepoHygiene:
    def test_out_inside_the_repo_is_refused(self, tmp_path):
        # Req 1.2: MetaFood3D imagery/metadata never lands in the repo.
        data_dir = write_dataset(tmp_path / "mf3d", [
            ("obj001", "pasta", 60.0, _box_mm()),
        ])
        repo_out = mf3d_testkit._REPO_ROOT / "build" / "mf3d_test_out"
        with pytest.raises(SystemExit, match="repo"):
            ingest.main(["--mf3d-dir", str(data_dir),
                         "--out", str(repo_out)])
        assert not repo_out.exists()

    def test_dataset_dir_is_read_only_to_ingest(self, tmp_path):
        data_dir = write_dataset(tmp_path / "mf3d", [
            ("obj001", "pasta", 60.0, _box_mm()),
        ])
        before = sorted(p.relative_to(data_dir).as_posix()
                        for p in data_dir.rglob("*"))
        _run(tmp_path, [("obj001", "pasta", 60.0, _box_mm())])
        after = sorted(p.relative_to(data_dir).as_posix()
                       for p in data_dir.rglob("*"))
        assert before == after
