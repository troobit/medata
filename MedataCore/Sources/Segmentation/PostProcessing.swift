import Foundation

// Steps 8–13 of design §6.5. Logits come in at [targetSize × targetSize × classes]
// FP32. Output: probabilities resized back to (originalWidth × originalHeight),
// argmax label map, σ_seg (mean of top-class probability over food pixels), and
// perClassMeanProb (informational, food-classes only).
//
// Refusal predicate alignment (M8 / edge case 3): `noFoodPixels` fires when the
// silhouette test `(1 − q[bg]) ≥ τ_sil` finds zero qualifying pixels — NOT when
// `argmax = background` holds everywhere. A pixel with q[bg] = 0.45 (in silhouette,
// since 1 − 0.45 = 0.55) but argmax = bg counts toward the silhouette and avoids
// refusal, even though it does not contribute to σ_seg.

public struct PostProcessedOutput: Sendable {
    public let probabilities: ProbabilityTensor
    public let argmax: ArgmaxMap
    public let perClassMeanProb: [String: Float]
    public let sigmaSeg: Float
}

public enum SegmenterPostProcessor {
    public static let tauSilhouette: Float = 0.5         // §6.6 / §6.7

    public static func process(
        logitsFP32: [Float],
        targetSize: Int,
        classes: Int,
        scaledWidth: Int,
        scaledHeight: Int,
        originalWidth: Int,
        originalHeight: Int,
        palette: ClassPalette
    ) throws -> PostProcessedOutput {
        guard logitsFP32.count == targetSize * targetSize * classes else {
            throw SegmentationError.invalidLogitsShape(
                "logits count \(logitsFP32.count) ≠ \(targetSize)×\(targetSize)×\(classes)"
            )
        }
        guard classes == palette.totalClasses else {
            throw SegmentationError.invalidLogitsShape(
                "logits classes \(classes) ≠ palette.totalClasses \(palette.totalClasses)"
            )
        }
        guard scaledWidth > 0, scaledHeight > 0,
              scaledWidth <= targetSize, scaledHeight <= targetSize else {
            throw SegmentationError.invalidInputDimensions(
                "scaledWidth=\(scaledWidth), scaledHeight=\(scaledHeight) must be in 1...targetSize=\(targetSize)"
            )
        }
        guard originalWidth > 0, originalHeight > 0 else {
            throw SegmentationError.invalidInputDimensions(
                "originalWidth=\(originalWidth), originalHeight=\(originalHeight) must be positive"
            )
        }

        // Step 9: softmax along class axis over the entire padded tensor (FP32, in place).
        var probsPadded = [Float](repeating: 0, count: targetSize * targetSize * classes)
        for pixel in 0..<(targetSize * targetSize) {
            let off = pixel * classes
            var maxLogit = -Float.infinity
            for c in 0..<classes {
                if logitsFP32[off + c] > maxLogit { maxLogit = logitsFP32[off + c] }
            }
            var sum: Float = 0
            for c in 0..<classes {
                let e = expf(logitsFP32[off + c] - maxLogit)
                probsPadded[off + c] = e
                sum += e
            }
            if sum > 0 {
                let inv = 1 / sum
                for c in 0..<classes { probsPadded[off + c] *= inv }
            }
        }

        // Step 10: crop the letterbox region (top-left scaledWidth × scaledHeight) and
        // bilinearly resize back to (originalWidth × originalHeight). Pixel-centre
        // alignment matches the resize convention used during pre-processing.
        var cropped = [Float](repeating: 0, count: scaledHeight * scaledWidth * classes)
        for y in 0..<scaledHeight {
            let srcRow = y * targetSize * classes
            let dstRow = y * scaledWidth * classes
            for c in 0..<(scaledWidth * classes) {
                cropped[dstRow + c] = probsPadded[srcRow + c]
            }
        }

        var resized = [Float](repeating: 0, count: originalHeight * originalWidth * classes)
        bilinearResizeProbabilities(
            src: cropped, srcW: scaledWidth, srcH: scaledHeight,
            dst: &resized, dstW: originalWidth, dstH: originalHeight,
            classes: classes
        )

        // Step 11: argmax over class axis → ArgmaxMap (UInt8, top-left origin per §6.0).
        // Each pixel is independent, so the scan is fanned out across CPU cores
        // (the per-pixel result is order-independent — bit-identical to the serial
        // scan). This and the resize above are the two dominant passes over the
        // original-resolution × classes tensor.
        let pixelCount = originalHeight * originalWidth
        var argmaxData = Data(count: pixelCount)
        argmaxData.withUnsafeMutableBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            resized.withUnsafeBufferPointer { srcBuf in
                let src = srcBuf.baseAddress!
                parallelForRows(rowCount: originalHeight, columns: originalWidth) { pStart, pEnd in
                    for pixel in pStart..<pEnd {
                        let off = pixel * classes
                        var bestC = 0
                        var bestV = -Float.infinity
                        for c in 0..<classes where src[off + c] > bestV {
                            bestV = src[off + c]
                            bestC = c
                        }
                        buf[pixel] = UInt8(bestC)
                    }
                }
            }
        }

        // Steps 12–13: refusal predicate (silhouette test) + σ_seg + perClassMeanProb.
        let bg = palette.background
        var silhouetteCount = 0
        var foodTopSum: Float = 0
        var foodPixelCount = 0
        var perClassSum = [Float](repeating: 0, count: classes)
        var perClassCount = [Int](repeating: 0, count: classes)

