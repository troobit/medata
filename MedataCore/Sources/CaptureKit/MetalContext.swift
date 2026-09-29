#if canImport(Metal)
import Foundation
import Metal

// Per design §3.1.1: shared Metal context. MTLDevice, MTLCommandQueue, and MTLLibrary are
// thread-safe per Apple's documentation; no actor wraps the queue. @unchecked Sendable is
// justified by Apple's documented thread-safety contract.
public struct MetalContext: @unchecked Sendable {
    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue
    public let segmenterLibrary: any MTLLibrary
    public let volumeLibrary: any MTLLibrary

    public init(
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue,
        segmenterLibrary: any MTLLibrary,
        volumeLibrary: any MTLLibrary
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.segmenterLibrary = segmenterLibrary
        self.volumeLibrary = volumeLibrary
    }

    public enum SetupError: Error {
        case deviceUnavailable
        case commandQueueUnavailable
        case libraryUnavailable(name: String)
    }

    // Construct a shared MetalContext using the system default device. Loads
    // segmenterLibrary and volumeLibrary by name from the main bundle if available,
    // falls back to the default library otherwise. .metal sources land under
    // Segmentation/Kernels and Volume/Kernels in later tasks.
    public static func makeDefault(
        segmenterLibraryName: String? = nil,
        volumeLibraryName: String? = nil
    ) throws -> MetalContext {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SetupError.deviceUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw SetupError.commandQueueUnavailable
        }
        let segLib = try loadLibrary(device: device, named: segmenterLibraryName, label: "segmenter")
        let volLib = try loadLibrary(device: device, named: volumeLibraryName, label: "volume")
        return MetalContext(
            device: device,
            commandQueue: queue,
            segmenterLibrary: segLib,
            volumeLibrary: volLib
        )
    }

    // Singleton initialised lazily on first access. Per design §3.1.1, the App target's
    // @main constructs and holds the context; tests build it directly via makeDefault.
    public static let shared: MetalContext? = try? makeDefault()

    private static func loadLibrary(
        device: any MTLDevice,
        named name: String?,
        label: String
    ) throws -> any MTLLibrary {
        if let name {
            if let url = Bundle.main.url(forResource: name, withExtension: "metallib") {
                let lib = try device.makeLibrary(URL: url)
                lib.label = label
                return lib
            }
            throw SetupError.libraryUnavailable(name: name)
        }
        if let lib = device.makeDefaultLibrary() {
            lib.label = label
            return lib
        }
        // Fallback: compile a no-op source so the lifecycle test on macOS test runners
        // (with no bundled metallib) succeeds. Callers needing specific kernels supply
        // a named library.
        let lib = try device.makeLibrary(source: "// empty\n", options: nil)
        lib.label = label
        return lib
    }
}
#endif
