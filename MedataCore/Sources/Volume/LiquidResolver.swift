import Foundation

// Standalone-liquid resolution (Req 7.4-7.6, Decisions 12/19/24). Sits after
// segmentation where liquid classes are detected; resolves each detection by
// the single precedence rule and returns either a carb estimate (always with
// the over-estimate flag — Decision 19: both paths over-read) or an exclusion
// + flag. Never emits an unbacked carb number.
//
// The resolver is pure: the DB content (foods liquid rows, liquid_servings,
// liquid_subclasses) arrives as `Tables`, and vessel/sub-class labels arrive
// as inputs — vessel and sub-class RECOGNITION is the deferred
// model-production dependency (Req 7.7), so everything here is unit-testable
// from label fixtures alone.

public enum LiquidResolver {

    // Region for canonical serving volumes (UK vs US pint, Req 7.7). Supplied
    // by a Settings value at the call site; defaults to UK.
    public enum Region: String, CaseIterable, Sendable {
        case uk = "UK"
        case us = "US"
    }

    // Closed vessel vocabulary, mirroring generate.py LIQUID_VESSELS (Req 7.4).
    // An unknown vessel label fails to parse into the enum; a missing serving
    // row for a valid vessel is a thrown error — never a silent zero.
    public enum Vessel: String, CaseIterable, Sendable {
        case pint
        case halfPint = "half_pint"
        case can330 = "can_330"
        case can440 = "can_440"
        case glass
        case mug
        case bowl
    }

    // Carb density inputs for one coarse class or sub-class row.
    public struct Composition: Sendable, Equatable {
        public let densityGPerCm3: Float
        public let carbsMonoPer100g: Float

        public init(densityGPerCm3: Float, carbsMonoPer100g: Float) {
            self.densityGPerCm3 = densityGPerCm3
            self.carbsMonoPer100g = carbsMonoPer100g
        }
    }

    public struct ServingKey: Hashable, Sendable {
        public let classId: String
        public let region: Region
        public let vessel: Vessel

        public init(classId: String, region: Region, vessel: Vessel) {
            self.classId = classId
            self.region = region
            self.vessel = vessel
        }
    }

    public struct SubclassKey: Hashable, Sendable {
        public let classId: String
        public let subClass: String

        public init(classId: String, subClass: String) {
            self.classId = classId
            self.subClass = subClass
        }
    }

    // DB-sourced lookup tables (foods liquid rows, liquid_servings,
    // liquid_subclasses) — loaded by the caller, never read here.
    public struct Tables: Sendable {
        public let servingMl: [ServingKey: Float]
        public let coarse: [String: Composition]
        public let subclasses: [SubclassKey: Composition]

        public init(servingMl: [ServingKey: Float],
                    coarse: [String: Composition],
                    subclasses: [SubclassKey: Composition] = [:]) {
            self.servingMl = servingMl
            self.coarse = coarse
            self.subclasses = subclasses
        }
    }

    // One detected liquid, expressed as labels: the coarse class from the
    // segmenter, the recognised vessel/sub-class if any (deferred, Req 7.7),
    // and the depth-integrated surface volume when usable (Req 7.3 — nil when
    // the surface depth is unusable, e.g. low coverage on a transparent
    // liquid).
    public struct Detection: Sendable {
        public let classId: String
        public let vessel: Vessel?
        public let subClass: String?
        public let surfaceVolumeCm3: Float?

        public init(classId: String, vessel: Vessel?,
                    subClass: String?, surfaceVolumeCm3: Float?) {
            self.classId = classId
            self.vessel = vessel
            self.subClass = subClass
            self.surfaceVolumeCm3 = surfaceVolumeCm3
        }
    }

    public enum Path: String, Sendable {
        case canonicalVessel = "canonical_vessel"   // Req 7.4 fill assumption
        case depthIntegrated = "depth_integrated"   // Req 7.3 vessel base/walls
    }

    public struct Estimate: Sendable, Equatable {
        public let carbsG: Float
        public let path: Path
        // Always true (Decision 19): the vessel path assumes a full serving
        // and the depth path integrates the vessel base/walls — both over-read.
        public let liquidOverEstimate: Bool
    }

    public enum Resolution: Sendable, Equatable {
        case estimate(Estimate)
        case excludedFlagged
    }

    public enum ResolverError: Error, Equatable {
        case unknownLiquidClass(String)
        case servingLookupMiss(classId: String, region: Region, vessel: Vessel)
    }

    // The Req 7.4 pure mapping: (vessel, sub_class, region) →
    // liquid_servings.serving_ml × the class's DB carb density. Sub-class
    // densities are best-effort (Req 7.5): an uncertain or unknown sub-class
    // falls back to the coarse row — densities come from the DB, with no
    // assumed ordering between sub-classes.
    public static func canonicalCarbsG(classId: String, subClass: String?,
                                       vessel: Vessel, region: Region,
                                       tables: Tables) throws -> Float {
        let composition = try composition(classId: classId, subClass: subClass,
                                          tables: tables)
        let key = ServingKey(classId: classId, region: region, vessel: vessel)
        guard let servingMl = tables.servingMl[key] else {
            throw ResolverError.servingLookupMiss(classId: classId,
                                                  region: region,
                                                  vessel: vessel)
        }
        return carbsG(volumeCm3: servingMl, composition: composition)
    }

    // The Req 7.6 precedence rule: recognised standard vessel →
    // canonical-volume estimate; else usable surface depth → depth-integrated
    // estimate; else exclude + flag.
    public static func resolve(_ detection: Detection,
                               region: Region = .uk,
                               tables: Tables) throws -> Resolution {
        if let vessel = detection.vessel {
            let carbs = try canonicalCarbsG(classId: detection.classId,
                                            subClass: detection.subClass,
                                            vessel: vessel, region: region,
                                            tables: tables)
            return .estimate(Estimate(carbsG: carbs, path: .canonicalVessel,
                                      liquidOverEstimate: true))
        }
        if let volumeCm3 = detection.surfaceVolumeCm3, volumeCm3 > 0 {
            let composition = try composition(classId: detection.classId,
                                              subClass: detection.subClass,
                                              tables: tables)
            let carbs = carbsG(volumeCm3: volumeCm3, composition: composition)
            return .estimate(Estimate(carbsG: carbs, path: .depthIntegrated,
                                      liquidOverEstimate: true))
        }
        return .excludedFlagged
    }

    // Result-level liquidOverEstimate (Req 8.2): raised when the result
    // includes a liquid ESTIMATE from either path. An excluded liquid carries
    // its own exclusion flag (existing behaviour), not this one.
    public static func liquidOverEstimate(_ resolutions: [Resolution]) -> Bool {
        resolutions.contains {
            if case .estimate(let estimate) = $0 {
                return estimate.liquidOverEstimate
            }
            return false
        }
    }

    // MARK: - private

    private static func composition(classId: String, subClass: String?,
                                    tables: Tables) throws -> Composition {
        guard let coarse = tables.coarse[classId] else {
            throw ResolverError.unknownLiquidClass(classId)
        }
        guard let subClass else { return coarse }
        return tables.subclasses[SubclassKey(classId: classId,
                                             subClass: subClass)] ?? coarse
    }

    private static func carbsG(volumeCm3: Float,
                               composition: Composition) -> Float {
        volumeCm3 * composition.densityGPerCm3
            * composition.carbsMonoPer100g / 100
    }
}
