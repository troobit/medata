#if FIELD_LOOP
import Foundation

// The note file contract (ml-feedback-loop design, Data Models). One JSON file
// plus one PNG per note in `Documents/notes/`, schema-versioned, read by
// `tools/field_loop/field_pull.py` on the Mac.
//
// Keys are written explicitly rather than by `.convertToSnakeCase`: this is a
// wire contract another language parses, and an encoder strategy would let a
// property rename silently rewrite the wire format.

// The join keys a meal-linked note carries (Req 2.1). All three are optional
// because the surfaces differ in what they know: a refusal has an outcome id
// and no meal, a Records row has a meal id and reaches its outcome through the
// timestamp, and `timestamp_ms` is the onward join to the capture-bundle stem.
nonisolated struct FieldNoteMealLink: Codable, Equatable, Sendable {
    var mealID: UUID?
    var outcomeID: UUID?
    var timestampMs: Int64?

    enum CodingKeys: String, CodingKey {
        case mealID = "meal_id"
        case outcomeID = "outcome_id"
        case timestampMs = "timestamp_ms"
    }

    var isEmpty: Bool { mealID == nil && outcomeID == nil && timestampMs == nil }
}

// One detected food as the developer saw it (Req 2.4). Displayed — that is,
// corrected — values, not `record.macros`: the note is about what was on the
// screen, and a later reprocessing or correction must not be able to change
// what the note was about.
nonisolated struct EstimateSnapshotFood: Codable, Equatable, Sendable {
    var classID: String
    var displayName: String
    var massG: Double
    var carbsG: Double

    enum CodingKeys: String, CodingKey {
        case classID = "class_id"
        case displayName = "display_name"
        case massG = "mass_g"
        case carbsG = "carbs_g"
    }
}

nonisolated struct EstimateSnapshot: Codable, Equatable, Sendable {
    var foods: [EstimateSnapshotFood]
    var displayedTotalCarbsG: Double
    var displayedTotalMassG: Double

    enum CodingKeys: String, CodingKey {
        case foods
        case displayedTotalCarbsG = "displayed_total_carbs_g"
        case displayedTotalMassG = "displayed_total_mass_g"
    }
}

nonisolated struct FieldNote: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var v: Int = FieldNote.schemaVersion
    var id: UUID
    var createdAtMs: Int64
    var screenID: String
    // Verbatim (Req 2.3): household measures — "two slices", "half a bowl" —
    // are expected content and are never parsed on device.
    var text: String
    var carbsG: Double?
    var meal: FieldNoteMealLink?
    var estimateSnapshot: EstimateSnapshot?
    var screenshot: String?
    // Why the screenshot is absent, when it is (Req 1.6: the note still saves).
    var screenshotError: String?
    var speechUsed: Bool
    var buildStamp: String
    var modelVersion: String
    var profile: String = "field"

    enum CodingKeys: String, CodingKey {
        case v
        case id
        case createdAtMs = "created_at_ms"
        case screenID = "screen_id"
        case text
        case carbsG = "carbs_g"
        case meal
        case estimateSnapshot = "estimate_snapshot"
        case screenshot
        case screenshotError = "screenshot_error"
        case speechUsed = "speech_used"
        case buildStamp = "build_stamp"
        case modelVersion = "model_version"
        case profile
    }

    // `<created_at_ms>-<uuid>` — time-ordered by filename, unique by id, and
    // the shared stem of the JSON and its PNG. Pull-side dedup is
    // filename-keyed, so the stem must never be reused (Req 2.5: a later note
    // on the same capture is a distinct file, never an overwrite).
    var filenameStem: String {
        "\(createdAtMs)-\(id.uuidString.lowercased())"
    }
}
#endif
