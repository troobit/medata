#if HARNESS_ENABLED
import Foundation
import PortableContracts
import SwiftProtobuf

// Loads PbMealFixture records from a directory of .fixture binary-proto files.
// Enforces the segmenter_checkpoint_sha256 guard per design §7.3: any fixture
// whose recorded checkpoint hash does not match the expected value is refused.
public enum FixtureLoader {
    public enum Error: Swift.Error, Equatable {
        case checkpointMismatch(expected: String, got: String, file: String)
        case parseFailure(file: String)
        case directoryUnreadable(String)
    }

    // Load all `.fixture` files from `directoryURL` in lexicographic order.
    // Throws `checkpointMismatch` on the first fixture whose sha256 != `checkpointSHA256`.
    public static func load(
        from directoryURL: URL,
        checkpointSHA256: String
    ) throws -> [PbMealFixture] {
        let urls: [URL]
        do {
            urls = try FileManager.default
                .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "fixture" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw Error.directoryUnreadable(directoryURL.path)
        }

        return try urls.map { url in
            let data = try Data(contentsOf: url)
            let fixture: PbMealFixture
            do {
                fixture = try PbMealFixture(serializedBytes: data)
            } catch {
                throw Error.parseFailure(file: url.lastPathComponent)
            }
            guard fixture.segmenterCheckpointSha256 == checkpointSHA256 else {
                throw Error.checkpointMismatch(
                    expected: checkpointSHA256,
                    got: fixture.segmenterCheckpointSha256,
                    file: url.lastPathComponent
                )
            }
            return fixture
        }
    }
}
#endif