        try argmaxData.withUnsafeBytes { rawBuf -> Void in
            let buf = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            for pixel in 0..<pixelCount {
                let off = pixel * classes
                let qBg = resized[off + bg]
                if (1 - qBg) < tauSilhouette { continue }            // not in food silhouette
                silhouetteCount += 1
                let cId = Int(buf[pixel])
                if palette.isFoodClass(cId) {
                    // P[p, argmax] == max_c P[p, c]; σ_seg uses this top probability.
                    let topProb = resized[off + cId]
                    foodTopSum += topProb
                    foodPixelCount += 1
                    perClassSum[cId] += topProb
                    perClassCount[cId] += 1
                }
            }
            if silhouetteCount == 0 { throw SegmentationError.noFoodPixels }
        }

        let sigmaSeg: Float = foodPixelCount > 0 ? foodTopSum / Float(foodPixelCount) : 0
        var perClassMean: [String: Float] = [:]
        for c in 0..<classes {
            guard perClassCount[c] > 0,
                  palette.isFoodClass(c),
                  let name = palette.foodClassName(at: c) else { continue }
            perClassMean[name] = perClassSum[c] / Float(perClassCount[c])
        }

        // Cast probabilities to FP16 LE bytes (portable §3.5 / §6.0 contract).
        let bytes = FP16Bytes.encode(resized)
        let probTensor = ProbabilityTensor(
            bytes: bytes,
            height: originalHeight, width: originalWidth, classes: classes,
            palette: palette
        )
        let argMap = ArgmaxMap(pixels: argmaxData, height: originalHeight, width: originalWidth)
        return PostProcessedOutput(
            probabilities: probTensor,
            argmax: argMap,
            perClassMeanProb: perClassMean,
            sigmaSeg: sigmaSeg
        )
    }
}

func bilinearResizeProbabilities(
    src: [Float], srcW: Int, srcH: Int,
    dst: inout [Float], dstW: Int, dstH: Int,
    classes: Int
) {
    let scaleX = Float(srcW) / Float(dstW)
    let scaleY = Float(srcH) / Float(dstH)
    // Output rows are independent; fan them out across CPU cores. Each output
    // element is computed from the same source samples and weights regardless of
    // which worker runs the row, so the result is bit-identical to a serial pass.
    src.withUnsafeBufferPointer { srcBuf in
        dst.withUnsafeMutableBufferPointer { dstBuf in
            let s = srcBuf.baseAddress!
            let d = dstBuf.baseAddress!
            parallelForRows(rowCount: dstH, columns: dstW) { pStart, pEnd in
                let ydStart = pStart / dstW
                let ydEnd = (pEnd + dstW - 1) / dstW
                for yd in ydStart..<ydEnd {
                    let ys = (Float(yd) + 0.5) * scaleY - 0.5
                    let ys0i = Int(ys.rounded(.down))
                    let dy = ys - Float(ys0i)
                    let y0 = max(0, min(srcH - 1, ys0i))
                    let y1 = max(0, min(srcH - 1, ys0i + 1))
                    for xd in 0..<dstW {
                        let xs = (Float(xd) + 0.5) * scaleX - 0.5
                        let xs0i = Int(xs.rounded(.down))
                        let dx = xs - Float(xs0i)
                        let x0 = max(0, min(srcW - 1, xs0i))
                        let x1 = max(0, min(srcW - 1, xs0i + 1))

                        let off00 = (y0 * srcW + x0) * classes
                        let off01 = (y0 * srcW + x1) * classes
                        let off10 = (y1 * srcW + x0) * classes
                        let off11 = (y1 * srcW + x1) * classes
                        let dstOff = (yd * dstW + xd) * classes
                        for c in 0..<classes {
                            let v00 = s[off00 + c]
                            let v01 = s[off01 + c]
                            let v10 = s[off10 + c]
                            let v11 = s[off11 + c]
                            let v0 = v00 * (1 - dx) + v01 * dx
                            let v1 = v10 * (1 - dx) + v11 * dx
                            d[dstOff + c] = v0 * (1 - dy) + v1 * dy
                        }
                    }
                }
            }
        }
    }
}

// Splits a `rowCount × columns` pixel grid into contiguous row stripes and runs
// `body(pixelStart, pixelEnd)` for each stripe concurrently across CPU cores via
// `DispatchQueue.concurrentPerform`. The stripe boundaries fall on whole rows so
// callers that key off `pixel / columns` see clean row ranges. Falls back to a
// single serial invocation for small grids where dispatch overhead would dominate.
func parallelForRows(
    rowCount: Int,
    columns: Int,
    body: (_ pixelStart: Int, _ pixelEnd: Int) -> Void
) {
    let pixelCount = rowCount * columns
    let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
    // Target a few stripes per core for load balance; cap to the row count.
    let stripes = min(rowCount, max(1, cores * 2))
    guard stripes > 1, pixelCount >= 1 << 16 else {
        body(0, pixelCount)
        return
    }
    let rowsPerStripe = (rowCount + stripes - 1) / stripes
    DispatchQueue.concurrentPerform(iterations: stripes) { stripe in
        let rowStart = stripe * rowsPerStripe
        guard rowStart < rowCount else { return }
        let rowEnd = min(rowCount, rowStart + rowsPerStripe)
        body(rowStart * columns, rowEnd * columns)
    }
}
