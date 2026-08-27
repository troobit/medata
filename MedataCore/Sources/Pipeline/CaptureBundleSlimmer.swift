import Foundation

// Wire-level slimmer for recorded capture bundles
// (specs/estimation/ml-feedback-loop Req 3.6, design "Device storage budget and
// slimming"). The counterpart to CaptureBundleRecorder: the recorder decides
// what a bundle contains, this decides what it keeps once the disk runs short.
//
// At the measured sizes (~390 MB per two-view success, ~199 MB per refusal) and
// the observed capture rate, a multi-day field session outruns the phone. The
// probability tensors are almost all of that mass and nothing downstream of a
// completed attempt re-reads them: geometry replays from image, depth, argmax,
// intrinsics and gravity. Dropping the tensors keeps a bundle replayable for
// geometry and class identity and gives up re-scoring it, which is the trade
// Req 3.6 asks for — reduce bulk rather than stop recording or lose captures.
//
// The mechanism is a varint field skip over the proto wire format — the Swift
// equivalent of the reader in tools/fixture_slice.py — NOT a SwiftProtobuf
// decode. Decoding a ~390 MB bundle to re-encode it would materialise the
// tensors we are trying to be rid of, on a phone, under thermal pressure.
// Records that are not dropped are copied byte for byte, so nothing outside the
// two dropped fields can change; unknown fields from a newer or older recorder
// survive untouched for the same reason.
//
// Profile-neutral: the App-layer FieldMaintenance decides WHEN to call this.
public enum CaptureBundleSlimmer {

    // PbMealFixture field numbers
    // (MedataCore/Sources/PortableContracts/Schemas/MealFixture.proto):
    // 9 = nadir_probs, 10 = oblique_probs.
    public static let droppedFieldNumbers: Set<Int> = [9, 10]

    // The sidecar marks CONTENT state and sits beside the bundle as
    // `<stem>.slimmed`. Deliberately not `fixture_revision`, which versions the
    // schema: a slimmed bundle is the same schema carrying less, and bumping
    // the revision would tell every reader the format moved when it did not.
    public static let markerExtension = "slimmed"

    public struct Result: Equatable, Sendable {
        public let bytesBefore: Int
        public let bytesAfter: Int
        // True when the bundle already carried no dropped field: the file is
        // left untouched. Oldest-first sweeps re-encounter bundles, and a
        // rewrite-anyway would churn the disk it is trying to free.
        public let alreadySlim: Bool
    }

    public enum Error: Swift.Error, Equatable {
        // A truncated or corrupt bundle — including one still being written by
        // a recorder that has not yet renamed it into place. The original is
        // left exactly as found: replacing it with a partially-parsed prefix
        // would destroy field data that cannot be recaptured.
        case malformedWireFormat(reason: String, offset: Int)
    }

