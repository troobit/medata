#!/usr/bin/env python3
"""Overhead depth render for MetaFood3D meshes (Req 2.4, Decision 12).

Turns a food mesh into the ``nadir_depth`` buffer the volume estimator
consumes: a pinned nadir **perspective** camera casts one CPU ray per pixel
(trimesh's pure-numpy ray-triangle intersector — bit-deterministic, no GL
context, no GPU/driver variance), and the first hit's **z-depth** becomes
the pixel value in millimetres.

Conventions (recorded in lineage via the ingest run summary, Req 9.1):

- Camera frame: camera at the origin, +Z the optical/depth axis, x right,
  y down (image row-major). Meshes are in millimetres, already posed in
  this frame with the authored support plane at ``z = plane_depth_mm``.
- Depth value = hit z-coordinate (RealSense/z-depth convention — what
  intrinsics unprojection assumes), NOT the Euclidean ray length.
- Output: (height, width) little-endian Float32 millimetres, row-major,
  0 = miss (DepthMap.proto).
- The default configuration matches tools/nutrition5k/ingest.py: pinned
  RealSense-D435 RGB nominal intrinsics at 640x480, plane at 385 mm —
  inside the N5k CAMERA_TO_PLATE_BAND (250, 400) mm and below the 0.4 m
  depth cap, so the reference-depth check the ingest reuses passes for
  the right reason.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

_F4 = np.dtype("<f4")


@dataclass(frozen=True)
class RenderConfig:
    fx: float
    fy: float
    cx: float
    cy: float
    width: int
    height: int
    plane_depth_mm: float

    def as_lineage(self) -> dict:
        """Recorded verbatim in the ingest run summary (Req 2.4/9.1)."""
        return {
            "intrinsics_model": "realsense_d435_rgb_nominal",
            "fx": self.fx, "fy": self.fy, "cx": self.cx, "cy": self.cy,
            "width": self.width, "height": self.height,
            "plane_depth_mm": self.plane_depth_mm,
            "pose": "nadir",
            "depth_convention": "z_depth_mm_float32_le_zero_miss",
            "noise": "noise_free_render",  # Req 2.5 / Decision 8
        }


# The N5k pinned camera model (tools/nutrition5k/ingest.py
# PINNED_INTRINSICS) with the plane seated at the true N5k plate distance.
DEFAULT_CONFIG = RenderConfig(fx=617.0, fy=617.0, cx=319.5, cy=239.5,
                              width=640, height=480, plane_depth_mm=385.0)


def render_overhead_depth(mesh, cfg: RenderConfig = DEFAULT_CONFIG) -> np.ndarray:
    """First-hit z-depth per pixel for a mesh posed in the camera frame.

    Returns (cfg.height, cfg.width) '<f4' millimetres, 0 = miss. Food-only:
    plane pixels are composited separately (``composite_support_plane``)
    so the caller can distinguish food coverage from background."""
    import trimesh  # lazy: mapping-only callers run without trimesh

    cols, rows = np.meshgrid(np.arange(cfg.width, dtype=np.float64),
                             np.arange(cfg.height, dtype=np.float64))
    directions = np.stack([
        (cols - cfg.cx) / cfg.fx,
        (rows - cfg.cy) / cfg.fy,
        np.ones_like(cols),
    ], axis=-1).reshape(-1, 3)
    origins = np.zeros_like(directions)

    # Pure-numpy intersector (Decision 12): deterministic across machines,
    # unlike the optional embree backend.
    intersector = trimesh.ray.ray_triangle.RayMeshIntersector(mesh)
    locations, ray_ids, _ = intersector.intersects_location(
        origins, directions, multiple_hits=False)

    depth = np.zeros(cfg.height * cfg.width, dtype=np.float64)
    if len(ray_ids):
        # multiple_hits=False returns one hit per hitting ray, but the
        # first-hit choice is made here explicitly: keep the smallest z
        # per ray so a duplicate-hit backend cannot change the result.
        order = np.lexsort((locations[:, 2], ray_ids))
        ray_ids = ray_ids[order]
        z = locations[order, 2]
        first = np.ones(len(ray_ids), dtype=bool)
        first[1:] = ray_ids[1:] != ray_ids[:-1]
        depth[ray_ids[first]] = z[first]

    return depth.reshape(cfg.height, cfg.width).astype(_F4)


def composite_support_plane(depth_mm: np.ndarray,
                            cfg: RenderConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Replace misses with the authored support plane at
    ``cfg.plane_depth_mm`` (constant z-depth: the plane is normal to the
    nadir optical axis), so the emitted fixture depth looks like a plate
    scene and the plane-fit path has a surface to stand on (Req 2.4)."""
    composite = depth_mm.astype(_F4, copy=True)
    composite[composite == 0] = np.float32(cfg.plane_depth_mm)
    return composite
