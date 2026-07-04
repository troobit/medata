import Foundation
import CaptureKit
#if canImport(CoreML)
import CoreML
#endif
#if DEBUG
import os

// Dev-build-only sub-stage log on the `ie.medata.app` / `Shutter` channel.
// Same channel as Pipeline's per-stage start log (`pipeline.stage.start`), so
// a single Console.app predicate captures the full trail and the hanging
// segmenter sub-stage is identifiable by which `segmenter.substage.start`
// line is last in the log.
private let segmenterLog = Logger(subsystem: "ie.medata.app", category: "Shutter")
#endif

// Inference engine protocol: takes the FP16 LE HWC buffer produced by
// SegmenterPreProcessor and returns logits of shape [targetSize × targetSize × C]
// as row-major FP32. Decoupling the engine from the wrapper keeps tests free of
// any dependency on a real Core ML model, and lets the same code drive
// Core ML (production), TFLite (validation), or a stub (tests).
public protocol SegmenterInferenceEngine: Sendable {
    func runInference(
        inputFP16Bytes: Data, targetSize: Int
    ) async throws -> (logits: [Float], classes: Int)
}

public final class CoreMLSegmenter: @unchecked Sendable {
    // Filesystem path (string, not URL — P8 portability). The Android co-developer's
    // TFLite wrapper consumes the same string contract.
    public let modelPathString: String
    public let palette: ClassPalette
    public let targetSize: Int
    private let engine: SegmenterInferenceEngine

    // Version of the loaded Core ML model (the checkpoint SHA-256 prefix stamped
    // by tools/segmenter/export.py). `nil` for the dev-stub engine, which has no
    // bundled model. Read by `Pipeline.segmenterSourceTag` to stamp
    // `coreml_<modelVersion>` onto produced meals (Req 5.4).
    public let modelVersion: String?

    public init(
        modelPath: String,
        palette: ClassPalette,
        engine: SegmenterInferenceEngine,
        targetSize: Int = SegmenterPreProcessor.defaultTargetSize,
        modelVersion: String? = nil
    ) {
        self.modelPathString = modelPath
        self.palette = palette
        self.engine = engine
        self.targetSize = targetSize
        self.modelVersion = modelVersion
    }

    public func segment(_ frame: RawFrame) async throws -> SegmentationResult {
        #if DEBUG
        segmenterLog.info("event=segmenter.substage.start name=preprocess width=\(frame.imageWidth, privacy: .public) height=\(frame.imageHeight, privacy: .public)")
        #endif
        let pre = try SegmenterPreProcessor.process(
            imageBytes: frame.imageBytes,
            pixelFormat: frame.pixelFormat,
            width: frame.imageWidth, height: frame.imageHeight,
            targetSize: targetSize
        )
        #if DEBUG
        segmenterLog.info("event=segmenter.substage.start name=inference targetSize=\(pre.targetSize, privacy: .public)")
        #endif
        let (logits, classes) = try await engine.runInference(
            inputFP16Bytes: pre.bytes, targetSize: pre.targetSize
        )
        #if DEBUG
        segmenterLog.info("event=segmenter.substage.start name=postprocess scaledWidth=\(pre.scaledWidth, privacy: .public) scaledHeight=\(pre.scaledHeight, privacy: .public) originalWidth=\(pre.originalWidth, privacy: .public) originalHeight=\(pre.originalHeight, privacy: .public) classes=\(classes, privacy: .public)")
        #endif
        let post = try SegmenterPostProcessor.process(
            logitsFP32: logits,
            targetSize: pre.targetSize, classes: classes,
            scaledWidth: pre.scaledWidth, scaledHeight: pre.scaledHeight,
            originalWidth: pre.originalWidth, originalHeight: pre.originalHeight,
            palette: palette
        )
        return SegmentationResult(
            probabilities: post.probabilities,
            argmax: post.argmax,
            perClassMeanProb: post.perClassMeanProb,
            sigmaSeg: post.sigmaSeg
        )
    }
}

// MARK: - Weights size budget (Req 8.2)

public enum SegmenterWeightsBudget {
    // Req 8.2 as amended by model-production Decision 13: the Decision 25
    // architecture is 22.1 MB at FP16, so the original 10 MB ceiling was
    // unachievable; 24 MiB fits FP16 and still catches an accidental FP32 export.
    public static let maxBytes: Int = 24 * 1024 * 1024

    // Core ML packages are bundle directories; we sum file sizes recursively.
    public static func validate(at path: String, maxBytes: Int = maxBytes) throws {
        let url = URL(fileURLWithPath: path)
        let size = try totalBytes(at: url)
        guard size <= maxBytes else {
            throw SegmentationError.weightsBudgetExceeded(actual: size, max: maxBytes)
        }
    }

