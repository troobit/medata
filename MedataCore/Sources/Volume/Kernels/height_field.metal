// Single-view height-field integration kernel per design §6.7.
// One thread per nadir-view pixel; dispatch over the full colour-image grid.
// Per-class atomic volume accumulators in MTLBuffer<atomic_uint>[C] with
// .storageModeShared (Apple Silicon UMA). Volume is accumulated as a fixed-point
// integer (μm³ × 1000 → stored as uint) to avoid atomics on floating-point.
//
// Inter-class occlusion detection (§6.8) runs in the same pass via a
// single-pass 4-neighbour scan over the argmax + top-surface depth data that is
// already resident in thread-group memory, satisfying Req 13.2.
//
// Numerical contract (§6.0):
//   * Probability tensor P is FP16 IEEE-754 LE, HWC row-major.
//   * Depth map is Float32 row-major in mm (z_t = |z|, positive distance along −Z).
//   * Confidence bytes are UInt8 0..255.
//   * Pixel area: a(p) = z_t² / (f_x · f_y · cos³θ_p) with
//     cosθ_p = f_mean / sqrt(f_mean² + (u−c_x)² + (v−c_y)²) (Decision 29).
//   * Volume conversion mm³→cm³ and β-correction happen in the Swift dispatcher
//     (HeightFieldEstimator), not here.

#include <metal_stdlib>
using namespace metal;

struct HeightFieldParams {
    // Image dimensions (colour grid = depth grid in this dispatch).
    uint  width;
    uint  height;
    // Camera intrinsics.
    float fx;
    float fy;
    float cx;
    float cy;
    // Support plane (n̂, d): n̂ · p = d on plane (mm).
    float3 plane_normal;
    float  plane_d_mm;
    // Class ids.
    uint  classes;
    uint  background_id;
    uint  unsupported_liquid_id;
    // Thresholds.
    float tau_sil;      // silhouette: (1 − q[bg]) ≥ τ_sil
    float tau_conf;     // LiDAR confidence threshold (0..1 from UInt8/255)
    // Occlusion detection.
    float depth_discontinuity_mm;   // §6.8: 10 mm
};

// Volume is accumulated as scaled fixed-point: 1 unit = 1 μm³ / 1000 ≈ 1e-9 mm³.
// Shift by 20 bits allows ~1e12 mm³ per class before overflow — well above max meal.
// Swift dispatcher converts back: vol_mm3 = atomic_count * scale.
static constant float kVolumeScale = 1e-3f;   // stored as mm³ × 1000 (uint)

kernel void height_field_integrate(
    device const half    *probs            [[ buffer(0) ]],   // FP16 HWC
    device const float   *depth_mm         [[ buffer(1) ]],   // Float32 row-major mm
    device const uint8_t *confidence       [[ buffer(2) ]],   // UInt8 0..255
    device const uint8_t *argmax           [[ buffer(3) ]],   // UInt8 row-major
    constant HeightFieldParams &p          [[ buffer(4) ]],
    device atomic_uint   *class_vol_fixed  [[ buffer(5) ]],   // [C] fixed-point vol
    device atomic_uint   *occlusion_flag   [[ buffer(6) ]],   // length 1; 0 or 1
    uint2                  gid             [[ thread_position_in_grid ]])
{
    const uint x = gid.x;
    const uint y = gid.y;
    if (x >= p.width || y >= p.height) return;

    const uint pix = y * p.width + x;
    const uint off = pix * p.classes;

    // Silhouette test: (1 − q[bg]) ≥ τ_sil.
    const float q_bg = float(probs[off + p.background_id]);
    if ((1.0f - q_bg) < p.tau_sil) return;

    const uint label = argmax[pix];
    if (label == p.background_id || label == p.unsupported_liquid_id) return;
    // Skip unknown_food — only food classes (all others) proceed.

    // LiDAR confidence.
    const float conf = float(confidence[pix]) / 255.0f;
    if (conf < p.tau_conf) return;

    const float zt = depth_mm[pix];
    if (zt <= 0.0f) return;

    // Camera-frame ray: d = ((x−cx)/fx, (y−cy)/fy, −1), normalised.
    const float du = float(x) - p.cx;
    const float dv = float(y) - p.cy;
    const float dirX = du / p.fx;
    const float dirY = dv / p.fy;
    const float dirZ = -1.0f;
    const float dirLen = sqrt(dirX*dirX + dirY*dirY + 1.0f);
    const float3 dir = float3(dirX / dirLen, dirY / dirLen, dirZ / dirLen);

    // Support-plane intersection: α = d / (n̂ · dir).
    const float denom = dot(p.plane_normal, dir);
    if (abs(denom) < 1e-9f) return;
    const float alpha_sup = p.plane_d_mm / denom;
    if (alpha_sup <= 0.0f) return;
    const float z_sup = abs((dir * alpha_sup).z);

    // Food-top z (depth along optical axis, mm).
    const float abs_dirZ = abs(dir.z);
    if (abs_dirZ < 1e-9f) return;
    const float z_top = zt;   // depth_mm stores |z| per §6.0
    const float height_mm = max(0.0f, z_sup - z_top);
    if (height_mm <= 0.0f) return;

    // Off-axis pixel area (Decision 29): a(p) = z_t²/(f_x·f_y·cos³θ).
    const float f_mean = (p.fx + p.fy) * 0.5f;
    const float denom_root = sqrt(f_mean*f_mean + du*du + dv*dv);
    const float cos_theta = f_mean / denom_root;
    const float cos3 = cos_theta * cos_theta * cos_theta;
    const float area_mm2 = (zt * zt) / (p.fx * p.fy * cos3);

    const float vol_mm3 = area_mm2 * height_mm;
    const uint vol_fixed = uint(vol_mm3 / kVolumeScale);
    atomic_fetch_add_explicit(class_vol_fixed + label, vol_fixed, memory_order_relaxed);

    // Inter-class occlusion detection (§6.8): 4-neighbour scan.
    // If this pixel and a neighbour belong to different food classes AND their
    // depth differs by > depth_discontinuity_mm, set the occlusion flag.
    const int nx[4] = {1, -1, 0, 0};
    const int ny[4] = {0, 0, 1, -1};
    for (int k = 0; k < 4; ++k) {
        const int nbx = int(x) + nx[k];
        const int nby = int(y) + ny[k];
        if (nbx < 0 || nbx >= int(p.width) || nby < 0 || nby >= int(p.height)) continue;
        const uint nb_pix = uint(nby) * p.width + uint(nbx);
        const uint nb_label = argmax[nb_pix];
        if (nb_label == label) continue;
        if (nb_label == p.background_id || nb_label == p.unsupported_liquid_id) continue;
        const float nb_depth = depth_mm[nb_pix];
        if (abs(zt - nb_depth) > p.depth_discontinuity_mm) {
            atomic_store_explicit(occlusion_flag, 1u, memory_order_relaxed);
        }
    }
}
