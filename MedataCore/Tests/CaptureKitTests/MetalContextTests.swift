#if canImport(Metal)
import Metal
import XCTest
@testable import CaptureKit

final class MetalContextTests: XCTestCase {
    func testMakeDefaultProducesValidDeviceAndQueue() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available on this host (e.g. CI without GPU)")
        }
        let ctx = try MetalContext.makeDefault()
        XCTAssertFalse(ctx.device.name.isEmpty, "device should report a non-empty name")
        XCTAssertNotNil(ctx.commandQueue.label ?? "")
        XCTAssertNotNil(ctx.segmenterLibrary)
        XCTAssertNotNil(ctx.volumeLibrary)
    }

    func testLibrariesAreLabelled() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available")
        }
        let ctx = try MetalContext.makeDefault()
        XCTAssertEqual(ctx.segmenterLibrary.label, "segmenter")
        XCTAssertEqual(ctx.volumeLibrary.label, "volume")
    }

    func testMissingNamedLibraryThrows() {
        guard MTLCreateSystemDefaultDevice() != nil else {
            return  // no Metal — nothing to assert
        }
        XCTAssertThrowsError(
            try MetalContext.makeDefault(segmenterLibraryName: "doesNotExistMetallib")
        ) { error in
            guard case MetalContext.SetupError.libraryUnavailable(let name) = error else {
                return XCTFail("expected SetupError.libraryUnavailable, got \(error)")
            }
            XCTAssertEqual(name, "doesNotExistMetallib")
        }
    }

    // Per design §3.1.1: MetalContext is `@unchecked Sendable` so it can cross actor
    // boundaries. The compile-time assertion below would fail to type-check if the
    // conformance were removed.
    func testIsSendable() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available")
        }
        let ctx = try MetalContext.makeDefault()
        let _: any Sendable = ctx
    }
}
#endif
