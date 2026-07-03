#if HARNESS_ENABLED
import Foundation

// Mixture β calibrator (design §MixtureBetaCalibrator, Decisions 11/14).
// Solves, over multi-ingredient plates, V_p ≈ Σ_c (m_pc/ρ_c)·x_c with
// x_c = 1/β_c, as a bounded-variable least squares (Lawson–Hanson active set).
// The β bounds [0.05, 1.5] are enforced INSIDE the solve — a post-hoc clamp
// would re-leak a clamped class's excess volume into co-occurring classes and
// break the joint attribution (Decision 11 refinement).
//
// Offline harness only (Decision 14): never ships on-device; the device
// consumes only the baked DB rows this feeds.
public enum MixtureBetaCalibrator {

    // Provisional gate values (design §Provisional gate values, recorded in
    // the calibration report).
    public static let effectiveSampleMin = 30           // pipeline floor
    public static let tauEff: Float = 0.15              // per-plate mass fraction (Req 4.5)
    public static let stackingKappa: Float = 0.6        // hull-vs-expected guard (Req 4.3)
    public static let liquidSignificantFraction: Float = 0.05  // Req 4.7
    public static let relativeSEBound: Float = 0.15     // identifiability (Req 5.4)
    public static let betaFloor: Float = 0.05
    public static let betaCeil: Float = 1.5

    public struct PlateObservation: Sendable {
        public let fixtureID: String
        public let totalHullVolumeCm3: Float          // depth-derived (TotalHullVolume)
        public let massByClassG: [String: Float]      // mapped N5k masses

        public init(fixtureID: String, totalHullVolumeCm3: Float,
                    massByClassG: [String: Float]) {
            self.fixtureID = fixtureID
            self.totalHullVolumeCm3 = totalHullVolumeCm3
            self.massByClassG = massByClassG
        }
    }

    public struct Result: Sendable {
        public let betaPerClass: [String: Float]
        public let standardErrorPerClass: [String: Float]   // SE on β → dispersion (Req 6.4)
        public let effectiveSamplePerClass: [String: Int]   // plates at mass fraction ≥ τ_eff (Req 4.5)
        public let identifiablePerClass: [String: Bool]     // relative SE ≤ bound (Req 5.4)
        public let conditionNumber: Float                   // Req 5.5 diagnostic
        public let excludedPlates: [String]                 // stacking/occlusion guard (Req 4.3)
        public let liquidExcludedPlates: [String]           // Req 4.7, counted in the 4.5 pool report
        public let fixedOffsetClasses: Set<String>          // under-sampled, held at β = 1 (Req 4.6)
        public let clampedClasses: Set<String>              // bound-resting → Req 5.6 warning
    }

