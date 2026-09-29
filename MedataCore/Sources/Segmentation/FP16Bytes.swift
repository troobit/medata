import Foundation

// Float16 encode/decode for the portable §6.0 contract (FP16 IEEE-754 binary16, LE,
// HWC row-major). Apple Silicon and modern Intel Macs store Float16 little-endian
// natively, so a raw memcpy is correct on every platform this package targets.

public enum FP16Bytes {
    public static func encode(_ values: [Float]) -> Data {
        var data = Data(count: values.count * 2)
        data.withUnsafeMutableBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: Float16.self).baseAddress!
            for i in 0..<values.count {
                buf[i] = Float16(values[i])
            }
        }
        return data
    }

    public static func decode(_ data: Data, count: Int) -> [Float] {
        precondition(data.count == count * 2, "FP16 byte size mismatch")
        return data.withUnsafeBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: Float16.self).baseAddress!
            return (0..<count).map { Float(buf[$0]) }
        }
    }
}
