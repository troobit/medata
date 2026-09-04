import Foundation
import PortableContracts

// World-up ("anti-gravity") expressed in the §6.0 camera frame, derived from the
// platform's gravity-aligned world-from-camera transform (ARKit/ARCore world: +Y up).
//
// `RawFrame.gravity` ("unit vector, camera frame") feeds `LiDARPlaneFitter`'s
// gravity gate, which rejects any candidate plane whose normal is more than 15°
// from this vector. The vector is pose-dependent: for a nadir capture (camera
// looking straight down) the table normal — and therefore this vector — points
// along the optical axis, (0, 0, 1) in the §6.0 back-projection frame. Passing
// a world-frame constant instead put every real capture's table normal ~90°
// outside the gate, so RANSAC returned zero inliers and both capture modes
// refused with lidarFitDegenerate ("no flat surface"). Bug
// `capture-no-flat-surface-gravity-frame` 2026-07-06.
//
// Frame algebra: §6.0's projection formula (design §6.0; LiDARPlaneFitter's
// back-projection) measures +Y down the image, which is the ARKit rendering
// camera frame with the Y axis negated. World-up in the ARKit camera frame is
// Rᵀ·(0, 1, 0) = (c₀.y, c₁.y, c₂.y) where cᵢ are the rotation columns of
// worldFromCamera; the §6.0 value then flips the Y component. At the identity
// pose this evaluates to (0, −1, 0) — numerically equal to world-frame DOWN,
// which is how the old constant read as plausible.
public enum CameraGravity {
    public static func worldUpInCameraFrame(worldFromCamera m: Mat4) -> Vec3 {
        let up = Vec3(m[col: 0, row: 1], -m[col: 1, row: 1], m[col: 2, row: 1])
        // Rigid transforms have unit rotation columns; normalise defensively and
        // fall back to the identity-pose value on a degenerate input.
        guard up.lengthSquared > 0 else { return Vec3(0, -1, 0) }
        return up.normalised()
    }
}
