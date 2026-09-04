"""Tests for the MetaFood3D overhead depth render (Req 2.4, Decisions 12/13).

The render turns a mesh (millimetre units, camera frame: camera at the
origin, +Z the optical/depth axis, support plane at z = plane_depth_mm)
into the nadir depth buffer the volume estimator consumes:

- fixed, recorded camera configuration — the N5k pinned RealSense-D435 RGB
  nominal intrinsics at 640x480, nadir pose, plane at ~385 mm (inside the
  N5k CAMERA_TO_PLATE_BAND (250, 400) and below the 0.4 m cap);
- Float32 little-endian millimetres, row-major, 0 = miss (DepthMap.proto);
- z-depth per pixel (RealSense convention — what intrinsics unprojection
  assumes), NOT Euclidean ray length;
- deterministic: same mesh + config yields byte-identical output
  (Hypothesis property; Decision 12 chose CPU ray-cast for exactly this).

Runs only where trimesh is installed (tools/metafood3d/.venv); the
mapping tests stay importable on the bare system python.
"""

import numpy as np
import pytest
from hypothesis import assume, given, settings
from hypothesis import strategies as st

trimesh = pytest.importorskip("trimesh")

from mf3d_testkit import load_tool  # noqa: E402

render = load_tool("render")

# Small proportional config so property tests stay fast; the pinned
# 640x480 default is asserted separately.
SMALL = render.RenderConfig(fx=77.125, fy=77.125, cx=39.5, cy=29.5,
                            width=80, height=60, plane_depth_mm=385.0)
TINY = render.RenderConfig(fx=38.5, fy=38.5, cx=19.5, cy=14.5,
                           width=40, height=30, plane_depth_mm=385.0)


def _box(extents, centre_z, cfg=SMALL):
    """Axis-aligned box centred on the optical axis with its top face at
    centre_z - extents[2]/2 (all mm, camera frame)."""
    mesh = trimesh.creation.box(extents=extents)
    mesh.apply_translation([0.0, 0.0, centre_z])
    return mesh


class TestPinnedConfig:
    def test_default_matches_the_n5k_pinned_intrinsics(self):
        # tools/nutrition5k/ingest.py PINNED_INTRINSICS: D435 RGB-module
        # factory nominal @ 640x480 — β must be fit under the same camera
        # model N5k uses (design §render table).
        cfg = render.DEFAULT_CONFIG
        assert (cfg.fx, cfg.fy, cfg.cx, cfg.cy, cfg.width, cfg.height) == \
            (617.0, 617.0, 319.5, 239.5, 640, 480)

    def test_plane_depth_inside_the_n5k_plate_band_and_below_cap(self):
        # CAMERA_TO_PLATE_BAND_MM (250, 400), DEPTH_CAP 0.4 m
        # (tools/nutrition5k/ingest.py) — the reference-depth check the
        # ingest reuses must pass for the right reason.
        cfg = render.DEFAULT_CONFIG
        assert cfg.plane_depth_mm == 385.0
        assert 250.0 < cfg.plane_depth_mm < 400.0


