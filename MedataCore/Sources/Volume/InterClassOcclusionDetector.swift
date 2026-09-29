import Foundation
import Segmentation

// Inter-class occlusion detector per design §6.8 / Req 13.2. Single-pass O(W·H)
// 4-neighbour scan over the nadir mask + top-surface depth map. A boundary between
// two food classes with depth discontinuity > 10 mm signals that a tall food occludes
// a shorter one in the nadir view — σ_occl is reduced to 0.80 by §6.8 when detected.

public enum InterClassOcclusionDetector {
    public static let depthDiscontinuityMm: Float = 10

    public static func detect(
        argmax: ArgmaxMap,
        depthTopMm: [Float],
        palette: ClassPalette
    ) -> Bool {
        let w = argmax.width
        let h = argmax.height
        precondition(depthTopMm.count == w * h,
                     "depthTopMm must be sized argmax.width × argmax.height")

        return argmax.pixels.withUnsafeBytes { raw -> Bool in
            let lab = raw.bindMemory(to: UInt8.self).baseAddress!
            for y in 0..<h {
                for x in 0..<w {
                    let pIdx = y * w + x
                    let pLab = Int(lab[pIdx])
                    if !palette.isFoodClass(pLab) { continue }
                    let pZ = depthTopMm[pIdx]
                    // 4-neighbour scan.
                    let neighbours = [
                        (x + 1, y),
                        (x - 1, y),
                        (x, y + 1),
                        (x, y - 1)
                    ]
                    for (nx, ny) in neighbours {
                        if nx < 0 || nx >= w || ny < 0 || ny >= h { continue }
                        let nIdx = ny * w + nx
                        let nLab = Int(lab[nIdx])
                        if nLab == pLab { continue }
                        if !palette.isFoodClass(nLab) { continue }
                        if abs(pZ - depthTopMm[nIdx]) > depthDiscontinuityMm {
                            return true
                        }
                    }
                }
            }
            return false
        }
    }
}
