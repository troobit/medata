import Foundation
import PortableContracts

// Swift-ergonomic RawFrame and friends per design §3.1. The portable wire format is
// PbRawFrame from RawFrame.proto; these Swift types are what the rest of MedataCore
// consumes. Bridges to/from the Pb* generated types live in `Bridges.swift`.

public enum PixelFormat: String, Sendable, Codable {
    case rgb8 = "RGB8"
    case bgra8 = "BGRA8"
    case rgba8 = "RGBA8"
}

public enum ColourSpace: String, Sendable, Codable {
    case sRGB = "sRGB"
    case linear = "linear"
}

public struct CameraIntrinsics: Sendable, Codable, Equatable {
    public let fx: Float
    public let fy: Float
    public let cx: Float
    public let cy: Float
    public let distortion: [Float]
    public let imageWidth: Int
    public let imageHeight: Int

    public init(fx: Float, fy: Float, cx: Float, cy: Float,
                distortion: [Float] = [], imageWidth: Int, imageHeight: Int) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.distortion = distortion
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
}

public struct DepthMap: Sendable {
    public let depthBytesMm: Data            // Float32 LE row-major in mm (per §6.0).
    public let confidenceBytes: Data         // UInt8 0..255 per §6.0.
    public let width: Int
    public let height: Int
    public let rowStrideBytes: Int
    public let depthIntrinsics: CameraIntrinsics
    public let depthFromColour: Mat4

    public init(depthBytesMm: Data, confidenceBytes: Data,
                width: Int, height: Int, rowStrideBytes: Int,
                depthIntrinsics: CameraIntrinsics, depthFromColour: Mat4) {
        self.depthBytesMm = depthBytesMm
        self.confidenceBytes = confidenceBytes
        self.width = width
        self.height = height
        self.rowStrideBytes = rowStrideBytes
        self.depthIntrinsics = depthIntrinsics
        self.depthFromColour = depthFromColour
    }
}

public struct RawFrame: Sendable {
    public let imageBytes: Data
    public let pixelFormat: PixelFormat
    public let colourSpace: ColourSpace
    public let orientation: Int            // EXIF-style 1..8 per §3.1
    public let imageWidth: Int
    public let imageHeight: Int
    public let timestampMonotonicNs: Int64 // §6.0: monotonic, no wall-clock semantics
    public let intrinsics: CameraIntrinsics
    public let gravity: Vec3               // world-up unit vector in the §6.0 camera
                                           // frame (pose-dependent — see CameraGravity)
    public let worldFromCamera: Mat4
    public let depth: DepthMap?            // nil when LiDAR unavailable

    public init(imageBytes: Data, pixelFormat: PixelFormat, colourSpace: ColourSpace,
                orientation: Int, imageWidth: Int, imageHeight: Int,
                timestampMonotonicNs: Int64, intrinsics: CameraIntrinsics,
                gravity: Vec3, worldFromCamera: Mat4, depth: DepthMap?) {
        self.imageBytes = imageBytes
        self.pixelFormat = pixelFormat
        self.colourSpace = colourSpace
        self.orientation = orientation
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.timestampMonotonicNs = timestampMonotonicNs
        self.intrinsics = intrinsics
        self.gravity = gravity
        self.worldFromCamera = worldFromCamera
        self.depth = depth
    }
}

// ARKit confidence enum mapping per §6.0: low → 0, medium → 127, high → 255.
public enum LidarConfidenceLevel: Int, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public var normalisedByte: UInt8 {
        switch self {
        case .low: return 0
        case .medium: return 127
        case .high: return 255
        }
    }
}
