import Accelerate
import CoreVideo
import Foundation
import PortableContracts

// Capture-boundary CVPixelBuffer→BGRA8 conversion per spec
// `rawframe-rgb-conversion`. Used by ARKitCaptureEngine.buildRawFrame in place
// of the previous copyPixelBufferBytes / detectPixelFormat helpers, and reachable
// from any future macOS HarnessCLI tool that needs to read pixels from a
// CVPixelBuffer without an ARSession (Decision 3).
//
// Conversion backend is vImage's biplanar YpCbCr→ARGB path with a permute map
// `[3, 2, 1, 0]` that lands the bytes in BGRA order. The full-range BT.601
// pixel range matches `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` —
// ARKit's `ARFrame.capturedImage` format on every supported device. The cached
// `vImage_YpCbCrToARGB` info struct is built once on first call (Req 4.3).
public enum PixelBufferAdapter {
    public enum ConversionError: Error, Equatable {
        case unsupportedSourceFormat(fourCC: String)
        case conversionFailed(vImageErrorCode: Int)
    }

    public struct Output {
        public let bytes: Data
        public let format: PixelFormat
        public let width: Int
        public let height: Int
    }

    public static func convert(_ buffer: CVPixelBuffer) throws -> Output {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let fmt = CVPixelBufferGetPixelFormatType(buffer)

        switch fmt {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            // Full-range and video-range share the same plane layout; the
            // cached info struct is generated for full-range to match ARKit.
            return try convertYCbCr(buffer, width: width, height: height)

        case kCVPixelFormatType_32BGRA:
            let bytes = try copyContiguous(buffer, bytesPerPixel: 4)
            return Output(bytes: bytes, format: .bgra8, width: width, height: height)

        case kCVPixelFormatType_32RGBA:
            let bytes = try copyContiguous(buffer, bytesPerPixel: 4)
            return Output(bytes: bytes, format: .rgba8, width: width, height: height)

        default:
            throw ConversionError.unsupportedSourceFormat(fourCC: fourCCString(fmt))
        }
    }

    // MARK: - YCbCr → BGRA via vImage

    private static func convertYCbCr(_ buffer: CVPixelBuffer,
                                     width: Int, height: Int) throws -> Output {
        let lockStatus = CVPixelBufferLockBaseAddress(buffer, .readOnly)
        guard lockStatus == kCVReturnSuccess else {
            throw ConversionError.conversionFailed(vImageErrorCode: Int(lockStatus))
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else {
            throw ConversionError.conversionFailed(vImageErrorCode: Int(kvImageInvalidParameter))
        }

        var ySrc = vImage_Buffer(
            data: yBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        )
        var cbcrSrc = vImage_Buffer(
            data: cbcrBase,
            height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(buffer, 1)),
            width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(buffer, 1)),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        )

        // Destination buffer: contiguous, rowBytes = width * 4 (Req 1.3).
        let destRowBytes = width * 4
        var destBytes = Data(count: height * destRowBytes)
        let convertErr: vImage_Error = destBytes.withUnsafeMutableBytes { rawDest -> vImage_Error in
            guard let destBase = rawDest.baseAddress else { return kvImageInternalError }
            var dest = vImage_Buffer(
                data: destBase,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: destRowBytes
            )
            var info = ConversionInfoCache.shared.info
            let permuteMap: [UInt8] = [3, 2, 1, 0]
            return vImageConvert_420Yp8_CbCr8ToARGB8888(
                &ySrc, &cbcrSrc, &dest, &info,
                permuteMap, 255, vImage_Flags(kvImageNoFlags)
            )
        }
        guard convertErr == kvImageNoError else {
            throw ConversionError.conversionFailed(vImageErrorCode: Int(convertErr))
        }
        return Output(bytes: destBytes, format: .bgra8, width: width, height: height)
    }

    // MARK: - BGRA / RGBA passthrough (collapse per-row stride padding)

    private static func copyContiguous(_ buffer: CVPixelBuffer,
                                       bytesPerPixel: Int) throws -> Data {
        let lockStatus = CVPixelBufferLockBaseAddress(buffer, .readOnly)
        guard lockStatus == kCVReturnSuccess else {
            throw ConversionError.conversionFailed(vImageErrorCode: Int(lockStatus))
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let srcStride = CVPixelBufferGetBytesPerRow(buffer)
        let dstStride = width * bytesPerPixel

        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw ConversionError.conversionFailed(vImageErrorCode: Int(kvImageInvalidParameter))
        }

        if srcStride == dstStride {
            return Data(bytes: base, count: dstStride * height)
        }
        var out = Data(count: dstStride * height)
        out.withUnsafeMutableBytes { rawDst in
            guard let dst = rawDst.baseAddress else { return }
            for row in 0..<height {
                memcpy(dst.advanced(by: row * dstStride),
                       base.advanced(by: row * srcStride),
                       dstStride)
            }
        }
        return out
    }

    // MARK: - FourCC rendering

    private static func fourCCString(_ value: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        if let str = String(bytes: bytes, encoding: .ascii), bytes.allSatisfy({ (0x20...0x7E).contains($0) }) {
            return str
        }
        return String(format: "0x%08X", value)
    }
}

// MARK: - Cached vImage conversion info (built once per process)

// The `vImage_YpCbCrToARGB` info struct is a C value type with no reference
// fields; we initialise it once and treat the cached instance as immutable
// read-only state from then on. Wrapped in a class to make the singleton
// trivially Sendable for cross-actor reads from `PixelBufferAdapter.convert`.
private final class ConversionInfoCache: @unchecked Sendable {
    static let shared = ConversionInfoCache()
    let info: vImage_YpCbCrToARGB

    private init() {
        var info = vImage_YpCbCrToARGB()
        // Full-range BT.601: Yp 0..255, Cb/Cr 0..255 with zero offset 128.
        var range = vImage_YpCbCrPixelRange(
            Yp_bias: 0,
            CbCr_bias: 128,
            YpRangeMax: 255,
            CbCrRangeMax: 255,
            YpMax: 255,
            YpMin: 0,
            CbCrMax: 255,
            CbCrMin: 0
        )
        let err = vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
            &range,
            &info,
            kvImage420Yp8_CbCr8,
            kvImageARGB8888,
            vImage_Flags(kvImageNoFlags)
        )
        precondition(err == kvImageNoError,
                     "vImage YpCbCr→ARGB conversion-info generation failed: \(err)")
        self.info = info
    }
}
