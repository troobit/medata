import Foundation
import PortableContracts
import SwiftProtobuf

// Swift-ergonomic MealRecord. Uses Pb sub-types for all composite fields so
// Persistence stays within the PortableContracts dependency boundary.
// `paletteVersion` is SQL-only (denormalised column); it is NOT in PbMealRecord.
public struct MealRecord: Sendable, Equatable, Hashable {
    public let id: UUID
    public let createdAt: Date
    public let capturePath: CapturePath
    public let databaseEdition: String
    public let paletteVersion: String
    public let frames: [PbRawFrameMetadata]
    public let calibration: PbCameraIntrinsics
    public let supportPlane: PbSupportPlane
    public let scale: PbMetricScale
    public let volumes: PbVolumeResult
    public let macros: PbMacroResult
    public let confidence: PbConfidenceResult
    public let perClassCalibration: [String: PbBetaCalibrationStatus]
    public let userCorrection: PbUserCorrection?
    // SQL-only fields. `segmenterSource` carries the dev-stub provenance used by
    // the Meals-tab placeholder chip (UI Req §19.3, research Decision 42).
    // `photoAssetID` references a `PHAsset.localIdentifier` for thumbnail
    // retrieval (UI Req §19.2). Both default to `nil` until the producing
    // research tasks land — the Meals tab still renders, the chip and thumbnail
    // just fall back per UI Decision 15.
    public let segmenterSource: String?
    public let photoAssetID: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        capturePath: CapturePath,
        databaseEdition: String,
        paletteVersion: String,
        frames: [PbRawFrameMetadata] = [],
        calibration: PbCameraIntrinsics,
        supportPlane: PbSupportPlane,
        scale: PbMetricScale,
        volumes: PbVolumeResult,
        macros: PbMacroResult,
        confidence: PbConfidenceResult,
        perClassCalibration: [String: PbBetaCalibrationStatus] = [:],
        userCorrection: PbUserCorrection? = nil,
        segmenterSource: String? = nil,
        photoAssetID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.capturePath = capturePath
        self.databaseEdition = databaseEdition
        self.paletteVersion = paletteVersion
        self.frames = frames
        self.calibration = calibration
        self.supportPlane = supportPlane
        self.scale = scale
        self.volumes = volumes
        self.macros = macros
        self.confidence = confidence
        self.perClassCalibration = perClassCalibration
        self.userCorrection = userCorrection
        self.segmenterSource = segmenterSource
        self.photoAssetID = photoAssetID
    }
}

// Artefact descriptor — mirrors PbMealArtefact but uses Swift-native Int.
public struct MealArtefact: Sendable, Equatable {
    public let kind: String       // 'image' | 'depth' | 'confidence' | 'mask' | 'probs'
    public let viewId: String     // 'nadir' | 'oblique'
    public let filename: String
    public let bytesSize: Int
    public let sha256Hex: String

    public init(kind: String, viewId: String, filename: String, bytesSize: Int, sha256Hex: String) {
        self.kind = kind
        self.viewId = viewId
        self.filename = filename
        self.bytesSize = bytesSize
        self.sha256Hex = sha256Hex
    }
}

// MARK: - PbMealRecord bridge

public extension MealRecord {
    // Converts to PbMealRecord for protobuf-JSON serialisation.
    // paletteVersion is omitted (SQL column only, not in proto).
    var pb: PbMealRecord {
        var out = PbMealRecord()
        out.id = id.uuidString
        out.createdAtMs = Int64(createdAt.timeIntervalSince1970 * 1000)
        out.capturePath = capturePath.pb
        out.databaseEdition = databaseEdition
        out.frames = frames
        out.calibration = calibration
        out.supportPlane = supportPlane
        out.scale = scale
        out.volumes = volumes
        out.macros = macros
        out.confidence = confidence
        out.perClassCalibration = perClassCalibration
        if let uc = userCorrection { out.userCorrection = uc }
        return out
    }

    // Reconstructs from PbMealRecord + the SQL-only columns.
    init(
        pb: PbMealRecord,
        paletteVersion: String,
        segmenterSource: String? = nil,
        photoAssetID: String? = nil
    ) throws {
        guard let uuid = UUID(uuidString: pb.id) else {
            throw PersistenceError.corruptRecord("invalid UUID: \(pb.id)")
        }
        guard let capturePath = CapturePath(pb: pb.capturePath) else {
            throw PersistenceError.corruptRecord("unrecognised capture_path")
        }
        self.id = uuid
        self.createdAt = Date(timeIntervalSince1970: Double(pb.createdAtMs) / 1000)
        self.capturePath = capturePath
        self.databaseEdition = pb.databaseEdition
        self.paletteVersion = paletteVersion
        self.frames = pb.frames
        self.calibration = pb.calibration
        self.supportPlane = pb.supportPlane
        self.scale = pb.scale
        self.volumes = pb.volumes
        self.macros = pb.macros
        self.confidence = pb.confidence
        self.perClassCalibration = pb.perClassCalibration
        self.userCorrection = pb.hasUserCorrection ? pb.userCorrection : nil
        self.segmenterSource = segmenterSource
        self.photoAssetID = photoAssetID
    }

    // Encodes to protobuf-JSON string per Decision 31.
    func jsonString() throws -> String {
        try pb.jsonString()
    }

    // Decodes from protobuf-JSON string + the SQL-only columns.
    static func from(
        jsonString: String,
        paletteVersion: String,
        segmenterSource: String? = nil,
        photoAssetID: String? = nil
    ) throws -> MealRecord {
        let pb = try PbMealRecord(jsonString: jsonString)
        return try MealRecord(
            pb: pb,
            paletteVersion: paletteVersion,
            segmenterSource: segmenterSource,
            photoAssetID: photoAssetID
        )
    }
}

// MARK: - CapturePath bridge

extension CapturePath {
    init?(pb: PbCapturePath) {
        switch pb {
        case .singleViewLidar: self = .singleViewLidar
        case .twoViewSfs: self = .twoViewSfS
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    var pb: PbCapturePath {
        switch self {
        case .singleViewLidar: return .singleViewLidar
        case .twoViewSfS: return .twoViewSfs
        }
    }
}
