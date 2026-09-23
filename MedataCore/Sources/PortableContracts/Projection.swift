import Foundation

// Camera intrinsic projection per design §6.0.
// With -Z forward, project(K, p) = (fx · X / -Z + cx, fy · Y / -Z + cy)
// for camera-frame point p = (X, Y, Z). Defined only for Z < 0 (i.e. point in front of camera).
// Returns nil for points at or behind the camera.
public func project(_ k: PbCameraIntrinsics, _ point: Vec3) -> (u: Float, v: Float)? {
    guard point.z < 0 else { return nil }
    let denom = -point.z
    let u = k.fx * point.x / denom + k.cx
    let v = k.fy * point.y / denom + k.cy
    return (u, v)
}
