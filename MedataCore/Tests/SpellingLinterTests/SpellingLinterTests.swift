import Foundation
import XCTest

// Tests for tools/check_spelling.sh — the spelling linter behind `make spell`.
// Each test creates a temporary Swift file, runs the shell script against it, and
// verifies the exit code. These tests run on macOS (the linter is a shell script).
final class SpellingLinterTests: XCTestCase {

    private static var scriptURL: URL = {
        // Resolve tools/check_spelling.sh relative to the package root.
        // __FILE__ is inside MedataCore/Tests/SpellingLinterTests/, so the package
        // root is four levels up.
        let here = URL(fileURLWithPath: #filePath)
        let packageRoot = here
            .deletingLastPathComponent()   // SpellingLinterTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // MedataCore/
            .deletingLastPathComponent()   // (package root)
        return packageRoot.appendingPathComponent("tools/check_spelling.sh")
    }()

    // MARK: – Banned US-English words (must be rejected)

    func testRejectsRecognized() throws {
        try assertLinterFails(source: #"let x = "recognized""#)
    }

    func testRejectsColor() throws {
        try assertLinterFails(source: #"let foregroundColor = UIColor.red"#)
    }

    func testRejectsFiber() throws {
        try assertLinterFails(source: #"// dietary fiber content"#)
    }

    func testRejectsFavorite() throws {
        try assertLinterFails(source: #"var favorite: Bool = true"#)
    }

    func testRejectsCenter() throws {
        try assertLinterFails(source: #"let center = CGPoint.zero"#)
    }

    func testRejectsOptimize() throws {
        try assertLinterFails(source: "func optimize() {}")
    }

    func testRejectsInitialize() throws {
        try assertLinterFails(source: "func initialize() {}")
    }

    func testRejectsNormalize() throws {
        try assertLinterFails(source: "func normalize() {}")
    }

    func testRejectsSynchronize() throws {
        try assertLinterFails(source: "func synchronize() {}")
    }

    func testRejectsOrganization() throws {
        try assertLinterFails(source: #"let org: Organization"#)
    }

    // MARK: – Correct spellings (must be accepted)

    func testAllowsRecognised() throws {
        try assertLinterPasses(source: #"let x = "recognised""#)
    }

    func testAllowsColour() throws {
        try assertLinterPasses(source: "let colour = UIColor.red")
    }

    func testAllowsFibre() throws {
        try assertLinterPasses(source: "// dietary fibre content")
    }

    func testAllowsFavourite() throws {
        try assertLinterPasses(source: "var favourite: Bool = true")
    }

    func testAllowsCentre() throws {
        try assertLinterPasses(source: "let centre = CGPoint.zero")
    }

    func testAllowsOptimise() throws {
        try assertLinterPasses(source: "func optimise() {}")
    }

    func testAllowsInitialise() throws {
        try assertLinterPasses(source: "func initialise() {}")
    }

    func testAllowsNormalise() throws {
        try assertLinterPasses(source: "func normalise() {}")
    }

    func testAllowsSynchronise() throws {
        try assertLinterPasses(source: "func synchronise() {}")
    }

    // MARK: – Edge cases

    func testWordBoundaryDoesNotFlagColorInColour() throws {
        // "colour" must not be flagged because it contains "color" as a substring.
        // The linter uses \b word-boundary anchors.
        try assertLinterPasses(source: "let colour = 42")
    }

    func testWordBoundaryDoesNotFlagCentreInCenter() throws {
        // Likewise "centre" must not be tripped by the "center" rule.
        try assertLinterPasses(source: "func centrePoint() -> CGPoint { .zero }")
    }

    func testEmptyFileIsClean() throws {
        try assertLinterPasses(source: "")
    }

    func testMultipleBannedWordsAreAllReported() throws {
        // A file with two violations must still exit 1.
        try assertLinterFails(source: "let color = 0; let center = 0")
    }

    // MARK: – Helpers

    private func assertLinterPasses(source: String, file: StaticString = #file, line: UInt = #line) throws {
        let status = try runLinter(swiftSource: source)
        XCTAssertEqual(status, 0,
            "Expected linter to pass (exit 0) for source:\n\(source)",
            file: file, line: line)
    }

    private func assertLinterFails(source: String, file: StaticString = #file, line: UInt = #line) throws {
        let status = try runLinter(swiftSource: source)
        XCTAssertEqual(status, 1,
            "Expected linter to fail (exit 1) for source:\n\(source)",
            file: file, line: line)
    }

    // Writes `swiftSource` to a temp directory that looks like a MedataCore/Sources
    // subtree, then runs check_spelling.sh and returns the exit code.
    private func runLinter(swiftSource: String) throws -> Int32 {
        #if !os(macOS)
        throw XCTSkip("Spelling linter shell script runs on macOS only")
        #endif

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpellingLinterTests-\(UUID().uuidString)")

        // Create a MedataCore/Sources/Stub layout so the script's SCAN_TARGETS match.
        let sourceDir = tmp
            .appendingPathComponent("MedataCore")
            .appendingPathComponent("Sources")
            .appendingPathComponent("Stub")
        try FileManager.default.createDirectory(at: sourceDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let swiftFile = sourceDir.appendingPathComponent("test.swift")
        try swiftSource.write(to: swiftFile, atomically: true, encoding: .utf8)

        // Build a wrapper script that overrides REPO_ROOT to point at tmp.
        let wrapperSource = """
        #!/usr/bin/env bash
        export REPO_ROOT="\(tmp.path)"
        exec bash "\(Self.scriptURL.path)"
        """
        let wrapperURL = tmp.appendingPathComponent("run_linter.sh")
        try wrapperSource.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: wrapperURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", wrapperURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
