import Foundation
import PortableContracts

// CaptureKit ↔ PortableContracts (proto) bridges. These are the only place the
// Swift-ergonomic types from `RawFrame.swift` cross to the wire format defined
// in PortableContracts/Schemas/.

public extension CameraIntrinsics {
    init(pb: PbCameraIntrinsics) {
        self.init(
            fx: pb.fx, fy: pb.fy, cx: pb.cx, cy: pb.cy,
            distortion: pb.distortion,
            imageWidth: Int(pb.imageWidth),
            imageHeight: Int(pb.imageHeight)
        )
    }

    var pb: PbCameraIntrinsics {
        var out = PbCameraIntrinsics()
        out.fx = fx
        out.fy = fy
        out.cx = cx
        out.cy = cy
        out.distortion = distortion
        out.imageWidth = Int32(imageWidth)
        out.imageHeight = Int32(imageHeight)
        return out
    }
}

public extension DepthMap {
    init(pb: PbDepthMap) {
        self.init(
            depthBytesMm: pb.depthBytesMm,
            confidenceBytes: pb.confidenceBytes,
            width: Int(pb.width),
            height: Int(pb.height),
            rowStrideBytes: Int(pb.rowStrideBytes),
            depthIntrinsics: CameraIntrinsics(pb: pb.depthIntrinsics),
            depthFromColour: Mat4(pb: pb.depthFromColour)
        )
    }

    var pb: PbDepthMap {
        var out = PbDepthMap()
        out.depthBytesMm = depthBytesMm
        out.confidenceBytes = confidenceBytes
        out.width = Int32(width)
        out.height = Int32(height)
        out.rowStrideBytes = Int32(rowStrideBytes)
        out.depthIntrinsics = depthIntrinsics.pb
        out.depthFromColour = depthFromColour.pb
        return out
    }
}

public extension PixelFormat {
    init?(pb: PbPixelFormat) {
        switch pb {
        case .rgb8: self = .rgb8
        case .bgra8: self = .bgra8
        case .rgba8: self = .rgba8
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    var pb: PbPixelFormat {
        switch self {
        case .rgb8: return .rgb8
        case .bgra8: return .bgra8
        case .rgba8: return .rgba8
        }
    }
}

public extension ColourSpace {
    init?(pb: PbColourSpace) {
        switch pb {
        case .srgb: self = .sRGB
        case .linear: self = .linear
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    var pb: PbColourSpace {
        switch self {
        case .sRGB: return .srgb
        case .linear: return .linear
        }
    }
}

public extension RawFrame {
    var pb: PbRawFrame {
        var out = PbRawFrame()
        out.imageBytes = imageBytes
        out.pixelFormat = pixelFormat.pb
        out.colourSpace = colourSpace.pb
        out.orientation = Int32(orientation)
        out.imageWidth = Int32(imageWidth)
        out.imageHeight = Int32(imageHeight)
        out.timestampMonotonicNs = timestampMonotonicNs
        out.intrinsics = intrinsics.pb
        out.gravity = gravity.pb
        out.worldFromCamera = worldFromCamera.pb
        if let d = depth {
            out.depth = d.pb
        }
        return out
    }
}
