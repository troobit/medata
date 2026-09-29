#if FIELD_LOOP
import BackgroundTasks
import CryptoKit
import Foundation
import OSLog
import Persistence
import Pipeline
import UIKit

// Device-side housekeeping for the field loop: acting on what a pull took
// (ml-feedback-loop Decision 14) and keeping the capture footprint inside a
// stated budget (Req 3.6).
//
// Ordering is a contract, not a preference: **manifest processing runs before
// slimming, and slimming skips every stem a pending manifest lists.** A bundle
// slimmed after it was pulled would fail its hash check for the rest of its
// life on the device, and the file would never be deleted.
actor FieldMaintenance {
    static let shared = FieldMaintenance()

    // Registered in MeData/Info.plist under BGTaskSchedulerPermittedIdentifiers.
    // Declaring an identifier nothing registers is inert, which is what a
    // product build does — this whole file compiles out there.
    static let backgroundTaskIdentifier = "com.medata.fieldloop.maintenance"

    private static let log = Logger(subsystem: "ie.medata.app", category: "FieldMaintenance")

    // Measured bundle sizes are ~390 MB (two-view success) and ~200 MB
    // (refusal), and the observed field rate is 49 attempts in 11 minutes, so a
    // three-day session can pass 50 GB. The budget arms slimming; the
    // watermark is where a sweep stops, so a session sitting exactly on the
    // budget does not re-slim on every capture.
    struct Budget: Sendable {
        var armBytes: Int64 = 25 * 1_000_000_000
        var lowWatermarkBytes: Int64 = 20 * 1_000_000_000
    }

    // Two-phase handshake (Decision 14). The pull tool writes the manifest
    // under `<name>.partial` and only then the sentinel naming its SHA-256 and
    // byte length, so a manifest still being copied — or copied and then
    // truncated — can never be acted on. Names are part of the wire contract
    // with `tools/field_loop/field_pull.py`.
    enum ManifestFile {
        static let manifest = "pulled_manifest.json.partial"
        static let sentinel = "pulled_manifest.ready"
    }

    struct Manifest: Codable, Sendable {
        struct Entry: Codable, Sendable {
            let stem: String
            let sha256: String
        }
        let pullID: String
        let bundles: [Entry]
        let notes: [Entry]
        // Outcome ids whose protection this pull retires. The Mac side lists an
        // id only once every note referencing it is in the same pull — the
        // device cannot know that, and unprotecting an outcome a note on the
        // phone still points at would let the row evict out from under it.
        let protectedOutcomes: [String]

        enum CodingKeys: String, CodingKey {
            case pullID = "pull_id"
            case bundles
            case notes
            case protectedOutcomes = "protected_outcomes"
        }
    }

    struct Sentinel: Codable, Sendable {
        let sha256: String
        let length: Int
    }

    // Surfaced in the next pull summary (Req 3.6): when the sweep cannot reach
    // the watermark, recording continues and this file says so, rather than the
    // recorder silently dropping captures.
    struct SlimmingState: Codable, Sendable {
        let atMs: Int64
        let footprintBytes: Int64
        let watermarkBytes: Int64
        let bundlesSlimmed: Int
        let watermarkReached: Bool
        let deferredReason: String?

        enum CodingKeys: String, CodingKey {
            case atMs = "at_ms"
            case footprintBytes = "footprint_bytes"
            case watermarkBytes = "watermark_bytes"
            case bundlesSlimmed = "bundles_slimmed"
            case watermarkReached = "watermark_reached"
            case deferredReason = "deferred_reason"
        }
    }

    private let documentsURL: URL
    private let capturesURL: URL
    private var budget = Budget()
    private var store: (any PersistenceStore)?
    private var isRunning = false

    init(documentsURL: URL = URL.documentsDirectory) {
        self.documentsURL = documentsURL
        capturesURL = documentsURL.appendingPathComponent("captures", isDirectory: true)
    }

    func configure(store: any PersistenceStore) {
        self.store = store
    }

    // Launch, foreground, and post-capture all land here. Re-entrancy is
    // guarded rather than queued: a second pass while one is running would only
    // re-measure the same directory.
    func run(reason: String) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let pending = processManifest()
        await slimIfNeeded(skippingStems: pending, reason: reason)
    }

    // MARK: - Manifest pass

    // Returns the stems slimming must not touch: everything a manifest still
    // lists, whether it was deleted this pass or held back by a hash mismatch.
    @discardableResult
    private func processManifest() -> Set<String> {
        let manifestURL = documentsURL.appendingPathComponent(ManifestFile.manifest)
        let sentinelURL = documentsURL.appendingPathComponent(ManifestFile.sentinel)
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestURL.path),
              fm.fileExists(atPath: sentinelURL.path)
        else { return [] }

        guard let manifest = verifiedManifest(manifestURL: manifestURL, sentinelURL: sentinelURL)
        else {
            // A half-written manifest is ignored, not deleted: the next pull
            // re-pushes it, and deleting it here would lose the pull's record
            // of what it took.
            Self.log.notice("event=fieldmaint.manifest.unverified")
            return []
        }

        var listed = Set<String>()
        var deleted = 0
        var mismatched = 0
        for entry in manifest.bundles {
            listed.insert(entry.stem)
            let bundleURL = capturesURL
                .appendingPathComponent(entry.stem)
                .appendingPathExtension("fixture")
            switch deleteIfHashMatches(bundleURL, expected: entry.sha256) {
            case .deleted:
                deleted += 1
                // The sidecar has no independent value once its bundle is gone.
                try? fm.removeItem(at: capturesURL
                    .appendingPathComponent(entry.stem)
                    .appendingPathExtension(CaptureBundleSlimmer.markerExtension))
            case .mismatch:
                mismatched += 1
            case .absent:
                break
            }
        }
        for entry in manifest.notes {
            listed.insert(entry.stem)
            let noteURL = documentsURL
                .appendingPathComponent("notes", isDirectory: true)
                .appendingPathComponent(entry.stem)
                .appendingPathExtension("json")
            switch deleteIfHashMatches(noteURL, expected: entry.sha256) {
            case .deleted:
                deleted += 1
                try? fm.removeItem(at: documentsURL
                    .appendingPathComponent("notes", isDirectory: true)
                    .appendingPathComponent(entry.stem)
                    .appendingPathExtension("png"))
            case .mismatch:
                mismatched += 1
            case .absent:
                break
            }
        }

        let outcomeIDs = manifest.protectedOutcomes.compactMap(UUID.init(uuidString:))
        if let store, !outcomeIDs.isEmpty {
            Task {
                for id in outcomeIDs {
                    try? await store.unmarkOutcomeProtected(id: id)
                }
            }
        }

        // Manifest and sentinel go last: until both are gone this pull is still
        // pending, and an interrupted pass simply repeats — every step above is
        // idempotent.
        try? fm.removeItem(at: manifestURL)
        try? fm.removeItem(at: sentinelURL)
        Self.log.notice(
            "event=fieldmaint.manifest.processed pull=\(manifest.pullID, privacy: .public) deleted=\(deleted, privacy: .public) mismatched=\(mismatched, privacy: .public) unprotected=\(outcomeIDs.count, privacy: .public)"
        )
        return listed
    }

    private func verifiedManifest(manifestURL: URL, sentinelURL: URL) -> Manifest? {
        guard let sentinelData = try? Data(contentsOf: sentinelURL),
              let sentinel = try? JSONDecoder().decode(Sentinel.self, from: sentinelData),
              let manifestData = try? Data(contentsOf: manifestURL),
              manifestData.count == sentinel.length,
              Self.hex(SHA256.hash(data: manifestData)) == sentinel.sha256.lowercased(),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData)
        else { return nil }
        return manifest
    }

    private enum DeleteOutcome { case deleted, mismatch, absent }

    // Hash-gated (Decision 14): a file whose bytes no longer match what the Mac
    // verified is left alone and reported in the next pull. Nothing on the
    // phone is deleted on the strength of a filename.
    private func deleteIfHashMatches(_ url: URL, expected: String) -> DeleteOutcome {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let digest = Self.sha256OfFile(at: url) else { return .mismatch }
        guard digest == expected.lowercased() else {
            Self.log.notice(
                "event=fieldmaint.hash.mismatch file=\(url.lastPathComponent, privacy: .public)"
            )
            return .mismatch
        }
        do {
            try FileManager.default.removeItem(at: url)
            return .deleted
        } catch {
            return .mismatch
        }
    }

    // MARK: - Slimming

    private func slimIfNeeded(skippingStems skip: Set<String>, reason: String) async {
        let footprint = captureFootprintBytes()
        guard footprint > budget.armBytes else { return }

        if let deferral = await Self.deferralReason() {
            Self.log.notice(
                "event=fieldmaint.slim.deferred reason=\(deferral, privacy: .public) footprintBytes=\(footprint, privacy: .public)"
            )
            writeSlimmingState(SlimmingState(
                atMs: Int64(Date().timeIntervalSince1970 * 1000),
                footprintBytes: footprint,
                watermarkBytes: budget.lowWatermarkBytes,
                bundlesSlimmed: 0,
                watermarkReached: false,
                deferredReason: deferral
            ))
            return
        }

        var remaining = footprint
        var slimmed = 0
        // Oldest first: the filename stem is a zero-padded millisecond
        // timestamp, so lexical order IS capture order.
        for url in bundleURLsOldestFirst() where remaining > budget.lowWatermarkBytes {
            let stem = url.deletingPathExtension().lastPathComponent
            guard !skip.contains(stem) else { continue }
            guard !FileManager.default.fileExists(atPath: url.deletingPathExtension()
                .appendingPathExtension(CaptureBundleSlimmer.markerExtension).path)
            else { continue }
            do {
                let result = try CaptureBundleSlimmer.slim(bundleAt: url)
                remaining -= Int64(result.bytesBefore - result.bytesAfter)
                if !result.alreadySlim { slimmed += 1 }
            } catch {
                // A bundle the recorder is still writing throws here and is
                // left exactly as found; the next pass picks it up.
                Self.log.error(
                    "event=fieldmaint.slim.failed file=\(url.lastPathComponent, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
            if await Self.deferralReason() != nil { break }
        }

        let reached = remaining <= budget.lowWatermarkBytes
        writeSlimmingState(SlimmingState(
            atMs: Int64(Date().timeIntervalSince1970 * 1000),
            footprintBytes: remaining,
            watermarkBytes: budget.lowWatermarkBytes,
            bundlesSlimmed: slimmed,
            watermarkReached: reached,
            deferredReason: nil
        ))
        Self.log.notice(
            "event=fieldmaint.slim.swept reason=\(reason, privacy: .public) slimmed=\(slimmed, privacy: .public) footprintBytes=\(remaining, privacy: .public) watermarkReached=\(reached, privacy: .public)"
        )
    }

    // Req 3.6: reducing bulk must never become a reason to stop recording, so
    // the sweep steps aside under heat or a low battery and says why.
    // `@MainActor` because UIDevice is: battery state is main-actor state in
    // the concurrency model, so the check hops rather than racing it.
    @MainActor
    private static func deferralReason() -> String? {
        if ProcessInfo.processInfo.thermalState.rawValue
            >= ProcessInfo.ThermalState.serious.rawValue {
            return "thermal"
        }
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = wasMonitoring }
        let charging = device.batteryState == .charging || device.batteryState == .full
        if !charging, device.batteryLevel >= 0, device.batteryLevel < 0.2 {
            return "battery"
        }
        return nil
    }

    private func bundleURLsOldestFirst() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: capturesURL, includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "fixture" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func captureFootprintBytes() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: capturesURL, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return urls.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    private func writeSlimmingState(_ state: SlimmingState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(
            to: documentsURL.appendingPathComponent("slimming_state.json"),
            options: .atomic
        )
    }

    // MARK: - Hashing

    private static func hex(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // Streamed: a 390 MB bundle must not be read whole to be checked.
    private static func sha256OfFile(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }
}

// MARK: - Scheduling

// The BGTask half. Registration must complete before the application finishes
// launching, so it is called from `MedataApp.init` alongside the glucose
// source's own registration.
@MainActor
enum FieldMaintenanceScheduler {
    private static let log = Logger(subsystem: "ie.medata.app", category: "FieldMaintenance")

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: FieldMaintenance.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task {
                await FieldMaintenance.shared.run(reason: "background")
                processing.setTaskCompleted(success: true)
                schedule()
            }
            processing.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(
            identifier: FieldMaintenance.backgroundTaskIdentifier
        )
        // The sweep rewrites hundreds of megabytes; asking for power confines
        // it to the charger, which is also when a field day's backlog is most
        // likely to be sitting still.
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error(
                "event=fieldmaint.bgtask.submit.failed error=\(String(describing: error), privacy: .public)"
            )
        }
    }
}
#endif
