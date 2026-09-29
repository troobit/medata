import Foundation
import XCTest

// Decision 10: GlucoseWidgetShared must stay dependency-free so the widget
// extension's link closure cannot acquire GRDB through it. Mirrors the
// dump-package approach of GlucoseIngestionTests/EstimationFirewallTests —
// the generated manifest is the source of truth, no hand-maintained fixture.
//
// Known limit (Decision 12): dump-package enumerates PACKAGE edges only, so
// this cannot see an accidental `import WidgetKit`. System frameworks never
// appear in the graph. That boundary is held by review.
final class PackageBoundaryTests: XCTestCase {

    func testGlucoseWidgetSharedHasNoPackageDependencies() throws {
        #if os(macOS)
        let graph = try Self.parseTargetGraph(Self.dumpPackage(at: Self.findPackageRoot()))

        // Guard against the check going vacuous through a rename.
        let dependencies = try XCTUnwrap(
            graph["GlucoseWidgetShared"],
            "GlucoseWidgetShared missing from dump-package — this check is vacuous")

        // Positive control: edge parsing must actually see dependencies, or an
        // empty list below would prove nothing.
        XCTAssertTrue(
            graph["Persistence"]?.contains("GlucoseWidgetShared") == true,
            "Persistence → GlucoseWidgetShared edge not seen — dependency parsing is broken")

        XCTAssertEqual(
            dependencies, [],
            "GlucoseWidgetShared gained a dependency (\(dependencies)) — Decision 10 breached")
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
        // invocation — a nested dump-package against the default scratch path
        // deadlocks waiting on it.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-shared-dump-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "--scratch-path", scratch.path, "dump-package"]
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
                domain: "PackageBoundaryTests", code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "dump-package failed: \(String(decoding: diagnostics, as: UTF8.self))"
                ])
        }
        return output
    }

    // Adjacency map: target name → dependency names. Each dependency is a
    // one-key object — {"byName": ["Persistence", null]} or
    // {"product": ["GRDB", "GRDB.swift", null, null]} — whose first array
    // element is always the dependency's name.
    private static func parseTargetGraph(_ data: Data) throws -> [String: [String]] {
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
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
    #endif
}
