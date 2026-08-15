// swift-tools-version: 5.9
import PackageDescription

// Compile-time feature flags (Decisions 41, 42):
//
//   HARNESS_ENABLED       — Decision 41. Gates the AccuracyHarness, BetaCalibrator,
//                           FixtureLoader/Runner, SegBench, the HarnessCLI executable
//                           and the corresponding tests. Defined ONLY on the
//                           HarnessCore / HarnessCLI / HarnessCLITests targets so
//                           the shipping iOS app binary contains zero harness code.
//
//   DEV_STUB_SEGMENTER    — Decision 42, Req §23. Selects `StubInferenceEngine`
//                           over `CoreMLInferenceEngine` inside
//                           `Pipeline.makeForDevice` for Phase 1 device-MVP builds.
//                           Defined on the `Pipeline` target in `.debug` only so
//                           Release builds (Phase 3) bind the real Core ML model.

let package = Package(
    name: "MedataCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Benchmark rides in the app-facing product so BenchmarkView /
        // EstimationLogView can render Report and the anchor block
        // (snaq-parity lane B); the target itself still depends on
        // Persistence only, keeping the report maths in `make test`.
        .library(name: "MedataCore", targets: ["Pipeline", "Benchmark"]),
        // Separate product: glucose ingestion is a data stream beside the
        // estimation pipeline, not part of it (specs/data/libre-ingestion
        // Decision 2). The app links both.
        .library(name: "GlucoseGraph", targets: ["GlucoseGraph"]),
        // Separate product for the same reason as GlucoseGraph: live glucose
        // ingestion (specs/data/cgm-connect) is a data stream beside the
        // estimation pipeline, deliberately NOT reachable via the MedataCore
        // product (Req 7.1). The app links it in Phase 4.
        .library(name: "GlucoseIngestion", targets: ["GlucoseIngestion"]),
        // Discrete product, deliberately NOT part of the MedataCore umbrella
        // (specs/ui/glucose-lock-widget Decision 10): the MeDataWidgets
        // extension links exactly this and therefore cannot acquire GRDB
        // transitively. Foundation-only, zero dependencies.
        .library(name: "GlucoseWidgetShared", targets: ["GlucoseWidgetShared"]),
        // Discrete product for the same reason as GlucoseWidgetShared
        // (specs/ui/glucose-lock-widget Decision 16): the MeDataWidgets
        // extension fetches from LibreLinkUp itself while the app is suspended,
        // so it links this and GlucoseWidgetShared and still cannot acquire
        // GRDB. Foundation-only, no Persistence dependency.
        .library(name: "LibreLinkUpKit", targets: ["LibreLinkUpKit"]),
        // Discrete product for the pure dose arithmetic
        // (specs/data/insulin-dosing Decision 11). A product, not a bare
        // target, because the iOS app links SwiftPM code by PRODUCT name only
        // — `packageProductDependencies` in project.pbxproj names products —
        // so `import Dosing` from App/ cannot resolve without this line.
        // GlucoseWidgetShared is the precedent: a zero-dependency leaf that
        // still needed its own library product to be linkable.
        .library(name: "Dosing", targets: ["Dosing"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "PortableContracts",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "MedataCore/Sources/PortableContracts",
            exclude: ["Schemas"]
        ),
        .target(
            name: "CaptureKit",
            dependencies: ["PortableContracts"],
            path: "MedataCore/Sources/CaptureKit"
        ),
        .target(
            name: "CardDetection",
            dependencies: ["PortableContracts", "CaptureKit"],
            path: "MedataCore/Sources/CardDetection"
        ),
        .target(
            name: "SupportPlane",
            dependencies: ["PortableContracts", "CaptureKit", "CardDetection"],
            path: "MedataCore/Sources/SupportPlane"
        ),
        .target(
            name: "MetricScale",
            dependencies: ["PortableContracts", "CardDetection", "SupportPlane"],
            path: "MedataCore/Sources/MetricScale"
        ),
        .target(
            name: "Segmentation",
            dependencies: ["PortableContracts", "CaptureKit"],
            path: "MedataCore/Sources/Segmentation"
        ),
        .target(
            name: "Volume",
            dependencies: ["PortableContracts", "CaptureKit", "Segmentation", "SupportPlane", "MetricScale"],
            path: "MedataCore/Sources/Volume",
            resources: [
                .copy("Kernels")
            ]
        ),
        .target(
            name: "Foods",
            dependencies: [
                "PortableContracts",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "MedataCore/Sources/Foods",
            resources: [
                .copy("Resources/cofid_db.sqlite"),
                .copy("Resources/afcd_db.sqlite")
            ]
        ),
        .target(
            name: "Macros",
            dependencies: ["PortableContracts", "Foods", "Volume"],
            path: "MedataCore/Sources/Macros"
        ),
        .target(
            name: "Confidence",
            dependencies: ["PortableContracts"],
            path: "MedataCore/Sources/Confidence"
        ),
        // Glucose widget contract (specs/ui/glucose-lock-widget Decisions 10, 12):
        // the snapshot DTO, the two leaf enums, the App Group / widget-kind ids,
        // the UserDefaults snapshot store, and the pure staleness maths.
        // Foundation only — the dependency list MUST stay empty (asserted in
        // GlucoseWidgetSharedTests) and the target MUST NOT import WidgetKit:
        // Persistence depends on it, so either would ride into Pipeline and on
        // into the macOS HarnessCLI.
        .target(
            name: "GlucoseWidgetShared",
            path: "MedataCore/Sources/GlucoseWidgetShared"
        ),
        // LibreLinkUp vendor client (specs/data/cgm-connect Req 3), extracted
        // from GlucoseIngestion so the widget extension can fetch for itself
        // (specs/ui/glucose-lock-widget Decision 16). GlucoseWidgetShared is
        // the only dependency and only for the App Group suite the shared
        // connection state and vendor rate gate live in — so this target's
        // closure stays Foundation + system frameworks, and the appex link
        // closure still cannot reach GRDB (Decision 12).
        .target(
            name: "LibreLinkUpKit",
            dependencies: ["GlucoseWidgetShared"],
            path: "MedataCore/Sources/LibreLinkUpKit"
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "PortableContracts",
                // TrendsMath returns GlucoseTrend / GlucoseBandStatus.
                "GlucoseWidgetShared",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "MedataCore/Sources/Persistence"
        ),
        // Pure dose arithmetic (specs/data/insulin-dosing Decision 11): the
        // band classifier, the carbohydrate ratio type, the insulin-on-board
        // curve and the suggester. Foundation only — the dependency list MUST
        // stay empty. Persistence must not depend on it and it must not depend
        // on Persistence: the App composes the persisted row from the pure
        // result, so no estimation target can reach this code even
        // transitively (Req 10.3). The firewall is structural rather than
        // asserted by a dump-package test — GlucoseIngestion needed one
        // because it depends on Persistence, which Pipeline also depends on,
        // so a transitive path was possible; here there is no edge for a path
        // to run along.
        .target(
            name: "Dosing",
            path: "MedataCore/Sources/Dosing"
        ),
        // Libre ingestion (specs/data/libre-ingestion): LibreLink screenshot →
        // bsl readings. Zero internal dependencies by design (Decision 2) —
        // platform bindings are Vision/CoreGraphics/ImageIO only.
        .target(
            name: "GlucoseGraph",
            path: "MedataCore/Sources/GlucoseGraph"
        ),
        // Live glucose ingestion (specs/data/cgm-connect): the GlucoseSource
        // abstraction + IngestionCoordinator writing bsl events through
        // Persistence. The estimation targets (Pipeline, CaptureKit,
        // Segmentation, Volume, Macros, MetricScale, SupportPlane,
        // CardDetection, Confidence, Foods) MUST NOT depend on this target
        // (Req 7.1) — enforced by the firewall test in GlucoseIngestionTests.
        .target(
            name: "GlucoseIngestion",
            dependencies: [
                "Persistence", "PortableContracts", "LibreLinkUpKit",
                // Grid snapping and the trend maths moved here so the widget
                // shares them (glucose-lock-widget Decision 16).
                "GlucoseWidgetShared"
            ],
            path: "MedataCore/Sources/GlucoseIngestion"
        ),
        // Benchmark report maths (specs/estimation/snaq-parity lane B):
        // BenchmarkReport.compute + the promotion-gate bootstrap. Depends on
        // Persistence only — placement keeps the report maths in the executed
        // `make test` surface, out of the app target.
        .target(
            name: "Benchmark",
            dependencies: ["Persistence"],
            path: "MedataCore/Sources/Benchmark"
        ),
        .target(
            name: "Pipeline",
            dependencies: [
                "CaptureKit", "CardDetection", "SupportPlane", "MetricScale",
                "Segmentation", "Volume", "Foods", "Macros", "Confidence", "Persistence",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "MedataCore/Sources/Pipeline",
            // Bundled Core ML segmenter (model-production Req 5.1/5.2, Decision 7).
            // `.copy("Resources")` preserves the directory inside `Bundle.module`,
            // so the gitignored `Resources/segmenter.mlpackage` (dropped in by
            // `tools/segmenter/export.py`) is bundled when present and absent
            // otherwise; the committed `Resources/README.md` keeps `Bundle.module`
            // available on clean checkouts that do not yet have the model.
            resources: [
                .copy("Resources")
            ],
            // DEV_STUB_SEGMENTER per Decision 42 / Req §23.4: Debug builds
            // bind StubInferenceEngine; Release builds bind CoreMLInferenceEngine.
            swiftSettings: [
                .define("DEV_STUB_SEGMENTER", .when(configuration: .debug))
            ]
        ),
        // Harness targets — feature-flagged via HARNESS_ENABLED per Decision 41.
        // The iOS app target ("MedataCore" / "Pipeline") MUST NOT define HARNESS_ENABLED,
        // so the shipping app binary links zero harness code. Only the three targets
        // below set the compile flag, and the gate is enforced per-file via #if HARNESS_ENABLED.
        .target(
            name: "HarnessCore",
            dependencies: [
                "Pipeline",
                "CaptureKit",
                "Segmentation",
                "SupportPlane",
                "Volume",
                "Macros",
                "Foods",
                "PortableContracts",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "HarnessCore",
            swiftSettings: [.define("HARNESS_ENABLED")]
        ),
        .executableTarget(
            name: "HarnessCLI",
            dependencies: ["HarnessCore", "Pipeline"],
            path: "HarnessCLI",
            swiftSettings: [.define("HARNESS_ENABLED")]
        ),
        .testTarget(
            name: "PortableContractsTests",
            dependencies: ["PortableContracts"],
            path: "MedataCore/Tests/PortableContractsTests"
        ),
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit"],
            path: "MedataCore/Tests/CaptureKitTests"
        ),
        .testTarget(
            name: "SegmentationTests",
            dependencies: ["Segmentation", "CaptureKit", "PortableContracts"],
            path: "MedataCore/Tests/SegmentationTests"
        ),
        .testTarget(
            name: "CardDetectionTests",
            dependencies: ["CardDetection", "CaptureKit", "PortableContracts"],
            path: "MedataCore/Tests/CardDetectionTests"
        ),
        .testTarget(
            name: "SupportPlaneTests",
            // `Confidence` is here for the task 26 corpus pass alone: Req 4.6's
            // `supportPlaneFallbackPenalty` is priced in millimetres of plane error, and
            // the millimetres are measured on these slices. `Volume` is here for the same
            // pass and the same reason: τ_conf is TWO constants under one name, and the
            // second is `HeightFieldEstimator.tauConfidence` (Decision 53).
            dependencies: ["SupportPlane", "CaptureKit", "CardDetection", "PortableContracts",
                           "Confidence", "Volume"],
            path: "MedataCore/Tests/SupportPlaneTests",
            // Depth-only slices of the two field captures Reqs 6.2/7.1 name, cut by
            // `tools/fixture_slice.py`. ~290 KB each against the 195 MB bundles they
            // come from, which is what makes those criteria executable off-device.
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "MetricScaleTests",
            dependencies: ["MetricScale", "CardDetection", "SupportPlane", "PortableContracts"],
            path: "MedataCore/Tests/MetricScaleTests"
        ),
        .testTarget(
            name: "VolumeTests",
            dependencies: ["Volume", "Segmentation", "SupportPlane", "CaptureKit", "PortableContracts"],
            path: "MedataCore/Tests/VolumeTests"
        ),
        .testTarget(
            name: "FoodsTests",
            dependencies: [
                "Foods",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "MedataCore/Tests/FoodsTests"
        ),
        .testTarget(
            name: "MacrosTests",
            dependencies: ["Macros", "Foods", "Volume", "PortableContracts"],
            path: "MedataCore/Tests/MacrosTests"
        ),
        .testTarget(
            name: "ConfidenceTests",
            dependencies: ["Confidence", "PortableContracts"],
            path: "MedataCore/Tests/ConfidenceTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                "PortableContracts",
                // TrendsMath's glucose trend/band helpers return its enums.
                "GlucoseWidgetShared",
                // Test-only: PaletteMigratorTests exercises the real
                // v1 → v2 ClassPalettes (myfoodrepo-bridge PRD). The
                // Persistence TARGET stays palette-agnostic.
                "Segmentation",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "MedataCore/Tests/PersistenceTests"
        ),
        .testTarget(
            name: "BenchmarkTests",
            dependencies: ["Benchmark", "Persistence"],
            path: "MedataCore/Tests/BenchmarkTests"
        ),
        .testTarget(
            name: "GlucoseGraphTests",
            dependencies: ["GlucoseGraph"],
            path: "MedataCore/Tests/GlucoseGraphTests",
            // The accuracy corpus (specs/data/libre-ingestion Req 6.1,
            // Decision 6): 9 LibreLink screenshots + ground-truth fixtures.
            resources: [
                .copy("Resources/corpus")
            ]
        ),
        .testTarget(
            name: "DosingTests",
            dependencies: ["Dosing"],
            path: "MedataCore/Tests/DosingTests"
        ),
        .testTarget(
            name: "GlucoseWidgetSharedTests",
            dependencies: ["GlucoseWidgetShared"],
            path: "MedataCore/Tests/GlucoseWidgetSharedTests"
        ),
        .testTarget(
            name: "GlucoseIngestionTests",
            dependencies: [
                "GlucoseIngestion",
                "Persistence",
                "PortableContracts",
                // The LLU payload decoding fixtures live here; the types they
                // decode moved to LibreLinkUpKit (glucose-lock-widget Decision 16).
                "LibreLinkUpKit"
            ],
            path: "MedataCore/Tests/GlucoseIngestionTests"
        ),
        .testTarget(
            name: "PipelineTests",
            dependencies: ["Pipeline", "Persistence", "PortableContracts", "SupportPlane", "CaptureKit", "Volume"],
            path: "MedataCore/Tests/PipelineTests"
        ),
        .testTarget(
            name: "HarnessCLITests",
            dependencies: [
                "HarnessCore",
                "Pipeline",
                "CardDetection",
                "CaptureKit",
                "Persistence",
                "Segmentation",
                "Foods",
                "PortableContracts",
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "MedataCore/Tests/HarnessCLITests",
            swiftSettings: [.define("HARNESS_ENABLED")]
        )
    ]
)