    @discardableResult
    public static func slim(bundleAt url: URL) throws -> Result {
        // Memory-mapped: the scan only touches tags and lengths, so the pages
        // holding the tensors are never faulted in on the read side.
        let input = try Data(contentsOf: url, options: .mappedIfSafe)
        let ranges = try topLevelFieldRanges(input)
        let kept = ranges.filter { !droppedFieldNumbers.contains($0.number) }
        guard kept.count != ranges.count else {
            // The marker is still written: it states "this bundle carries no
            // probability tensors", which is what the corpus index and any
            // replay need to know, and is equally true of a refusal recorded
            // before segmentation as of a rewritten success. Equal byte counts
            // are what distinguish the two.
            try writeMarker(for: url, bytesBefore: input.count, bytesAfter: input.count)
            return Result(bytesBefore: input.count, bytesAfter: input.count, alreadySlim: true)
        }

        let tempURL = url.deletingPathExtension()
            .appendingPathExtension("slimming-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        var bytesAfter = 0
        do {
            let handle = try FileHandle(forWritingTo: tempURL)
            defer { try? handle.close() }
            // Written record by record so the output is never held whole in
            // memory beside the mapped input. Ranges are offsets from the
            // start of the message, not absolute Data indices.
            let base = input.startIndex
            for field in kept {
                let slice = input[(base + field.range.lowerBound)
                                  ..< (base + field.range.upperBound)]
                try handle.write(contentsOf: slice)
                bytesAfter += slice.count
            }
            try handle.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        // Atomic replace: a kill mid-slim leaves either the original bundle or
        // the slimmed one, never a truncated file a batch replay would choke on
        // (the recorder's finalise-then-rename convention).
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        try writeMarker(for: url, bytesBefore: input.count, bytesAfter: bytesAfter)
        return Result(bytesBefore: input.count, bytesAfter: bytesAfter, alreadySlim: false)
    }

    // MARK: - Wire scan

    public struct Field: Equatable, Sendable {
        public let number: Int
        // The WHOLE record — tag varint plus payload — so a kept field is
        // copied without being re-encoded.
        public let range: Range<Int>
    }

    // One pass over the top-level message. Nested messages are opaque payloads:
    // nothing this drops or keeps lives below the top level, so there is no
    // reason to descend into one.
    public static func topLevelFieldRanges(_ data: Data) throws -> [Field] {
        var fields: [Field] = []
        var i = 0
        let end = data.count
        while i < end {
            let start = i
            let (key, afterKey) = try readVarint(data, at: i)
            i = afterKey
            let number = Int(key >> 3)
            let wire = Int(key & 7)
            switch wire {
            case 0:
                (_, i) = try readVarint(data, at: i)
            case 1:
                i = try advance(i, by: 8, end: end)
            case 2:
                let (length, afterLength) = try readVarint(data, at: i)
                // A corrupt length is data, not a programming error:
                // `Int(length)` would trap the process on a bundle the caller
                // is trying to recover from.
                guard let payloadLength = Int(exactly: length) else {
                    throw Error.malformedWireFormat(
                        reason: "payload length \(length) exceeds Int", offset: start)
                }
                i = try advance(afterLength, by: payloadLength, end: end)
            case 5:
                i = try advance(i, by: 4, end: end)
            default:
                // Groups (3/4) are proto2-only and cannot appear here.
                throw Error.malformedWireFormat(
                    reason: "unsupported wire type \(wire) for field \(number)", offset: start)
            }
            fields.append(Field(number: number, range: start..<i))
        }
        return fields
    }

    private static func readVarint(_ data: Data, at index: Int) throws -> (UInt64, Int) {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var i = index
        while true {
            guard i < data.count else {
                throw Error.malformedWireFormat(reason: "truncated varint", offset: index)
            }
            guard shift < 64 else {
                throw Error.malformedWireFormat(reason: "varint overflows 64 bits", offset: index)
            }
            let byte = data[data.startIndex + i]
            i += 1
            value |= UInt64(byte & 0x7F) << shift
            shift += 7
            if byte & 0x80 == 0 { return (value, i) }
        }
    }

    private static func advance(_ index: Int, by count: Int, end: Int) throws -> Int {
        guard count >= 0, index <= end - count else {
            throw Error.malformedWireFormat(reason: "payload runs past the end", offset: index)
        }
        return index + count
    }

    // MARK: - Marker

    // key=value, the repo's tooling convention: the pull summary reads these
    // numbers, the interpretation lives in the spec.
    private static func writeMarker(for url: URL, bytesBefore: Int, bytesAfter: Int) throws {
        let dropped = droppedFieldNumbers.sorted().map(String.init).joined(separator: ",")
        let line = "fields_dropped=\(dropped) bytes_before=\(bytesBefore) "
            + "bytes_after=\(bytesAfter)\n"
        try Data(line.utf8).write(
            to: url.deletingPathExtension().appendingPathExtension(markerExtension),
            options: .atomic)
    }
}
