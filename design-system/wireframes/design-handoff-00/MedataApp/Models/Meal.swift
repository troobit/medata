import Foundation

/// Per-class estimate within a meal.
struct FoodClass: Hashable, Identifiable {
    let id: UUID
    let name: String              // e.g. "White rice"
    let classKey: String          // segmenter palette key
    let volumeCubicCm: Double
    let massGrams: Double
    let carbsGrams: Double
    let confidence: Double        // σ_c ∈ [0,1]
    let unknown: Bool             // true → "unknown carbs"
    let unsupportedLiquid: Bool

    init(id: UUID = UUID(), name: String, classKey: String,
         volumeCubicCm: Double, massGrams: Double,
         carbsGrams: Double, confidence: Double,
         unknown: Bool = false, unsupportedLiquid: Bool = false) {
        self.id = id
        self.name = name
        self.classKey = classKey
        self.volumeCubicCm = volumeCubicCm
        self.massGrams = massGrams
        self.carbsGrams = carbsGrams
        self.confidence = confidence
        self.unknown = unknown
        self.unsupportedLiquid = unsupportedLiquid
    }
}

/// Per req §3.8.
enum CapturePath: String, Codable, Hashable {
    case singleViewLidar = "single_view_lidar"
    case twoViewSfS      = "two_view_sfs"
}

/// Per-meal confidence breakdown (req §13).
struct Confidence: Hashable {
    let scale: Double            // σ_s
    let segmentation: Double     // σ_seg
    let geometric: Double        // σ_geom

    /// Geometric mean of three sub-confidences.
    var meal: Double {
        cbrt(max(0, scale) * max(0, segmentation) * max(0, geometric))
    }

    var level: Level {
        switch meal {
        case 0.8...:  return .high
        case 0.6..<0.8: return .moderate
        default:      return .low
        }
    }

    enum Level { case high, moderate, low }
}

struct Meal: Hashable, Identifiable {
    let id: UUID
    let capturedAt: Date
    let title: String                  // "Lunch", "Snack" etc.
    let capturePath: CapturePath
    let classes: [FoodClass]
    let confidence: Confidence
    let databaseEdition: String        // e.g. "CoFID 2024 + IFCDB 2023"
    var userCorrection: UserCorrection?

    var totalCarbs: Double { classes.map(\.carbsGrams).reduce(0, +) }
    var totalMass:  Double { classes.map(\.massGrams).reduce(0, +)  }

    /// Display rounding per req §12.4 — to the nearest 1 g.
    var displayCarbs: Int { Int(totalCarbs.rounded()) }
}

/// Req §14: capture data only, never overwrite originals.
struct UserCorrection: Hashable {
    let correctedTotalCarbs: Double?
    let perClass: [UUID: Double]      // FoodClass.id → corrected carbs
    let note: String
    let timestamp: Date
}
