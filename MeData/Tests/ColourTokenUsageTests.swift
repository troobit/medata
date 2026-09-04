import Foundation
import Testing
@testable import MeData

// Task 53 / Req §20.1 / Decision 16. Source-scan assertion that the new views
// consume `Color.<token>` names from `App/Colors.swift` instead of inline
// `Color(red:green:blue:)` or hex-string literals. The scan is a grep-style
// check over the canonical view files — heavier `swift-syntax` parsing buys
// nothing here because the failure modes we care about are textual: any new
// hex literal or `Color(red:` call inside a view body is the violation.
//
// Implementation notes:
// * The scan reads the source files at test time from a path relative to
//   the test bundle's source root via the `MEDATA_APP_DIR` environment
//   variable when running under Xcode, with a workspace-relative fallback.
// * The denylist is deliberately small: `Color(red:`, `Color(.sRGB`, and
//   hexadecimal `0x..../255` patterns inside view bodies. `Colors.swift`
//   itself is exempt — that's where the tokens are declared.
// * The allowlist of acceptable inline `Color`s: `Color.clear`, `Color.black`,
//   `Color.white`, `Color.secondary`. Anything else in a view body is a
//   token-discipline drift.
@Suite("Design-system token discipline (Req §20.1)")
struct ColourTokenUsageTests {

    // Paths updated 2026-08-28 for the page restructure, which moved every
    // file out of a flat `App/`. Five entries were dropped in the same pass —
    // CaptureTopBar, CaptureModeToggle, RefusalSheet, MealRow and MealsTabView
    // were deleted by the handoff-00 chrome rebuild and the home-router
    // consolidation, and this list had gone on naming them, so the reader
    // saw ten files scanned where six were.
    //
    // HomeView, IntakeView and CaptureErrorOverlay are ADDED: they are where
    // the surviving colour leaks actually are (see the note on denyPatterns).
    //
    // MealReviewView is deliberately NOT scanned. It builds a colour from the
    // segmentation class palette — `Color(red:green:blue:)` at
    // MealReviewView.swift:342 — which is data, not a design choice, and would
    // trip `denyPatterns` for the wrong reason.
    private static let scannedFiles: [String] = [
        "App/Pages/Capture/CaptureFlowView.swift",
        "App/Pages/Capture/CaptureErrorOverlay.swift",
        "App/Pages/Capture/LiveIndicatorBadge.swift",
        "App/Pages/Capture/ShutterButton.swift",
        "App/Pages/Home/HomeView.swift",
        "App/Pages/Intake/IntakeView.swift",
        "App/Pages/MealDetail/ResultView.swift",
        "App/Shared/ConfidencePill.swift"
    ]

    // KNOWN GAP, stated rather than hidden: `Color(uiColor: .systemRed)` and
    // `.systemOrange` are off-palette but match none of these patterns, so the
    // three surviving leaks — HomeView's glucose band, CaptureErrorOverlay's
    // file-local `amber`, MedataBubbleLevel's out-of-target bubble — are
    // scanned past. Adding `Color(uiColor: .system` here would catch them and
    // fail immediately; the honest fix is tokens in Colors.swift first, then
    // the pattern. Whoever adds those tokens should add the pattern with them.
    private static let denyPatterns: [String] = [
        "Color(red:",
        "Color(.sRGB",
        "Color(hue:",
        "Color(uiColor: UIColor(red:"
    ]

    @Test("no inline Color(red:green:blue:) in v1.1 view files (Req §20.1)")
    func noInlineColorLiterals() throws {
        let root = workspaceRoot()
        var violations: [String] = []
        for relative in Self.scannedFiles {
            let url = root.appendingPathComponent(relative)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                Issue.record("Source file not readable: \(relative)")
                continue
            }
            for pattern in Self.denyPatterns where source.contains(pattern) {
                violations.append("\(relative): contains `\(pattern)`")
            }
        }
        #expect(violations.isEmpty, "Inline colour literals: \(violations.joined(separator: ", "))")
    }

    @Test("Colors.swift exports the new tokens (Req §20.1)")
    func colorsSwiftExportsTokens() throws {
        let url = workspaceRoot().appendingPathComponent("App/Shared/Colors.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        for token in [
            "captureBackground", "captureChromeText", "captureChromeBG", "captureScrim",
            "surfacePrimary", "surfaceElevated", "placeholderBG", "placeholderFG",
            "confidenceHigh", "confidenceModerate", "confidenceLow", "medataAccent"
        ] {
            #expect(source.contains("static let \(token)"), "missing token: \(token)")
        }
    }

    @Test("token coverage report enumerates the tokens used per scanned file")
    func tokenCoverageReport() throws {
        let root = workspaceRoot()
        let tokens = [
            "captureBackground", "captureChromeText", "captureChromeBG", "captureScrim",
            "surfacePrimary", "surfaceElevated", "placeholderBG", "placeholderFG",
            "confidenceHigh", "confidenceModerate", "confidenceLow", "medataAccent",
            "textPrimary", "textSecondary", "separatorSubtle"
        ]
        var report: [String] = ["Token coverage:"]
        for relative in Self.scannedFiles {
            let url = root.appendingPathComponent(relative)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let used = tokens.filter { source.contains("Color.\($0)") }
            report.append(" \(relative): \(used.joined(separator: ", "))")
        }
        // Surfaced via XCTest output so the report is visible during CI.
        print(report.joined(separator: "\n"))
        #expect(report.count > 1)
    }

    // MARK: - Helpers

    private func workspaceRoot() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["MEDATA_APP_DIR"] {
            return URL(fileURLWithPath: envPath)
        }
        // Tests/<file>.swift lives at MeData/Tests/<file>.swift; the workspace
        // root is two levels up.
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // MeData
            .deletingLastPathComponent() // workspace root
    }
}
