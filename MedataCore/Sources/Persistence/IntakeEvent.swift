import Foundation

// Manual carb intake (specs/data/manual-carb-intake, Phase 1). Follows the
// same `events` row convention as InsulinDose (see docs/agent-notes/
// persistence.md "Insulin events"): `value` = carbs (g), `timestamp` = the
// user-set time, `metadata` = a JSON object with `subtype`, `schema_version`,
// `source`, plus `preset_id` (quickadd only) and macro keys — all omitted,
// never null, when absent.

// Only "carb" ships in this spec (design.md "Event type and storage");
// "alcohol" etc. arrive in a later feature.
public enum IntakeSubtype: String, Sendable, Equatable {
    case carb
}

// Optional macros captured alongside carbs (Req 2.2, 2.3). Each field is
// `nil` when not provided by the user — never zero.
public struct IntakeMacros: Sendable, Equatable {
    public var proteinG: Double?
    public var fatG: Double?
    public var fibreG: Double?

    public init(proteinG: Double? = nil, fatG: Double? = nil, fibreG: Double? = nil) {
        self.proteinG = proteinG
        self.fatG = fatG
        self.fibreG = fibreG
    }
}

// Distinguishes a keyed-in entry from a one-tap quick-add (Req 6.1).
public enum IntakeSource: String, Sendable, Equatable {
    case manual
    case quickadd
}

// One manual carb entry bound for the event log. `carbsG` is required and
// constrained to 1...999 (Req 1.4) — enforced at the store layer, mirroring
// `insulinUnitsOutOfRange`. `presetID` is a point-in-time provenance stamp,
// set iff `source == .quickadd` (design.md "Event type and storage") — the
// store does not enforce this pairing, matching the project's existing
// permissiveness elsewhere (e.g. `InsulinDose.note`).
public struct IntakeEntry: Sendable, Equatable {
    // Version of the intake metadata convention (`metadata.schema_version`).
    public static let metadataSchemaVersion = 1

    public let id: UUID
    public let timestamp: Date
    public let carbsG: Double
    public let subtype: IntakeSubtype
    public let macros: IntakeMacros
    public let source: IntakeSource
    public let presetID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        carbsG: Double,
        subtype: IntakeSubtype = .carb,
        macros: IntakeMacros = .init(),
        source: IntakeSource,
        presetID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.carbsG = carbsG
        self.subtype = subtype
        self.macros = macros
        self.source = source
        self.presetID = presetID
    }
}