    // Fit β over the observations. `densityByClass` must cover every mapped
    // class (the DB does); `liquidClasses` marks classes whose plates are
    // excluded from the fit entirely when their mass is significant (Req 4.7).
    public static func fit(
        _ obs: [PlateObservation],
        densityByClass: [String: Float],
        liquidClasses: Set<String> = []
    ) -> Result {
        // --- Plate guards -------------------------------------------------
        var liquidExcluded: [String] = []
        var stackingExcluded: [String] = []
        var included: [PlateObservation] = []
        for plate in obs {
            let totalMass = plate.massByClassG.values.reduce(0, +)
            guard totalMass > 0 else { continue }
            let liquidMass = plate.massByClassG
                .filter { liquidClasses.contains($0.key) }
                .values.reduce(0, +)
            if liquidMass / totalMass >= liquidSignificantFraction {
                liquidExcluded.append(plate.fixtureID)
                continue
            }
            // Expected minimum volume at β ≈ 1 over solid mapped classes.
            let expectedMin = plate.massByClassG.reduce(Float(0)) { acc, kv in
                guard !liquidClasses.contains(kv.key),
                      let rho = densityByClass[kv.key] else { return acc }
                return acc + kv.value / rho
            }
            if plate.totalHullVolumeCm3 < stackingKappa * expectedMin {
                stackingExcluded.append(plate.fixtureID)
                continue
            }
            included.append(plate)
        }

        // --- Effective samples (Req 4.5) ----------------------------------
        // A plate counts toward a class only when the class's share of the
        // plate's mapped mass is ≥ τ_eff. Solid classes only; liquid classes
        // never enter the fit (Decision 9).
        var effective: [String: Int] = [:]
        for plate in included {
            let totalMass = plate.massByClassG.values.reduce(0, +)
            for (c, m) in plate.massByClassG where !liquidClasses.contains(c) {
                if m / totalMass >= tauEff {
                    effective[c, default: 0] += 1
                }
            }
        }

        let allSolid = Set(included.flatMap { $0.massByClassG.keys })
            .subtracting(liquidClasses)
        let fixedOffset = Set(allSolid.filter {
            effective[$0, default: 0] < effectiveSampleMin
        })
        let solved = allSolid.subtracting(fixedOffset).sorted()

        guard !solved.isEmpty, !included.isEmpty else {
            return Result(
                betaPerClass: [:], standardErrorPerClass: [:],
                effectiveSamplePerClass: effective, identifiablePerClass: [:],
                conditionNumber: .nan,
                excludedPlates: stackingExcluded,
                liquidExcludedPlates: liquidExcluded,
                fixedOffsetClasses: fixedOffset, clampedClasses: []
            )
        }

        // --- Design matrix -------------------------------------------------
        // A[p][c] = m_pc/ρ_c over solved classes; fixed-offset classes are
        // held at β = 1 and moved to the RHS: V' = V − Σ_fixed m/ρ (Req 4.6).
        // Trace liquid mass (below the significant fraction) stays in the hull
        // as unmodelled residual — an accepted, bounded bias.
        let n = included.count
        let k = solved.count
        var a = [Double](repeating: 0, count: n * k)
        var b = [Double](repeating: 0, count: n)
        for (p, plate) in included.enumerated() {
            var rhs = Double(plate.totalHullVolumeCm3)
            for (c, m) in plate.massByClassG {
                guard !liquidClasses.contains(c), let rho = densityByClass[c] else { continue }
                if fixedOffset.contains(c) {
                    rhs -= Double(m / rho)
                } else if let j = solved.firstIndex(of: c) {
                    a[p * k + j] = Double(m / rho)
                }
            }
            b[p] = rhs
        }

        // --- BVLS solve -----------------------------------------------------
        let lower = Double(1 / betaCeil)
        let upper = Double(1 / betaFloor)
        let x = bvls(a: a, b: b, rows: n, cols: k, lower: lower, upper: upper)

        let boundTol = 1e-6
        var clamped: Set<String> = []
        var beta: [String: Float] = [:]
        for (j, c) in solved.enumerated() {
            beta[c] = Float(1.0 / x[j])
            if abs(x[j] - lower) <= boundTol || abs(x[j] - upper) <= boundTol {
                clamped.insert(c)
            }
        }

        // --- Diagnostics (Req 5.4/5.5) --------------------------------------
        // Residual variance × diag(G⁻¹) with G = AᵀA over the solved columns.
        // The inverse uses eigenvalues floored at λ_max·1e-12, so a collinear
        // (near-null-space) class surfaces as an enormous SE rather than a
        // silently regularised one.
        var rss = 0.0
        for p in 0..<n {
            var pred = 0.0
            for j in 0..<k { pred += a[p * k + j] * x[j] }
            let r = b[p] - pred
            rss += r * r
        }
        let dof = max(1, n - k)
        let s2 = rss / Double(dof)

        var g = [Double](repeating: 0, count: k * k)
        for i in 0..<k {
            for j in i..<k {
                var sum = 0.0
                for p in 0..<n { sum += a[p * k + i] * a[p * k + j] }
                g[i * k + j] = sum
                g[j * k + i] = sum
            }
        }
        let eig = jacobiEigen(symmetric: g, dim: k)
        let lambdaMax = eig.values.max() ?? 0
        let lambdaMin = eig.values.min() ?? 0
        let conditionNumber: Float = lambdaMax > 0 && lambdaMin > 0
            ? Float((lambdaMax / lambdaMin).squareRoot())
            : .infinity

        var se: [String: Float] = [:]
        var identifiable: [String: Bool] = [:]
        let lambdaFloor = lambdaMax * 1e-12
        for (j, c) in solved.enumerated() {
            var varX = 0.0
            for e in 0..<k {
                let v = eig.vectors[e * k + j]
                varX += v * v / max(eig.values[e], lambdaFloor)
            }
            varX *= s2
            let seX = varX.squareRoot()
            // Delta method: β = 1/x → SE_β = SE_x/x²; relative SE_β = SE_x/x.
            se[c] = Float(seX / (x[j] * x[j]))
            let relSE = seX / x[j]
            identifiable[c] = relSE.isFinite && Float(relSE) <= relativeSEBound
        }
        for c in fixedOffset {
            identifiable[c] = false
        }

        return Result(
            betaPerClass: beta,
            standardErrorPerClass: se,
            effectiveSamplePerClass: effective,
            identifiablePerClass: identifiable,
            conditionNumber: conditionNumber,
            excludedPlates: stackingExcluded,
            liquidExcludedPlates: liquidExcluded,
            fixedOffsetClasses: fixedOffset,
            clampedClasses: clamped
        )
    }

