import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import GlucoseGraph

// Accuracy acceptance test against the frozen fixtures (Reqs 6.1–6.4).
// Port of the reference `test_accuracy.py`: parameterised over all 9 corpus
// images. Per image the extraction must:
// - yield a reading at >=98% of marks where the fixture records a value,
// - emit zero readings at fixture-absent marks,
// - keep >=95% of readings within ±0.3 mmol/L of the fixture value,
// - never deviate by more than ±0.6 mmol/L.
// It reports each image's MAE and maximum error, and doubles as the
// permanent regression harness: the fixtures were committed before the
// reference extraction existed and are never edited to fit the output.
final class AccuracyTests: XCTestCase {

    // Zone the screenshots were taken in — pinned so the gate passes on any
    // machine regardless of its local zone.
    private static let corpusZone = TimeZone(identifier: "Europe/Dublin")!

    // The 8h home view carries no printed date; in-app its date comes from
    // the photo asset (Decision 3). The reference supplied it via --date.
    private static let suppliedDates: [String: GraphDate] = [
        "IMG_0570": GraphDate(year: 2026, month: 7, day: 2)
    ]

    private static let images = [
        "IMG_0570", "IMG_0578", "IMG_0579", "IMG_0580", "IMG_0581",
        "IMG_0582", "IMG_0583", "IMG_0584", "IMG_0585",
    ]

    private func corpusURL(_ name: String, ext: String, subdirectory: String) throws -> URL {
        let url = Bundle.module.url(
            forResource: name, withExtension: ext,
            subdirectory: subdirectory)
        return try XCTUnwrap(url, "missing corpus resource \(subdirectory)/\(name).\(ext)")
    }

    private func loadImage(_ name: String) throws -> CGImage {
        let url = try corpusURL(name, ext: "PNG", subdirectory: "corpus")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    // Fixture CSV: header `local_time,value`, e.g. `2026-07-02T21:35,9.4`.
    private func loadFixture(_ name: String) throws -> [String: Double] {
        let url = try corpusURL(name, ext: "csv", subdirectory: "corpus/expected")
        let content = try String(contentsOf: url, encoding: .utf8)
        var fixture: [String: Double] = [:]
        for line in content.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: ",")
            guard parts.count == 2, let value = Double(parts[1]) else { continue }
            fixture[String(parts[0])] = value
        }
        return fixture
    }

    private static let localTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = corpusZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    func testAccuracyGates() throws {
        var axisHighs = Set<Int>()
        for name in Self.images {
            let fixture = try loadFixture(name)
            let image = try loadImage(name)
            let extraction = try GlucoseGraphExtractor.extract(
                cgImage: image,
                assetDate: Self.suppliedDates[name],
                timeZone: Self.corpusZone
            )
            axisHighs.insert(extraction.axisRange.high)

            var got: [String: Double] = [:]
            for reading in extraction.readings {
                let date = Date(timeIntervalSince1970: Double(reading.tsUtcMs) / 1000)
                got[Self.localTimeFormatter.string(from: date)] = reading.value
            }

            let gotKeys = Set(got.keys)
            let fixtureKeys = Set(fixture.keys)
            let falsePositives = gotKeys.subtracting(fixtureKeys).sorted()
            let matched = gotKeys.intersection(fixtureKeys).sorted()
            let missed = fixtureKeys.subtracting(gotKeys).sorted()

            let errors = matched.map { abs(got[$0]! - fixture[$0]!) }
            let mae = errors.isEmpty ? Double.nan : errors.reduce(0, +) / Double(errors.count)
            let maxError = errors.max() ?? .nan
            let recall = Double(matched.count) / Double(fixture.count)
            let within = errors.isEmpty
                ? 0.0
                : Double(errors.filter { $0 <= 0.3 + 1e-9 }.count) / Double(errors.count)

            // Req 6.2: the test SHALL report per-image MAE and max error.
            print(String(
                format: "%@: fixture=%d extracted=%d recall=%.1f%% within±0.3=%.1f%% MAE=%.3f max=%.2f",
                name, fixture.count, got.count, recall * 100, within * 100, mae, maxError))

            XCTAssertTrue(
                falsePositives.isEmpty,
                "\(name): readings at fixture-absent marks: \(falsePositives.prefix(6))")
            XCTAssertGreaterThanOrEqual(
                recall, 0.98,
                "\(name): recall \(recall) < 98%; missed \(missed.prefix(6))")
            XCTAssertGreaterThanOrEqual(
                within, 0.95, "\(name): only \(within) within ±0.3 mmol/L")
            XCTAssertLessThanOrEqual(
                maxError, 0.6 + 1e-9, "\(name): max error \(maxError) > 0.6")
        }

        // Req 2.4 targeted assertion: the corpus exercises both labelled
        // ranges (3–21 and 3–27) without per-image configuration.
        XCTAssertTrue(axisHighs.contains(21), "corpus should include a 3–21 axis")
        XCTAssertTrue(axisHighs.contains(27), "corpus should include a 3–27 axis")
    }
}