    public static func totalBytes(at url: URL) throws -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw SegmentationError.modelLoadFailed("path does not exist: \(url.path)")
        }
        if !isDir.boolValue {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            return (attrs[.size] as? Int) ?? 0
        }
        var total = 0
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return 0
        }
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true {
                total += values.fileSize ?? 0
            }
        }
        return total
    }
}

#if canImport(CoreML) && (os(iOS) || os(macOS))

// Production Core ML inference engine. ANE selected via .all compute units per
// Decision 25 / Req 16.5; dev builds may force .cpuOnly for reproducibility.
//
// The model is expected to expose a single float input (shape [1, 3, target, target] CHW
// or [1, target, target, 3] HWC) and a single multi-array output of logits in either
// CHW [1, C, target, target] or HWC [1, target, target, C]. The output shape is
// resolved at load time from the model description.
public final class CoreMLInferenceEngine: SegmenterInferenceEngine, @unchecked Sendable {
    // Key under the model's user-defined metadata holding the model version —
    // the first 12 hex of the training checkpoint SHA-256 (Req 1.3). Stamped by
    // tools/segmenter/export.py (task 7); this string is the shared contract
    // between the exporter and this loader, so the two must stay identical.
    public static let modelVersionMetadataKey = "medata.modelVersion"

    // Back-compat fallback used when a loaded model carries no
    // `medata.modelVersion` (e.g. older fixtures, or a model exported before the
    // stamp landed). Never produces an empty version tag.
    public static let fallbackModelVersion: String = "v0.1"

    // Pure, testable resolution of the model version from a model's user-defined
    // metadata dictionary: returns the stamped value, or the fallback when the
    // key is absent or empty (Req 5.4 — never an empty `coreml_` tag).
    public static func resolveModelVersion(fromUserMetadata metadata: [String: String]) -> String {
        if let v = metadata[modelVersionMetadataKey], !v.isEmpty { return v }
        return fallbackModelVersion
    }

    // Version of THIS loaded model, derived from its metadata at init. Stamped
    // onto every Phase 3 MealRecord as `coreml_<modelVersion>` (Req 5.4,
    // Decision 42) so a persisted meal is traceable to its exact model build.
    public let modelVersion: String

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let inputIsCHW: Bool
    private let outputIsCHW: Bool
    private let classes: Int
    private let targetSize: Int

    public init(modelPath: String, useNeuralEngine: Bool = true, targetSize: Int) throws {
        let url = URL(fileURLWithPath: modelPath)
        let compiled: URL
        if url.pathExtension == "mlmodel" {
            compiled = try MLModel.compileModel(at: url)
        } else {
            compiled = url
        }
        let cfg = MLModelConfiguration()
        cfg.computeUnits = useNeuralEngine ? .all : .cpuOnly
        let loaded: MLModel
        do {
            loaded = try MLModel(contentsOf: compiled, configuration: cfg)
        } catch {
            throw SegmentationError.modelLoadFailed("MLModel load failed: \(error.localizedDescription)")
        }
        self.model = loaded
        self.targetSize = targetSize

        let userMeta = (loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String]) ?? [:]
        self.modelVersion = Self.resolveModelVersion(fromUserMetadata: userMeta)

        let inDescs = loaded.modelDescription.inputDescriptionsByName
        guard let inEntry = inDescs.first(where: { $1.type == .multiArray }) else {
            throw SegmentationError.modelLoadFailed("model has no multi-array input")
        }
        self.inputName = inEntry.key
        let inShape = inEntry.value.multiArrayConstraint?.shape.map(\.intValue) ?? []
        self.inputIsCHW = Self.detectCHW(shape: inShape, channelHint: 3, targetSize: targetSize)

