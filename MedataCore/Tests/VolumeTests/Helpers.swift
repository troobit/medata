import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// Shared test helpers for VolumeTests.

// 2 food classes + bg(2) + unknownFood(3) + liquid(4) = 5 classes total.
func makePalette(numFood: Int = 2) -> ClassPalette {
    ClassPalette(
        foodClasses: (0..<numFood).map { "food_\($0)" },
        background: numFood,
        unknownFood: numFood + 1,
        unsupportedLiquid: numFood + 2,
        version: "test"
    )
}

// Build an FP16 HWC probability tensor. `probs(y, x, c)` returns the probability.
func makeProbTensor(
    width: Int, height: Int, palette: ClassPalette,
    probs: (Int, Int, Int) -> Float
) -> ProbabilityTensor {
    let c = palette.totalClasses
    var bytes = Data(count: height * width * c * 2)
    bytes.withUnsafeMutableBytes { raw in
        let buf = raw.bindMemory(to: Float16.self).baseAddress!
        for y in 0..<height {
            for x in 0..<width {
                let off = (y * width + x) * c
                for k in 0..<c {
                    buf[off + k] = Float16(probs(y, x, k))
                }
            }
        }
    }
    return ProbabilityTensor(bytes: bytes, height: height, width: width, classes: c, palette: palette)
}

// Build an ArgmaxMap. `label(y, x)` returns UInt8 class index.
func makeArgmax(width: Int, height: Int, label: (Int, Int) -> Int) -> ArgmaxMap {
    var pixels = Data(count: height * width)
    pixels.withUnsafeMutableBytes { raw in
        let buf = raw.bindMemory(to: UInt8.self).baseAddress!
        for y in 0..<height {
            for x in 0..<width {
                buf[y * width + x] = UInt8(label(y, x))
            }
        }
    }
    return ArgmaxMap(pixels: pixels, height: height, width: width)
}

// Build a DepthMap. `depthMm(y, x)` and `conf(y, x)` (0..255).
func makeDepthMap(
    width: Int, height: Int,
    intrinsics: CameraIntrinsics,
    depthMm: (Int, Int) -> Float,
    conf: (Int, Int) -> UInt8 = { _, _ in 255 }
) -> DepthMap {
    var depthBytes = Data(count: width * height * 4)
    var confBytes = Data(count: width * height)
    depthBytes.withUnsafeMutableBytes { rawD in
        confBytes.withUnsafeMutableBytes { rawC in
            let dBuf = rawD.bindMemory(to: Float.self).baseAddress!
            let cBuf = rawC.bindMemory(to: UInt8.self).baseAddress!
            for y in 0..<height {
                for x in 0..<width {
                    dBuf[y * width + x] = depthMm(y, x)
                    cBuf[y * width + x] = conf(y, x)
                }
            }
        }
    }
    return DepthMap(
        depthBytesMm: depthBytes,
        confidenceBytes: confBytes,
        width: width, height: height,
        rowStrideBytes: width * 4,
        depthIntrinsics: intrinsics,
        depthFromColour: .identity
    )
}

// Build a BinaryMask. `food(y, x)` returns true for food pixels.
func makeBinaryMask(width: Int, height: Int, food: (Int, Int) -> Bool) -> BinaryMask {
    let pixels = (0..<height).flatMap { y in
        (0..<width).map { x in food(y, x) ? UInt8(1) : UInt8(0) }
    }
    return BinaryMask(pixels: pixels, width: width, height: height)
}
