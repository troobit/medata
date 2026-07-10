import Foundation
import XCTest

// Estimation-path firewall (specs/data/cgm-connect Req 7.1): the TRANSITIVE
// dependency closure of every estimation target must exclude
// GlucoseIngestion. Transitive, not direct-edge — Pipeline → Persistence and
// GlucoseIngestion → Persistence both exist, so a direct-edge check would
// miss a Pipeline → … → GlucoseIngestion path. The generated dump-package
// graph is the single source of truth; no hand-maintained fixture.
final class EstimationFirewallTests: XCTestCase {

    private static let estimationTargets = [
        "Pipeline", "CaptureKit", "Segmentation", "Volume", "Macros",
        "MetricScale", "SupportPlane", "CardDetection", "Confidence", "Foods",
    ]

    func testEstimationTargetsTransitivelyExcludeGlucoseIngestion() throws {
        #if os(macOS)
        let packageRoot = try Self.findPackageRoot()
        let graph = try Self.parseTargetGraph(Self.dumpPackage(at: packageRoot))

        // Guard against the check going vacuous through a rename.
        XCTAssertNotNil(
            graph["GlucoseIngestion"],
            "GlucoseIngestion target missing from the package graph — firewall test is vacuous")

        // Positive control: edge parsing must actually see dependencies.
        // Pipeline → Persistence is a real, load-bearing edge; if parsing
        // rots (dump-package format change, key rename), this fails loudly
        // instead of the exclusion checks passing vacuously.
        XCTAssertTrue(
            Self.transitiveClosure(of: "Pipeline", in: graph).contains("Persistence"),
            "Pipeline's closure lacks Persistence — dependency parsing is broken, firewall vacuous")

        for target in Self.estimationTargets {
            XCTAssertNotNil(graph[target], "estimation target \(target) missing from dump-package")
            let closure = Self.transitiveClosure(of: target, in: graph)
            XCTAssertFalse(
                closure.contains("GlucoseIngestion"),
                "\(target) transitively depends on GlucoseIngestion — Req 7.1 firewall breached")
        }
        #else
        throw XCTSkip("requires the swift toolchain on PATH (macOS test host)")
        #endif
    }

    #if os(macOS)
    // Walks up from this file to the directory containing Package.swift.
    private static func findPackageRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("Package.swift").path) {
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else {
                throw XCTSkip("no Package.swift found above \(#filePath)")
            }
            dir = parent
        }
        return dir
    }

    private static func dumpPackage(at root: URL) throws -> Data {
        // An isolated --scratch-path is essential: this test runs INSIDE
        // `swift test`, which holds the package's .build lock for the whole
        // invocation — a nested dump-package against the default scratch
        // path deadlocks waiting on it.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("firewall-dump-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "package", "--scratch-path", scratch.path, "dump-package",
        ]
        process.currentDirectoryURL = root
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Drain both pipes before waiting so a large manifest cannot deadlock.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let diagnostics = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "EstimationFirewallTests", code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "dump-package failed: \(String(decoding: diagnostics, as: UTF8.self))"
                ])
        }
        return output
    }

    // Adjacency map: target name → dependency names. dump-package encodes
    // each dependency as a one-key object — {"byName": ["Persistence", null]}
    // or {"product": ["GRDB", "GRDB.swift", null, null]} or
    // {"target": ["Foo", null]} — the first array element is always the
    // dependency's name. Product names of external packages land in the map
    // probes harmlessly: they are not targets, so the walk stops there.
    private static func parseTargetGraph(_ data: Data) throws -> [String: [String]] {
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let targets = try XCTUnwrap(root["targets"] as? [[String: Any]])
        var graph: [String: [String]] = [:]
        for target in targets {
            let name = try XCTUnwrap(target["name"] as? String)
            let dependencies = target["dependencies"] as? [[String: Any]] ?? []
            graph[name] = dependencies.compactMap { dependency in
                (dependency.values.first as? [Any])?.first as? String
            }
        }
        return graph
    }

    private static func transitiveClosure(
        of target: String, in graph: [String: [String]]
    ) -> Set<String> {
        var closure: Set<String> = []
        var frontier = graph[target] ?? []
        while let next = frontier.popLast() {
            guard closure.insert(next).inserted else { continue }
            frontier.append(contentsOf: graph[next] ?? [])
        }
        return closure
    }
    #endif
}