    // MARK: - BVLS (Lawson–Hanson active set with bounds)

    // Minimise ||Ax − b||² subject to lower ≤ x_j ≤ upper. Row-major A.
    static func bvls(a: [Double], b: [Double], rows n: Int, cols k: Int,
                     lower: Double, upper: Double) -> [Double] {
        enum VarState { case free, atLower, atUpper }
        // Start at the interior point β = 1 (x = 1) clamped into the box.
        var x = [Double](repeating: min(max(1.0, lower), upper), count: k)
        var state = [VarState](repeating: .free, count: k)

        // Gradient of ½||b − Ax||²: w = Aᵀ(b − Ax).
        func gradient() -> [Double] {
            var resid = [Double](repeating: 0, count: n)
            for p in 0..<n {
                var pred = 0.0
                for j in 0..<k { pred += a[p * k + j] * x[j] }
                resid[p] = b[p] - pred
            }
            var w = [Double](repeating: 0, count: k)
            for j in 0..<k {
                var sum = 0.0
                for p in 0..<n { sum += a[p * k + j] * resid[p] }
                w[j] = sum
            }
            return w
        }

        // Least-squares over the free set with bound variables on the RHS,
        // via the eigendecomposition pseudo-inverse (rank-deficiency-safe).
        func freeSolve(_ freeIdx: [Int]) -> [Double] {
            let kf = freeIdx.count
            var g = [Double](repeating: 0, count: kf * kf)
            var r = [Double](repeating: 0, count: kf)
            for p in 0..<n {
                var rhs = b[p]
                for j in 0..<k where state[j] != .free {
                    rhs -= a[p * k + j] * x[j]
                }
                for (fi, j) in freeIdx.enumerated() {
                    let apj = a[p * k + j]
                    r[fi] += apj * rhs
                    for (fj, j2) in freeIdx.enumerated() where fj >= fi {
                        g[fi * kf + fj] += apj * a[p * k + j2]
                    }
                }
            }
            for i in 0..<kf {
                for j in (i + 1)..<kf { g[j * kf + i] = g[i * kf + j] }
            }
            let eig = jacobiEigen(symmetric: g, dim: kf)
            let lMax = eig.values.max() ?? 0
            let cutoff = lMax * 1e-10
            var z = [Double](repeating: 0, count: kf)
            for e in 0..<kf where eig.values[e] > cutoff {
                var proj = 0.0
                for i in 0..<kf { proj += eig.vectors[e * kf + i] * r[i] }
                proj /= eig.values[e]
                for i in 0..<kf { z[i] += eig.vectors[e * kf + i] * proj }
            }
            return z
        }

        let gradTol = 1e-9 * (gradient().map { abs($0) }.max() ?? 1.0)

        for _ in 0..<(20 * max(1, k)) {
            let freeIdx = (0..<k).filter { state[$0] == .free }

            if !freeIdx.isEmpty {
                let z = freeSolve(freeIdx)
                let violators = freeIdx.enumerated().filter { (fi, _) in
                    z[fi] < lower - 1e-12 || z[fi] > upper + 1e-12
                }
                if violators.isEmpty {
                    for (fi, j) in freeIdx.enumerated() { x[j] = z[fi] }
                } else {
                    // Interpolate from x toward z up to the first bound crossing.
                    var alpha = 1.0
                    for (fi, j) in freeIdx.enumerated() {
                        let dz = z[fi] - x[j]
                        if dz == 0 { continue }
                        let target = dz < 0 ? lower : upper
                        let step = (target - x[j]) / dz
                        if step < alpha, z[fi] < lower || z[fi] > upper {
                            alpha = max(0, step)
                        }
                    }
                    for (fi, j) in freeIdx.enumerated() {
                        x[j] += alpha * (z[fi] - x[j])
                        if x[j] <= lower + 1e-12 { x[j] = lower; state[j] = .atLower }
                        if x[j] >= upper - 1e-12 { x[j] = upper; state[j] = .atUpper }
                    }
                    continue
                }
            }

            // KKT check: release the most beneficial bound variable, if any.
            let w = gradient()
            var bestJ = -1
            var bestW = gradTol
            for j in 0..<k {
                switch state[j] {
                case .atLower where w[j] > bestW:  bestJ = j; bestW = w[j]
                case .atUpper where -w[j] > bestW: bestJ = j; bestW = -w[j]
                default: break
                }
            }
            if bestJ < 0 { break }        // optimal
            state[bestJ] = .free
        }
        return x
    }

