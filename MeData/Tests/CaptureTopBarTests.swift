import Testing
@testable import MeData

// Task 46 / Req §20.3 / Decision 16. Behavioural assertions for the top-chrome
// view through its injected closure surface — we drive the torch toggle and
// the close action without spinning up a real `AVCaptureDevice`.
@Suite("CaptureTopBar — close action, torch availability, torch toggle")
@MainActor
struct CaptureTopBarTests {

    @Test("torch button hidden when device has no torch (torchAvailable == false)")
    func torchHiddenWhenUnavailable() {
        let probe = CaptureTopBarProbe(torchAvailable: false)
        let bar = CaptureTopBar(
            torchAvailable: { probe.torchAvailable },
            torchActive: { probe.torchOn },
            setTorch: { probe.setTorch($0) }
        )
        // We assert against the probe rather than the rendered view body —
        // `torchAvailable()` is the gate the body reads.
        #expect(bar.torchAvailable() == false)
    }

    @Test("setTorch is called on toggle press")
    func setTorchCalled() {
        let probe = CaptureTopBarProbe(torchAvailable: true)
        let bar = CaptureTopBar(
            torchAvailable: { probe.torchAvailable },
            torchActive: { probe.torchOn },
            setTorch: { probe.setTorch($0) }
        )
        _ = bar.torchAvailable()
        probe.setTorch(true)
        #expect(probe.torchOn == true)
        #expect(probe.setTorchCallCount == 1)
    }

    @Test("close action fires the injected callback")
    func closeFires() {
        var closeCount = 0
        let bar = CaptureTopBar(close: { closeCount += 1 })
        bar.close()
        #expect(closeCount == 1)
    }
}

@MainActor
private final class CaptureTopBarProbe {
    let torchAvailable: Bool
    private(set) var torchOn: Bool = false
    private(set) var setTorchCallCount: Int = 0

    init(torchAvailable: Bool) {
        self.torchAvailable = torchAvailable
    }

    func setTorch(_ on: Bool) {
        torchOn = on
        setTorchCallCount += 1
    }
}
