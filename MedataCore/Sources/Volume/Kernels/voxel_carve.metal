// Two-view voxel carving kernel per design §6.6.
// One thread per voxel; 8×8×8 threadgroups (voxel-grid dims are multiples of 8 per §6.10).
// Per-class atomic counts in MTLBuffer<atomic_uint>[C] with .storageModeShared (Apple
// Silicon UMA).
//
// Numerical contract (§6.0):
//   * Probability tensors P_1, P_2 are FP16 IEEE-754 LE, HWC row-major.
//   * Voxel-ownership product q_1[c] * q_2[c] is PROMOTED to FP32 before argmax to
//     avoid FP16 rounding sensitivity when top two classes are within ~1e-3.
//   * Camera frame is right-handed, +X right, +Y up, −Z forward.
//   * Mat4 transforms are column-major.
//
// Volume conversion (mm³ → cm³) and β-correction happen in the Swift dispatcher
// (VoxelCarveEstimator), not in the kernel.

#include <metal_stdlib>
using namespace metal;

struct VoxelCarveParams {
    float edge_mm;
    uint  dims_x;
    uint  dims_y;
    uint  dims_z;
    float3 origin_camera1;
    float3 axis_x;
    float3 axis_y;
    float3 axis_z;
    // Per-view camera intrinsics: (fx, fy, cx, cy).
    float4 k1;
    float4 k2;
    // Image dims for each view.
    uint2  view1_dims;        // (W, H)
    uint2  view2_dims;
    // T_1→2 (column-major 4×4).
    float4x4 transform_1_to_2;
    // Support plane (n̂, d).
    float3 plane_normal;
    float  plane_d_mm;
    // Class ids.
    uint   classes;
    uint   background_id;
    uint   unsupported_liquid_id;
    // Thresholds.
    float  tau_sil;
    float  tau_v;
};

// Index of the FP16 probability sample at (y, x, c) in HWC row-major.
static inline uint pix_off(uint y, uint x, uint c, uint width, uint classes) {
    return (y * width + x) * classes + c;
}

kernel void voxel_carve(
    device const half     *probs1                [[ buffer(0) ]],
    device const half     *probs2                [[ buffer(1) ]],
    device const uint     *classes_in_both       [[ buffer(2) ]],   // sorted class ids
    constant uint         &classes_in_both_count [[ buffer(3) ]],
    constant VoxelCarveParams &params            [[ buffer(4) ]],
    device atomic_uint    *class_counts          [[ buffer(5) ]],   // length = params.classes
    device atomic_uint    *ambiguous_count       [[ buffer(6) ]],   // length = 1
    device atomic_uint    *silhouette_count      [[ buffer(7) ]],   // length = 1
    uint3                  gid                   [[ thread_position_in_grid ]])
{
    if (gid.x >= params.dims_x || gid.y >= params.dims_y || gid.z >= params.dims_z) {
        return;
    }
    float half_x = float(params.dims_x) * params.edge_mm * 0.5;
    float half_y = float(params.dims_y) * params.edge_mm * 0.5;
    float dx = (float(gid.x) + 0.5) * params.edge_mm - half_x;
    float dy = (float(gid.y) + 0.5) * params.edge_mm - half_y;
    float dz = (float(gid.z) + 0.5) * params.edge_mm;
    float3 p1 = params.origin_camera1
              + params.axis_x * dx
              + params.axis_y * dy
              + params.axis_z * dz;

    // Below-plane discard.
    if (dot(p1, params.plane_normal) - params.plane_d_mm < 0.0) { return; }

    // Project to view 1.
    if (p1.z >= 0.0) { return; }
    float u1 = params.k1.x * p1.x / (-p1.z) + params.k1.z;
    float v1 = params.k1.y * p1.y / (-p1.z) + params.k1.w;
    if (u1 < 0.0 || v1 < 0.0
        || u1 >= float(params.view1_dims.x)
        || v1 >= float(params.view1_dims.y)) { return; }

    // Project to view 2 via T_1→2.
    float4 p1h = float4(p1, 1.0);
    float4 p2h = params.transform_1_to_2 * p1h;
    float3 p2  = p2h.xyz;
    if (p2.z >= 0.0) { return; }
    float u2 = params.k2.x * p2.x / (-p2.z) + params.k2.z;
    float v2 = params.k2.y * p2.y / (-p2.z) + params.k2.w;
    if (u2 < 0.0 || v2 < 0.0
        || u2 >= float(params.view2_dims.x)
        || v2 >= float(params.view2_dims.y)) { return; }

    uint p1x = clamp(uint(floor(u1)), 0u, params.view1_dims.x - 1u);
    uint p1y = clamp(uint(floor(v1)), 0u, params.view1_dims.y - 1u);
    uint p2x = clamp(uint(floor(u2)), 0u, params.view2_dims.x - 1u);
    uint p2y = clamp(uint(floor(v2)), 0u, params.view2_dims.y - 1u);

    uint off1 = pix_off(p1y, p1x, 0u, params.view1_dims.x, params.classes);
    uint off2 = pix_off(p2y, p2x, 0u, params.view2_dims.x, params.classes);

    // Silhouette test on (1 − q[bg]) ≥ τ_sil in BOTH views.
    float q1bg = float(probs1[off1 + params.background_id]);
    float q2bg = float(probs2[off2 + params.background_id]);
    if ((1.0 - q1bg) < params.tau_sil) { return; }
    if ((1.0 - q2bg) < params.tau_sil) { return; }

    atomic_fetch_add_explicit(silhouette_count, 1u, memory_order_relaxed);

    // Per-pixel-pair argmax over classes_in_both_views, FP32 product.
    float best_score = 0.0;
    int   best_class = -1;
    for (uint i = 0u; i < classes_in_both_count; ++i) {
        uint c = classes_in_both[i];
        float qc1 = float(probs1[off1 + c]);
        float qc2 = float(probs2[off2 + c]);
        float s = qc1 * qc2;
        if (s > best_score) {
            best_score = s;
            best_class = int(c);
        }
    }
    if (best_class < 0) { return; }
    if (uint(best_class) == params.unsupported_liquid_id) { return; }
    if (best_score < params.tau_v) {
        atomic_fetch_add_explicit(ambiguous_count, 1u, memory_order_relaxed);
        return;
    }
    atomic_fetch_add_explicit(class_counts + uint(best_class), 1u, memory_order_relaxed);
}
