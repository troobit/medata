import CaptureKit
import Foundation
import PortableContracts

// Input bundle produced by the capture flow and consumed by Pipeline.estimate(_:).
// Carries all per-session data needed by the pipeline stages C–L (design §2.2).
public struct CaptureResult: Sendable {
    public let capturePath: CapturePath
    public let lidar: LiDARStatus
    public let nadirFrame: RawFrame
    public let obliqueFrame: RawFrame?      // nil for singleViewLidar path
    public let databaseEdition: String
    public let paletteVersion: String

    public init(
        capturePath: CapturePath,
        lidar: LiDARStatus,
        nadirFrame: RawFrame,
        obliqueFrame: RawFrame?,
        databaseEdition: String,
        paletteVersion: String
    ) {
        self.capturePath = capturePath
        self.lidar = lidar
        self.nadirFrame = nadirFrame
        self.obliqueFrame = obliqueFrame
        self.databaseEdition = databaseEdition
        self.paletteVersion = paletteVersion
    }
}