class TestDepthContract:
    def test_output_is_float32_le_row_major_zero_miss(self):
        depth = render.render_overhead_depth(
            _box([40.0, 40.0, 20.0], 375.0), SMALL)
        assert depth.shape == (SMALL.height, SMALL.width)
        assert depth.dtype == np.dtype("<f4")
        # A 40 mm box at ~375 mm cannot reach the frame corners: misses
        # are exactly 0 (DepthMap.proto sentinel).
        assert depth[0, 0] == 0.0 and depth[-1, -1] == 0.0
        assert (depth > 0).any()

    def test_depth_is_z_depth_not_ray_length(self):
        # A flat top face at constant z must read the SAME depth at
        # off-axis pixels; Euclidean ray length would grow by 1/cos(theta)
        # away from the centre and break intrinsics unprojection.
        top_z = 345.0
        mesh = _box([160.0, 120.0, 80.0], top_z + 40.0)
        depth = render.render_overhead_depth(mesh, SMALL)
        hit = depth > 0
        assert hit.sum() > 200
        np.testing.assert_allclose(depth[hit], top_z, rtol=0, atol=1e-3)

    def test_every_food_pixel_nearer_than_the_plane(self):
        # Seated food (sphere resting on the plane): positive
        # height-above-plane everywhere, so no pixel is silently dropped
        # by TotalHullVolume's max(0, .) gate.
        radius = 25.0
        sphere = trimesh.creation.icosphere(subdivisions=3, radius=radius)
        sphere.apply_translation([0.0, 0.0, SMALL.plane_depth_mm - radius])
        depth = render.render_overhead_depth(sphere, SMALL)
        hit = depth > 0
        assert hit.any()
        assert depth[hit].max() <= SMALL.plane_depth_mm + 1e-3
        assert depth[hit].min() == pytest.approx(
            SMALL.plane_depth_mm - 2 * radius, abs=0.5)

    def test_perspective_footprint_shrinks_with_distance(self):
        # Pinhole perspective at the pinned intrinsics: a w-wide top face
        # at depth z spans ~ fx * w / z pixel columns.
        for top_z in (345.0, 380.0):
            depth = render.render_overhead_depth(
                _box([60.0, 60.0, 4.0], top_z + 2.0), SMALL)
            cols = np.flatnonzero((depth > 0).any(axis=0))
            expected = SMALL.fx * 60.0 / top_z
            assert abs((cols[-1] - cols[0] + 1) - expected) <= 2.0


class TestSupportPlaneComposite:
    def test_misses_become_the_authored_plane(self):
        food = render.render_overhead_depth(
            _box([40.0, 40.0, 20.0], 375.0), SMALL)
        composite = render.composite_support_plane(food, SMALL)
        assert composite.dtype == np.dtype("<f4")
        assert (composite > 0).all()
        was_miss = food == 0
        assert (composite[was_miss] == SMALL.plane_depth_mm).all()
        np.testing.assert_array_equal(composite[~was_miss], food[~was_miss])


@st.composite
def seated_hulls(draw):
    """Random convex blobs seated on the plane (base at plane depth)."""
    n = draw(st.integers(min_value=6, max_value=12))
    coord = st.floats(min_value=-40.0, max_value=40.0,
                      allow_nan=False, allow_infinity=False)
    height = st.floats(min_value=0.0, max_value=39.0,
                       allow_nan=False, allow_infinity=False)
    points = [(draw(coord), draw(coord), draw(height)) for _ in range(n)]
    hull = trimesh.convex.convex_hull(np.asarray(points, dtype=np.float64))
    assume(hull.volume > 1.0)
    # Seat: deepest vertex on the plane, body towards the camera.
    hull.apply_translation(
        [0.0, 0.0, TINY.plane_depth_mm - hull.bounds[1][2]])
    return hull


class TestDeterminism:
    @settings(max_examples=10, deadline=None)
    @given(hull=seated_hulls())
    def test_same_mesh_and_config_yields_byte_identical_depth(self, hull):
        # Decision 12: CPU ray-cast is bit-deterministic; β must be
        # reproducible from lineage.
        first = render.render_overhead_depth(hull, TINY)
        again = render.render_overhead_depth(hull, TINY)
        assert first.tobytes() == again.tobytes()
        rebuilt = trimesh.Trimesh(vertices=hull.vertices.copy(),
                                  faces=hull.faces.copy(), process=False)
        assert render.render_overhead_depth(rebuilt, TINY).tobytes() \
            == first.tobytes()

    @settings(max_examples=10, deadline=None)
    @given(hull=seated_hulls())
    def test_seated_hull_pixels_have_positive_height_above_plane(self, hull):
        depth = render.render_overhead_depth(hull, TINY)
        hit = depth > 0
        assume(hit.any())
        assert depth[hit].max() <= TINY.plane_depth_mm + 1e-3
