import CaptureKit
import Foundation
import PortableContracts
import SupportPlane

// Reader for the `.depthslice` artefacts under `Fixtures/`, cut from full capture
// bundles by `tools/fixture_slice.py`.
//
// The bundles Reqs 6.2, 7.1 and 7.2 name are ~195 MB and live on the device, not in
// the repository — 199 MB of the 204 MB in `1785135663727-success.fixture` is the
// segmentation probability tensor. The support-plane fit needs none of it: the depth
// map and a food mask are the whole input. A slice is ~290 KB, so it can be
// committed, and Req 6.2 stops being a criterion only its author can run.
//
// Layout, all little-endian:
//   magic "MDSLICE1"            8 B
//   name length, name           i32 + UTF-8
//   depth w/h, colour w/h       4 x i32
//   fx, fy, cx, cy              4 x f32   (COLOUR intrinsics, not depth)
//   gravity x/y/z               3 x f32
//   depth mm                    f32 x (depth w x h)
//   confidence                  u8  x (depth w x h)
//   food mask                   u8  x (depth w x h), 1 = food
//
// The colour intrinsics are carried rather than the depth ones because
// `SupportRegion.depthIntrinsics(from:depth:)` derives depth intrinsics from colour
// and must keep doing so — device depth maps record all-zero intrinsics. The food
// mask is already on the depth grid, so the fitter's own downsample runs as the
// identity; `tools/fixture_slice.py` applies exactly the rule
// `downsampleFoodMask` would.
struct DepthSlice {
    let name: String
    let depth: DepthMap
    let colourIntrinsics: CameraIntrinsics
    let gravity: Vec3
    // Depth-grid mask. `BinaryMask` is nominally colour-grid, but the fitter
    // downsamples to the depth grid before use and that step is the identity here.
    let foodMask: BinaryMask

    // The same region expanded back onto the colour grid, for the PRE-FEATURE
    // comparison only: `LiDARPlaneFitter` enumerates colour-grid bands sized from
    // the mask's own bbox, so handing it a depth-grid mask against 1920x1440
    // intrinsics puts the bands in the wrong place and fits nothing meaningful.
    //
    // This is a lossy round trip — the slice threw away which colour pixels inside
    // a depth pixel were food — but the quantisation is one depth pixel, ~7.5
    // colour pixels, against bands as thick as the food bbox (hundreds). The
    // measured pre-feature volumes land within ~5 % of the figures the full
    // bundles produced, which is the check that this is immaterial.
    var colourFoodMask: BinaryMask {
        let cw = colourIntrinsics.imageWidth, ch = colourIntrinsics.imageHeight
        var pixels = [UInt8](repeating: 0, count: cw * ch)
        let sx = Float(depth.width) / Float(cw), sy = Float(depth.height) / Float(ch)
        for cy in 0..<ch {
            let dy = min(depth.height - 1, max(0, Int((Float(cy) + 0.5) * sy)))
            for cx in 0..<cw {
                let dx = min(depth.width - 1, max(0, Int((Float(cx) + 0.5) * sx)))
                pixels[cy * cw + cx] = foodMask.isFood(x: dx, y: dy) ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: cw, height: ch)
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case missing(String)
        case malformed(String)

        var description: String {
            switch self {
            case .missing(let name): return "depth slice \(name).depthslice is not in the bundle"
            case .malformed(let why): return "depth slice malformed: \(why)"
            }
        }
    }

    static func load(_ name: String) throws -> DepthSlice {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "depthslice", subdirectory: "Fixtures"
        ) else {
            throw Error.missing(name)
        }
        return try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> DepthSlice {
        var cursor = 0
        func take(_ count: Int, _ what: String) throws -> Data {
            guard cursor + count <= data.count else {
                throw Error.malformed("ran out of bytes reading \(what)")
            }
            defer { cursor += count }
            return data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + count))
        }
        func int32(_ what: String) throws -> Int {
            Int(try take(4, what).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        }
        func float(_ what: String) throws -> Float {
            try take(4, what).withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        }

        guard try take(8, "magic") == Data("MDSLICE1".utf8) else {
            throw Error.malformed("bad magic — not a .depthslice")
        }
        let nameLength = try int32("name length")
        guard let name = String(data: try take(nameLength, "name"), encoding: .utf8) else {
            throw Error.malformed("name is not UTF-8")
        }
        let dw = try int32("depth width"), dh = try int32("depth height")
        let cw = try int32("colour width"), ch = try int32("colour height")
        guard dw > 0, dh > 0, cw > 0, ch > 0 else { throw Error.malformed("non-positive dimensions") }

        let fx = try float("fx"), fy = try float("fy")
        let cx = try float("cx"), cy = try float("cy")
        let gravity = Vec3(try float("gx"), try float("gy"), try float("gz"))

        let samples = dw * dh
        let depthBytes = try take(samples * 4, "depth")
        let confidence = try take(samples, "confidence")
        let mask = try take(samples, "food mask")

        return DepthSlice(
            name: name,
            depth: DepthMap(
                depthBytesMm: depthBytes,
                confidenceBytes: confidence,
                width: dw, height: dh,
                rowStrideBytes: dw * 4,
                // All zeros, exactly as ARKitCaptureEngine writes it — the slice keeps
                // the trap the derivation exists to avoid rather than papering over it.
                depthIntrinsics: CameraIntrinsics(
                    fx: 0, fy: 0, cx: 0, cy: 0,
                    distortion: [], imageWidth: dw, imageHeight: dh
                ),
                depthFromColour: .identity
            ),
            colourIntrinsics: CameraIntrinsics(
                fx: fx, fy: fy, cx: cx, cy: cy,
                distortion: [], imageWidth: cw, imageHeight: ch
            ),
            gravity: gravity,
            foodMask: BinaryMask(pixels: [UInt8](mask), width: dw, height: dh)
        )
    }
}