        let outDescs = loaded.modelDescription.outputDescriptionsByName
        guard let outEntry = outDescs.first(where: { $1.type == .multiArray }) else {
            throw SegmentationError.modelLoadFailed("model has no multi-array output")
        }
        self.outputName = outEntry.key
        let outShape = outEntry.value.multiArrayConstraint?.shape.map(\.intValue) ?? []
        let (isCHW, c) = Self.detectClassesAndLayout(shape: outShape, targetSize: targetSize)
        self.outputIsCHW = isCHW
        self.classes = c
    }

    public func runInference(
        inputFP16Bytes: Data, targetSize: Int
    ) async throws -> (logits: [Float], classes: Int) {
        precondition(targetSize == self.targetSize, "engine targetSize mismatch")
        let array = try makeInputArray(fromHWCFP16: inputFP16Bytes, targetSize: targetSize)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: array)
        ])
        let result: MLFeatureProvider
        do {
            result = try await model.prediction(from: provider)
        } catch {
            throw SegmentationError.modelInferenceFailed("Core ML prediction failed: \(error.localizedDescription)")
        }
        guard let multi = result.featureValue(for: outputName)?.multiArrayValue else {
            throw SegmentationError.modelInferenceFailed("missing output \(outputName)")
        }
        let logits = try unpackLogits(multi, targetSize: targetSize, classes: classes, chw: outputIsCHW)
        return (logits, classes)
    }

    private func makeInputArray(fromHWCFP16 hwc: Data, targetSize: Int) throws -> MLMultiArray {
        let h = targetSize, w = targetSize, c = 3
        let shape: [NSNumber] = inputIsCHW
            ? [1, NSNumber(value: c), NSNumber(value: h), NSNumber(value: w)]
            : [1, NSNumber(value: h), NSNumber(value: w), NSNumber(value: c)]
        let arr = try MLMultiArray(shape: shape, dataType: .float16)
        let hwcFloats = FP16Bytes.decode(hwc, count: h * w * c)
        arr.withUnsafeMutableBytes { ptr, _ in
            let dst = ptr.bindMemory(to: Float16.self).baseAddress!
            if inputIsCHW {
                // HWC → CHW.
                for y in 0..<h {
                    for x in 0..<w {
                        let src = (y * w + x) * c
                        for chan in 0..<c {
                            let dstIdx = chan * h * w + y * w + x
                            dst[dstIdx] = Float16(hwcFloats[src + chan])
                        }
                    }
                }
            } else {
                // HWC layout already matches.
                for i in 0..<(h * w * c) { dst[i] = Float16(hwcFloats[i]) }
            }
        }
        return arr
    }

    private func unpackLogits(
        _ arr: MLMultiArray, targetSize: Int, classes: Int, chw: Bool
    ) throws -> [Float] {
        let h = targetSize, w = targetSize
        var logits = [Float](repeating: 0, count: h * w * classes)
        let dt = arr.dataType
        switch dt {
        case .float32:
            arr.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Float.self).baseAddress!
                writeLogits(src: { i in src[i] },
                            into: &logits,
                            chw: chw, h: h, w: w, classes: classes)
            }
        case .float16:
            arr.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Float16.self).baseAddress!
                writeLogits(src: { i in Float(src[i]) },
                            into: &logits,
                            chw: chw, h: h, w: w, classes: classes)
            }
        case .double:
            arr.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Double.self).baseAddress!
                writeLogits(src: { i in Float(src[i]) },
                            into: &logits,
                            chw: chw, h: h, w: w, classes: classes)
            }
        default:
            throw SegmentationError.modelInferenceFailed("unsupported output dtype \(dt)")
        }
        return logits
    }

    private func writeLogits(
        src: (Int) -> Float,
        into logits: inout [Float],
        chw: Bool, h: Int, w: Int, classes: Int
    ) {
        if chw {
            // [1, C, H, W] → [H, W, C] row-major.
            for c in 0..<classes {
                let cBase = c * h * w
                for y in 0..<h {
                    let srcRow = cBase + y * w
                    for x in 0..<w {
                        logits[(y * w + x) * classes + c] = src(srcRow + x)
                    }
                }
            }
        } else {
            // [1, H, W, C] → [H, W, C].
            for i in 0..<(h * w * classes) { logits[i] = src(i) }
        }
    }

    // Layout detector: if the channel-3 slot lies before the two spatial dims, treat
    // as CHW; otherwise HWC. The shape may include a leading batch dimension.
    private static func detectCHW(shape: [Int], channelHint: Int, targetSize: Int) -> Bool {
        // Strip leading 1s (batch / unit dims).
        var s = shape
        while let first = s.first, first <= 1 { s.removeFirst() }
        // Expect three dims now: [C, H, W] or [H, W, C].
        guard s.count >= 3 else { return false }
        if s[0] == channelHint && s[1] == targetSize { return true }
        return false
    }

    private static func detectClassesAndLayout(shape: [Int], targetSize: Int) -> (chw: Bool, classes: Int) {
        var s = shape
        while let first = s.first, first <= 1 { s.removeFirst() }
        if s.count >= 3 {
            // [C, H, W] if H/W positions match targetSize.
            if s[1] == targetSize && s[2] == targetSize { return (true, s[0]) }
            if s[0] == targetSize && s[1] == targetSize { return (false, s[2]) }
        }
        return (true, 0)
    }
}
#endif
