import CaptureKit
import Foundation
import PortableContracts

// ID-1 reference card geometry per ISO/IEC 7810:2003 (85.60 × 53.98 mm). Corner order
// matches the design's CardObservation.cornersImagePx contract: TL, TR, BR, BL.
public enum ISO7810 {
    public static let widthMm: Float = 85.60
    public static let heightMm: Float = 53.98

    public static let cornersMm: [(x: Float, y: Float)] = [
        (0, 0),                  // top-left
        (widthMm, 0),            // top-right
        (widthMm, heightMm),     // bottom-right
        (0, heightMm)            // bottom-left
    ]
}

public struct PixelCorner: Sendable, Equatable {
    public var u: Float
    public var v: Float
    public init(_ u: Float, _ v: Float) { self.u = u; self.v = v }
}

public enum CardPoseError: Error, Equatable {
    case wrongCornerCount
    case degenerateCardPose
    case cardTooOblique
}

public struct CardPose: Sendable, Equatable {
    // Rotation R as 3×3 column-major (camera-from-card). Column k is r_k.
    public let rotationColumnMajor: [Float]
    // Translation in mm (camera frame, -Z forward per §6.0).
    public let translationMm: Vec3
    public let scaleAtCardPlaneMmPerPx: Float
    public let pnpResidualPx: Float
    public let cardNormalCameraFrame: Vec3   // r_3, oriented per §6.1 step 8
}

public enum CardPoseSolver {
    // P4P specialisation per design §6.1. Single entry point so callers and tests
    // share one numerical pathway. Solver is stateless and pure.
    public static func solve(
        corners: [PixelCorner],
        intrinsics: CameraIntrinsics
    ) throws -> CardPose {
        guard corners.count == 4 else { throw CardPoseError.wrongCornerCount }

        let fx = intrinsics.fx
        let fy = intrinsics.fy
        let cx = intrinsics.cx
        let cy = intrinsics.cy

        // Step 1: normalise pixel coords. ũ_i = K^{-1}·[u_i;1] = ((u-cx)/fx, (v-cy)/fy).
        let normalised: [(x: Float, y: Float)] = corners.map { c in
            ((c.u - cx) / fx, (c.v - cy) / fy)
        }

        // Step 2: 8×9 DLT matrix derived for the −Z-forward convention (§6.0). The
        // standard +Z-forward cross-product DLT enforces (u,v,1) × H·(X,Y,1) = 0; with
        // −Z forward the pixel homogeneous element is −1 (since p_cam/(−p_cam.z) =
        // (ũ,ṽ,−1)), so the constraints become H1+ũ·H3=0 and H2+ṽ·H3=0 — i.e. the
        // linear-coefficient block has POSITIVE signs (not the standard negative).
        // Row pair per correspondence:
        //   [+X, +Y, +1,  0,  0,  0,  ũ·X, ũ·Y, ũ]
        //   [ 0,  0,  0, +X, +Y, +1,  ṽ·X, ṽ·Y, ṽ]
        // Column-major Float layout for Accelerate (ldA = M = 8).
        var dlt = [Float](repeating: 0, count: 8 * 9)
        let model = ISO7810.cornersMm
        for i in 0..<4 {
            let X = model[i].x, Y = model[i].y
            let u = normalised[i].x, v = normalised[i].y
            let r1 = i * 2
            let r2 = i * 2 + 1
            // Row 1 of pair.
            setColumnMajor(&dlt, rows: 8, row: r1, col: 0, value: X)
            setColumnMajor(&dlt, rows: 8, row: r1, col: 1, value: Y)
            setColumnMajor(&dlt, rows: 8, row: r1, col: 2, value: 1)
            setColumnMajor(&dlt, rows: 8, row: r1, col: 6, value: u * X)
            setColumnMajor(&dlt, rows: 8, row: r1, col: 7, value: u * Y)
            setColumnMajor(&dlt, rows: 8, row: r1, col: 8, value: u)
            // Row 2 of pair.
            setColumnMajor(&dlt, rows: 8, row: r2, col: 3, value: X)
            setColumnMajor(&dlt, rows: 8, row: r2, col: 4, value: Y)
            setColumnMajor(&dlt, rows: 8, row: r2, col: 5, value: 1)
            setColumnMajor(&dlt, rows: 8, row: r2, col: 6, value: v * X)
            setColumnMajor(&dlt, rows: 8, row: r2, col: 7, value: v * Y)
            setColumnMajor(&dlt, rows: 8, row: r2, col: 8, value: v)
        }

        // Step 3: SVD of DLT. Smallest singular vector of A is last column of V →
        // last row of V^T (since A = U Σ V^T). With M=8, N=9, rank ≤ 8 so the
        // null space is dim ≥ 1 and h is the null-space basis.
        let svdDlt = try LinearAlgebra.svdFull(dlt, rows: 8, cols: 9)
        // Vt is column-major 9×9; row k is at offsets k, k+9, k+18, ..., k+72.
        let lastRow = 8
        var hVec = [Float](repeating: 0, count: 9)
        for col in 0..<9 {
            hVec[col] = svdDlt.vt[col * 9 + lastRow]
        }

        // Step 4: reshape h (row-major) into H (3×3, row-major then convert to col-major).
        // h is [h11,h12,h13, h21,h22,h23, h31,h32,h33] in row order.
        // H column-major: H[col][row] → flat[col*3+row]; H_rowmajor[row][col] = h[row*3+col].
        var hCol = [Float](repeating: 0, count: 9)
        for row in 0..<3 {
            for col in 0..<3 {
                hCol[col * 3 + row] = hVec[row * 3 + col]
            }
        }

        // Stability gate: SVD of H itself. σ_min/σ_max ≥ 1e-6 else degenerate.
        let svdH = try LinearAlgebra.svdFull(hCol, rows: 3, cols: 3)
        let sMax = svdH.s[0]
        let sMin = svdH.s[2]
        guard sMax > 0, sMin / sMax >= 1e-6 else {
            throw CardPoseError.degenerateCardPose
        }

        // Step 5: decompose H = [r1, r2, t] up to scale.
        // Columns of H (column-major flat layout): col k starts at hCol[k*3].
        let h1 = Vec3(hCol[0], hCol[1], hCol[2])
        let h2 = Vec3(hCol[3], hCol[4], hCol[5])
        let h3 = Vec3(hCol[6], hCol[7], hCol[8])

        let h1Norm = h1.length
        guard h1Norm > 0 else { throw CardPoseError.degenerateCardPose }
        let lambdaMag = 1 / h1Norm

        var lambda: Float = lambdaMag
        var t = lambda * h3
        if t.z >= 0 {
            lambda = -lambdaMag
            t = lambda * h3
        }
        if t.z >= 0 {
            // Both signs land behind the camera — quad is not a card.
            throw CardPoseError.degenerateCardPose
        }

        var r1 = lambda * h1
        var r2 = lambda * h2
        var r3 = r1.cross(r2)

        // Step 6: project [r1 r2 r3] onto SO(3) via SVD with det(UV^T) fix-up.
        let mCol: [Float] = [r1.x, r1.y, r1.z,
                             r2.x, r2.y, r2.z,
                             r3.x, r3.y, r3.z]
        let svdM = try LinearAlgebra.svdFull(mCol, rows: 3, cols: 3)
        // R = U · diag(1, 1, det(U V^T)) · V^T.
        let uvT = LinearAlgebra.mul3x3(svdM.u, svdM.vt)
        let detSign: Float = LinearAlgebra.det3x3(uvT) >= 0 ? 1 : -1
        // Build diag(1,1,detSign) into D, then R = U · D · Vt.
        var d = [Float](repeating: 0, count: 9)
        d[0] = 1; d[4] = 1; d[8] = detSign
        let uD = LinearAlgebra.mul3x3(svdM.u, d)
        let r = LinearAlgebra.mul3x3(uD, svdM.vt)
        // Replace r1..r3 with the orthonormalised columns from r (column-major flat).
        r1 = Vec3(r[0], r[1], r[2])
        r2 = Vec3(r[3], r[4], r[5])
        r3 = Vec3(r[6], r[7], r[8])

        // Step 7: edge-on refusal. ẑ_cam = (0, 0, -1). |r3·ẑ_cam| = |r3.z|.
        if abs(r3.z) < 0.2 {
            throw CardPoseError.cardTooOblique
        }

        // n̂ orientation per §6.1 step 8: n̂ · (camera_origin − t) > 0 ⇒ n̂ · t < 0.
        var nHat = r3
        if nHat.dot(t) > 0 { nHat = -nHat }

        // Step 8: scale at card plane.
        let uCentreU = (corners[0].u + corners[1].u + corners[2].u + corners[3].u) / 4
        let uCentreV = (corners[0].v + corners[1].v + corners[2].v + corners[3].v) / 4
        let dRayUnnormalised = Vec3((uCentreU - cx) / fx, (uCentreV - cy) / fy, -1)
        let dRay = dRayUnnormalised.normalised()
        let denom = nHat.dot(dRay)
        guard abs(denom) > 1e-7 else { throw CardPoseError.degenerateCardPose }
        let alpha = nHat.dot(t) / denom
        let pCard = alpha * dRay
        let zCentre = -pCard.z
        let scaleMmPerPx = zCentre / fx

        // Reprojection residual (informational only per §6.1 step 9).
        let residual = computeResidual(
            corners: corners,
            r: r,            // column-major 3×3
            t: t,
            intrinsics: intrinsics
        )

        return CardPose(
            rotationColumnMajor: r,
            translationMm: t,
            scaleAtCardPlaneMmPerPx: scaleMmPerPx,
            pnpResidualPx: residual,
            cardNormalCameraFrame: nHat
        )
    }

