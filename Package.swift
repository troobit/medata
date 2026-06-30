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
        .library(name: "MedataCore", targets: ["Pipeline"])
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
        .target(
            name: "Persistence",
            dependencies: [
                "PortableContracts",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "MedataCore/Sources/Persistence"
        ),
        .target(
            name: "Pipeline",
            dependencies: [
                "CaptureKit", "CardDetection", "SupportPlane", "MetricScale",
                "Segmentation", "Volume", "Foods", "Macros", "Confidence", "Persistence"
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
            dependencies: ["SupportPlane", "CaptureKit", "CardDetection", "PortableContracts"],
            path: "MedataCore/Tests/SupportPlaneTests"
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
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "MedataCore/Tests/PersistenceTests"
        ),
        .testTarget(
            name: "PipelineTests",
            dependencies: ["Pipeline", "Persistence", "PortableContracts", "SupportPlane", "CaptureKit"],
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
