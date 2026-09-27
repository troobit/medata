// Apple Vision foreground baseline: VNGenerateForegroundInstanceMaskRequest
// (macOS 14+ / iOS 17+), union of all instances, written as an 8-bit PNG mask.
//
// Usage: swiftc -O vision_foreground.swift -o out/vision_foreground
//        out/vision_foreground <in-dir of PNGs> <out-dir>
// Prints one JSON object {stem: seconds} of wall-clock per image to stdout.
// Inputs must already be EXIF-upright (run_vision.py writes them).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: vision_foreground <in-dir> <out-dir>\n".data(using: .utf8)!)
    exit(2)
}
let inDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func writeMask(_ bytes: [UInt8], width: Int, height: Int, to url: URL) {
    let data = Data(bytes)
    let provider = CGDataProvider(data: data as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                        decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

var timings: [String: Double] = [:]
let files = try FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
    .sorted { $0.path < $1.path }

for url in files {
    let stem = url.deletingPathExtension().lastPathComponent
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let (w, h) = (cg.width, cg.height)
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    let t0 = Date()
    try handler.perform([request])
    var out = [UInt8](repeating: 0, count: w * h)
    if let result = request.results?.first, !result.allInstances.isEmpty {
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        timings[stem] = Date().timeIntervalSince(t0)
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        let mw = CVPixelBufferGetWidth(mask), mh = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float>.size
        let base = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: Float.self)
        precondition(mw == w && mh == h, "scaled mask \(mw)x\(mh) != image \(w)x\(h)")
        for y in 0..<h { for x in 0..<w where base[y * stride + x] > 0.5 { out[y * w + x] = 255 } }
        CVPixelBufferUnlockBaseAddress(mask, .readOnly)
    } else {
        timings[stem] = Date().timeIntervalSince(t0)
    }
    writeMask(out, width: w, height: h, to: outDir.appendingPathComponent("\(stem).png"))
}

let json = try JSONSerialization.data(withJSONObject: timings, options: [.sortedKeys])
print(String(data: json, encoding: .utf8)!)
