import CoreGraphics
import Foundation
import ImageIO
import Pipeline
import SwiftUI

// Read side of the mask artefact (UI Design Handoff 00, Decision 15). Loads the
// per-meal `mask` artefact bytes from the store, decodes the RAW 8-bit label
// indices via a `CGDataProvider` (NOT a colour-managed `UIImage` decode, which
// can remap index values), and tints each region per the deterministic
// id->colour table. Colours are applied at read time only — the stored PNG
// carries indices, never colours.
//
// The view renders ONLY the translucent tinted overlay so a parent stacks it
// over the captured photo (Segmentation review, Meal overview). On ANY miss —
// no artefact row, unreadable file, unexpected pixel format — it renders
// nothing, so the photo (or its placeholder) shows through unmodified
// (Req 6.8, photo-only fallback; never errors).
//
// `onDecode` reports the set of class indices present in the raster so callers
// can drive the §5.2 unknown / unsupported-liquid banners from the authoritative
// label map (the only place unknown/liquid regions surface — they carry no
// per-class macro entry). An empty set means "no mask / nothing to report".
struct MaskOverlayLoader: View {
    let store: any PersistenceStore
    let mealId: UUID
    // Single palette ships today; kept explicit so a future palette version can
    // shift the wheel without repainting old meals (ClassColourTable is versioned).
    var paletteVersion: String = ClassColourTable.v1.version
    var onDecode: (Set<Int>) -> Void = { _ in }

    @State private var overlay: CGImage?

    var body: some View {
        Group {
            if let overlay {
                Image(decorative: overlay, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .task(id: mealId) { await load() }
    }

    private func load() async {
        guard
            let data = try? await store.artefactData(mealId: mealId, kind: MaskOverlayDecoder.maskKind),
            let decoded = MaskOverlayDecoder.decode(pngData: data, paletteVersion: paletteVersion)
        else {
            overlay = nil
            onDecode([])
            return
        }
        overlay = decoded.overlay
        onDecode(decoded.presentClassIds)
    }
}

// A decoded mask: the tinted RGBA overlay plus the class indices present in the
// raster.
struct DecodedMask {
    let overlay: CGImage
    let presentClassIds: Set<Int>
}

// Pure decode of the 8-bit greyscale label PNG (paired with
// `MaskArtefactWriter.encodeLabelPNG` in the Pipeline). Reading the CGImage's
// own data provider gives the native sample bytes = raw class indices, with no
// colour management applied (the encode side used DeviceGray, alpha-none, no
// ICC profile).
enum MaskOverlayDecoder {
    static let maskKind = "mask"
    // Translucent so the photo underneath stays legible through the overlay.
    static let overlayAlpha: Double = 0.55

    static func decode(pngData: Data, paletteVersion: String) -> DecodedMask? {
        guard
            let source = CGImageSourceCreateWithData(pngData as CFData, nil),
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
            // One byte per pixel: the raw label raster. Anything else is not the
            // index map we wrote — fall back to photo-only.
            cg.bitsPerComponent == 8, cg.bitsPerPixel == 8,
            let provider = cg.dataProvider,
            let raw = provider.data
        else { return nil }

        let width = cg.width
        let height = cg.height
        let bytesPerRow = cg.bytesPerRow
        guard width > 0, height > 0, bytesPerRow >= width else { return nil }
        guard CFDataGetLength(raw) >= bytesPerRow * height,
              let labels = CFDataGetBytePtr(raw) else { return nil }

        let palette = ClassPalette.v1Standard
        let table = ClassColourTable(version: paletteVersion)
        let background = palette.background

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var present = Set<Int>()
        // Cache the premultiplied bytes per index — a mask has a handful of
        // distinct classes over tens of thousands of pixels.
        var cache: [Int: (UInt8, UInt8, UInt8, UInt8)] = [:]

        rgba.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let rowStart = y * bytesPerRow
                for x in 0..<width {
                    let idx = Int(labels[rowStart + x])
                    if idx == background { continue }  // transparent
                    present.insert(idx)
                    let px: (UInt8, UInt8, UInt8, UInt8)
                    if let cached = cache[idx] {
                        px = cached
                    } else {
                        let c = table.colour(forClassId: idx)
                        px = (
                            byte(c.red * overlayAlpha),
                            byte(c.green * overlayAlpha),
                            byte(c.blue * overlayAlpha),
                            byte(overlayAlpha)
                        )
                        cache[idx] = px
                    }
                    let o = (y * width + x) * 4
                    out[o] = px.0
                    out[o + 1] = px.1
                    out[o + 2] = px.2
                    out[o + 3] = px.3
                }
            }
        }

        guard let outProvider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let overlay = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: outProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return DecodedMask(overlay: overlay, presentClassIds: present)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }
}