    // MARK: - Symmetric eigendecomposition (cyclic Jacobi)

    // Returns eigenvalues and row-major eigenvectors (vectors[e*dim + i] is
    // component i of eigenvector e). Deterministic, Double precision — small
    // matrices only (k ≤ palette size).
    static func jacobiEigen(symmetric g: [Double], dim: Int)
        -> (values: [Double], vectors: [Double]) {
        var m = g
        var v = [Double](repeating: 0, count: dim * dim)
        for i in 0..<dim { v[i * dim + i] = 1 }
        guard dim > 1 else { return ([m.first ?? 0], v) }

        for _ in 0..<100 {
            var off = 0.0
            for i in 0..<dim {
                for j in (i + 1)..<dim { off += m[i * dim + j] * m[i * dim + j] }
            }
            if off < 1e-30 { break }
            for p in 0..<dim {
                for q in (p + 1)..<dim {
                    let apq = m[p * dim + q]
                    if abs(apq) < 1e-300 { continue }
                    let theta = (m[q * dim + q] - m[p * dim + p]) / (2 * apq)
                    let t = (theta >= 0 ? 1.0 : -1.0)
                        / (abs(theta) + (theta * theta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot()
                    let s = t * c
                    for i in 0..<dim {
                        let mip = m[i * dim + p]
                        let miq = m[i * dim + q]
                        m[i * dim + p] = c * mip - s * miq
                        m[i * dim + q] = s * mip + c * miq
                    }
                    for i in 0..<dim {
                        let mpi = m[p * dim + i]
                        let mqi = m[q * dim + i]
                        m[p * dim + i] = c * mpi - s * mqi
                        m[q * dim + i] = s * mpi + c * mqi
                    }
                    for i in 0..<dim {
                        let vpi = v[p * dim + i]
                        let vqi = v[q * dim + i]
                        v[p * dim + i] = c * vpi - s * vqi
                        v[q * dim + i] = s * vpi + c * vqi
                    }
                }
            }
        }
        let values = (0..<dim).map { m[$0 * dim + $0] }
        return (values, v)
    }
}
#endif
