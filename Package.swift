// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MedataCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MedataCore", targets: ["Pipeline"]),
        .executable(name: "HarnessCLI", targets: ["HarnessCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0")
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
            dependencies: ["PortableContracts"],
            path: "MedataCore/Sources/Foods"
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
            dependencies: ["PortableContracts"],
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
        .executableTarget(
            name: "HarnessCLI",
            dependencies: ["Pipeline"],
            path: "HarnessCLI"
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
        )
    ]
)
