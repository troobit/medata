import Accelerate
import Foundation

// Tiny Accelerate-backed SVD wrapper used by P4P card-pose recovery (§6.1) and the
// SO(3) projection at step 6. Column-major float storage throughout, matching LAPACK.
public enum LinAlgError: Error {
    case svdFailed(info: Int32)
}

public struct SVDResult {
    public let u: [Float]      // M x M (JOBU='A').
    public let s: [Float]      // min(M,N) singular values, descending.
    public let vt: [Float]     // N x N (JOBVT='A').
    public let m: Int
    public let n: Int
}

public enum LinearAlgebra {
    // SVD with both U and V^T returned in full ('A','A'). Caller supplies column-major
    // M×N input. Returns U (M×M), S (min(M,N)), Vt (N×N). Used for the homography null-
    // space solve (M=8,N=9) and SO(3) projection of [r1 r2 r3] (3×3).
    //
    // __LAPACK_int is `int` on Darwin without ACCELERATE_LAPACK_ILP64; that's Int32 in
    // Swift. We pass Int32 directly to satisfy the imported C signature.
    public static func svdFull(_ a: [Float], rows m: Int, cols n: Int) throws -> SVDResult {
        var jobu: Int8 = Int8(UInt8(ascii: "A"))
        var jobvt: Int8 = Int8(UInt8(ascii: "A"))
        var mLA: Int32 = Int32(m)
        var nLA: Int32 = Int32(n)
        var lda: Int32 = Int32(m)
        var ldu: Int32 = Int32(m)
        var ldvt: Int32 = Int32(n)
        var info: Int32 = 0

        var aCopy = a
        var s = [Float](repeating: 0, count: min(m, n))
        var u = [Float](repeating: 0, count: m * m)
        var vt = [Float](repeating: 0, count: n * n)

        // Workspace query.
        var workQuery: Float = 0
        var lwork: Int32 = -1
        sgesvd_(&jobu, &jobvt, &mLA, &nLA, &aCopy, &lda, &s, &u, &ldu, &vt, &ldvt,
                &workQuery, &lwork, &info)
        guard info == 0 else { throw LinAlgError.svdFailed(info: info) }

        lwork = Int32(workQuery)
        var work = [Float](repeating: 0, count: Int(lwork))
        sgesvd_(&jobu, &jobvt, &mLA, &nLA, &aCopy, &lda, &s, &u, &ldu, &vt, &ldvt,
                &work, &lwork, &info)
        guard info == 0 else { throw LinAlgError.svdFailed(info: info) }

        return SVDResult(u: u, s: s, vt: vt, m: m, n: n)
    }

    // 3×3 column-major matrix multiply.
    public static func mul3x3(_ a: [Float], _ b: [Float]) -> [Float] {
        precondition(a.count == 9 && b.count == 9)
        var c = [Float](repeating: 0, count: 9)
        for col in 0..<3 {
            for row in 0..<3 {
                var sum: Float = 0
                for k in 0..<3 {
                    sum += a[k * 3 + row] * b[col * 3 + k]
                }
                c[col * 3 + row] = sum
            }
        }
        return c
    }

    // 3×3 column-major determinant.
    public static func det3x3(_ m: [Float]) -> Float {
        precondition(m.count == 9)
        let a = m[0], b = m[3], c = m[6]
        let d = m[1], e = m[4], f = m[7]
        let g = m[2], h = m[5], i = m[8]
        return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    }

    // 3×3 column-major transpose.
    public static func transpose3x3(_ m: [Float]) -> [Float] {
        precondition(m.count == 9)
        return [m[0], m[3], m[6],
                m[1], m[4], m[7],
                m[2], m[5], m[8]]
    }
}
