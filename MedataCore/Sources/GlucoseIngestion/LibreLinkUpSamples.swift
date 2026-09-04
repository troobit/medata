import Foundation
import LibreLinkUpKit

// The ingest-path half of the LibreLinkUp mapping. `LibreLinkUpKit` stops at
// the vendor's own reading (UTC instant + mg/dL + FactoryTimestamp id) because
// its other consumer — the widget extension — has no `GlucoseSample` and no
// ingestion path (glucose-lock-widget Decision 16). Turning that into the
// source-abstraction type belongs here, where `GlucoseSample` lives.
//
// The mg/dL → mmol/L conversion is `GlucoseSample`'s own initialiser, so both
// surfaces convert at 18.0182 with no second copy of the constant.
extension LibreLinkUpClient {
    static func samples(from graph: LLUGraphResponse) -> [GlucoseSample] {
        readings(from: graph).map {
            GlucoseSample(nativeInstant: $0.instant, mgPerDl: $0.mgPerDl, nativeID: $0.nativeID)
        }
    }
}
