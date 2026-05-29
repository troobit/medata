// swift-tools-version: 5.9
import PackageDescription

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
                .copy("Resources/food_db.sqlite"),
                .copy("Resources/ifcdb_overlay.sqlite")
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
            path: "MedataCore/Sources/Pipeline"
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
            dependencies: ["SupportPlane", "CaptureKit", "PortableContracts"],
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
            dependencies: ["Pipeline", "Persistence", "PortableContracts"],
            path: "MedataCore/Tests/PipelineTests"
        )
    ]
)
