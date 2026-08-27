import Foundation
import GlucoseWidgetShared
import Persistence

// Source abstraction for live glucose (specs/data/cgm-connect Req 1).
// Every source — HealthKit, LibreLinkUp, whatever comes later — sits behind
// GlucoseSource and delivers batches to a GlucoseIngestSink. Delivery is
// pull-with-ack (Decision 7): `ingest` returns only after the write
// transaction commits, so a source advances its durable cursor (HealthKit
// anchor / LibreLinkUp last-success) only on a successful return.

// Connection state of one source, as surfaced in Settings (Req 1.1, 6.1).
public enum GlucoseConnectionState: Sendable, Equatable {
    case notConnected
    case connected(lastReadingAt: Date?)
    case failed(reason: String, lastSuccessAt: Date?)
}

// One reading as delivered by a source, already normalised to mmol/L
// (Req 1.1). `nativeInstant` is the pre-snap sensor instant — the
// coordinator snaps it onto the 5-minute grid (Decision 4) and keeps the
// native instant in the stored row's metadata (Req 4.2).
public struct GlucoseSample: Sendable, Equatable {
    public let nativeInstant: Date
    public let mmolL: Double
    public let nativeID: String?
    // How the source measured it (specs/data/fingerprick-glucose Req 1.1).
    // A source reports what it measured; the coordinator decides how that is
    // stored. Defaulted `.sensor`, so LibreLinkUp, the screenshot import and
    // the heartbeat source are untouched and Req 7.2's guarantee stays
    // structural — the sensor path is entered only by sensor samples.
    public let provenance: GlucoseProvenance

    public init(
        nativeInstant: Date, mmolL: Double, nativeID: String? = nil,
        provenance: GlucoseProvenance = .sensor
    ) {
        self.nativeInstant = nativeInstant
        self.mmolL = mmolL
        self.nativeID = nativeID
        self.provenance = provenance
    }

    // mg/dL convenience for sources that report it (Req 5.5). The divisor is
    // `GlucoseGrid.mgPerDlPerMmolL`, shared with the widget's own vendor fetch.
    // No rounding here — the coordinator's single rounding point rounds to one
    // decimal before the duplicate check and storage.
    public init(
        nativeInstant: Date, mgPerDl: Double, nativeID: String? = nil,
        provenance: GlucoseProvenance = .sensor
    ) {
        self.init(
            nativeInstant: nativeInstant,
            mmolL: GlucoseGrid.mmolL(fromMgPerDl: mgPerDl),
            nativeID: nativeID,
            provenance: provenance
        )
    }
}

// Implemented by the IngestionCoordinator. `ingest` returns only after the
// batch's transaction commits and throws when the write failed; a source
// treats a successful return as the durable ack and only then advances its
// cursor and (HealthKit) calls the OS completion handler (Req 2.5,
// Decision 7).
public protocol GlucoseIngestSink: Sendable {
    func ingest(_ samples: [GlucoseSample], from sourceID: String) async throws -> BslIngestSummary

    // State transitions outside the ingest path (Req 6.1): a source pushes
    // `.failed` / `.notConnected` / `.connected` here so the UI sees them
    // without polling. A successful `ingest` already implies `.connected`;
    // this exists for the transitions ingest cannot express.
    func reportState(_ state: GlucoseConnectionState, for sourceID: String) async
}

// One glucose source (Req 1.1). A source owns its own scheduling (HealthKit
// observer callbacks; LibreLinkUp timer/refresh) and calls
// `sink.ingest(batch, from: id)` as readings arrive.
public protocol GlucoseSource: Sendable {
    var id: String { get }
    func state() async -> GlucoseConnectionState
    func connect(sink: GlucoseIngestSink) async throws
    func disconnect() async
}