    // For each model corner X_i, project via (R·X_i + t) → image. Compute mean L2 px error.
    public static func computeResidual(
        corners: [PixelCorner],
        r: [Float],
        t: Vec3,
        intrinsics: CameraIntrinsics
    ) -> Float {
        var sum: Float = 0
        var counted = 0
        let model = ISO7810.cornersMm
        for i in 0..<4 {
            let X = Vec3(model[i].x, model[i].y, 0)
            let p = applyR(r, to: X) + t
            // Project per §6.0. project() guards Z<0; if not, residual is undefined.
            guard p.z < 0 else { continue }
            let denomZ = -p.z
            let u = intrinsics.fx * p.x / denomZ + intrinsics.cx
            let v = intrinsics.fy * p.y / denomZ + intrinsics.cy
            let du: Float = u - corners[i].u
            let dv: Float = v - corners[i].v
            let distSquared: Float = du * du + dv * dv
            sum += distSquared.squareRoot()
            counted += 1
        }
        return counted > 0 ? sum / Float(counted) : .infinity
    }

    // Apply column-major 3×3 to a Vec3.
    static func applyR(_ r: [Float], to v: Vec3) -> Vec3 {
        let x = r[0] * v.x + r[3] * v.y + r[6] * v.z
        let y = r[1] * v.x + r[4] * v.y + r[7] * v.z
        let z = r[2] * v.x + r[5] * v.y + r[8] * v.z
        return Vec3(x, y, z)
    }
}

// Column-major writer: A_{row,col} in flat[col*rows + row].
@inline(__always)
private func setColumnMajor(_ a: inout [Float], rows: Int, row: Int, col: Int, value: Float) {
    a[col * rows + row] = value
}
