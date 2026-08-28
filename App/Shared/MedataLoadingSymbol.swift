import SwiftUI

// The Medata brand mark rendered as a sequential "draw-on" loading symbol.
//
// The glyph is the three-stroke mark from `static/icon.svg` — a 128×128 SVG
// with a 24-unit round-capped stroke in `#63FF00`: the bowl-and-stem, the
// right-hand bar, and the centre dot. `MedataLoadingSymbol` animates those
// three strokes in order (bowl, then bar, then dot) so the mark appears to be
// drawn by hand, and reuses that as an indeterminate loading indicator.
//
// Spec: `specs/ui/loading-symbol-animation/smolspec.md`.
// Brand accent is `Color.medataAccent` (design-system/MASTER.md).
//
// Usage:
//   MedataLoadingSymbol()                        // looping loader, 64 pt
//   MedataLoadingSymbol(mode: .once, size: 120)  // one-shot draw-in (launch)
struct MedataLoadingSymbol: View {
    enum Mode {
        /// Draw in, then erase out, forever — an indeterminate spinner.
        case loop
        /// Draw in once and hold the finished mark.
        case once
    }

    var mode: Mode = .loop
    var size: CGFloat = 64
    var colour: Color = .medataAccent
    /// One full draw-in takes this long; a loop cycle is draw-in + erase-out.
    var cycleDuration: Double = 1.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    // Stroke width as a fraction of the view side, preserving icon.svg's
    // 24/128 ratio so the mark reads identically at any size.
    private var lineWidth: CGFloat {
        size * MedataSymbolGeometry.strokeWidth / MedataSymbolGeometry.canvasSide
    }

    // Sequential draw windows over the single 0→1 driver: the bowl draws first,
    // the bar follows, and the dot pops in last. Splitting one driver into three
    // windows keeps the timing deterministic and the loop a single animation.
    private var bowlProgress: Double { Self.segment(progress, from: 0.0, to: 0.55) }
    private var barProgress: Double { Self.segment(progress, from: 0.55, to: 0.80) }
    private var dotProgress: Double { Self.segment(progress, from: 0.80, to: 1.0) }

    var body: some View {
        ZStack {
            MedataSymbolGeometry.Bowl()
                .trim(from: 0, to: bowlProgress)
                .stroke(colour, style: strokeStyle)
            MedataSymbolGeometry.Bar()
                .trim(from: 0, to: barProgress)
                .stroke(colour, style: strokeStyle)
            MedataSymbolGeometry.Dot(diameter: lineWidth)
                .fill(colour)
                // The dot sits on the canvas centre, so scaling about the frame
                // centre scales it in place.
                .scaleEffect(0.4 + 0.6 * dotProgress)
                .opacity(dotProgress)
        }
        .frame(width: size, height: size)
        .onAppear(perform: startAnimating)
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("medata.loadingSymbol")
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    private func startAnimating() {
        guard !reduceMotion else {
            // Reduce Motion (accessibility): present the finished mark with no
            // draw-on animation.
            progress = 1
            return
        }
        switch mode {
        case .loop:
            withAnimation(.easeInOut(duration: cycleDuration).repeatForever(autoreverses: true)) {
                progress = 1
            }
        case .once:
            withAnimation(.easeInOut(duration: cycleDuration)) {
                progress = 1
            }
        }
    }

    /// Maps the global 0→1 driver into a local 0→1 for the window [from, to].
    private static func segment(_ value: Double, from start: Double, to end: Double) -> Double {
        guard end > start else { return value >= end ? 1 : 0 }
        return min(1, max(0, (value - start) / (end - start)))
    }
}

// The three strokes of the Medata mark, authored in the same 128×128 canvas as
// `static/icon.svg`. Each shape maps canvas coordinates into the draw rect, so a
// single source of truth drives both the static icon and this animated loader.
enum MedataSymbolGeometry {
    static let canvasSide: CGFloat = 128
    static let strokeWidth: CGFloat = 24

    // Canvas-space control points (y-down, matching SVG and SwiftUI).
    private static let bowlStart = CGPoint(x: 24, y: 24)
    private static let bowlControl1 = CGPoint(x: 130, y: 24)
    private static let bowlControl2 = CGPoint(x: 130, y: 104)
    private static let bowlEnd = CGPoint(x: 24, y: 104)
    private static let stemEnd = CGPoint(x: 24, y: 64)
    private static let barTop = CGPoint(x: 104, y: 64)
    private static let barBottom = CGPoint(x: 104, y: 104)
    private static let dotCentre = CGPoint(x: 64, y: 64)

    // Maps a canvas point into `rect`: uniform scale, centred, and inset by half
    // the stroke width so the round caps are never clipped at the edges.
    static func map(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let side = min(rect.width, rect.height)
        let stroke = side * strokeWidth / canvasSide
        let scale = (side - stroke) / canvasSide
        let originX = rect.midX - side / 2 + stroke / 2
        let originY = rect.midY - side / 2 + stroke / 2
        return CGPoint(x: originX + point.x * scale, y: originY + point.y * scale)
    }

    // Stroke 1: the bowl curve from the top-left, bulging right to the
    // bottom-left, then the inner stem up to the mid-left.
    struct Bowl: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: map(bowlStart, in: rect))
            path.addCurve(
                to: map(bowlEnd, in: rect),
                control1: map(bowlControl1, in: rect),
                control2: map(bowlControl2, in: rect)
            )
            path.addLine(to: map(stemEnd, in: rect))
            return path
        }
    }

    // Stroke 2: the short vertical bar on the right.
    struct Bar: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: map(barTop, in: rect))
            path.addLine(to: map(barBottom, in: rect))
            return path
        }
    }

    // Stroke 3: the centre dot — the SVG's degenerate round-capped segment,
    // drawn here as a filled circle of the same diameter as the stroke width.
    struct Dot: Shape {
        var diameter: CGFloat
        func path(in rect: CGRect) -> Path {
            let centre = map(dotCentre, in: rect)
            return Path(ellipseIn: CGRect(
                x: centre.x - diameter / 2,
                y: centre.y - diameter / 2,
                width: diameter,
                height: diameter
            ))
        }
    }
}

#if DEBUG
#Preview("Loading symbol") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 48) {
            MedataLoadingSymbol()
            MedataLoadingSymbol(mode: .once, size: 120)
        }
    }
}
#endif
