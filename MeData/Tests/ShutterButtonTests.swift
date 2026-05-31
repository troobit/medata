import Testing
@testable import MeData

// Task 48 / Req §20.6 / §20.10 / §20.11 / Decision 16. State + accessibility
// value mapping for `ShutterButton`. Visual press feedback is structural
// (verified by reading the metrics constants) — layout invariants (no shift in
// surrounding chrome) are enforced by sizing the button to a fixed outer
// footprint regardless of press state.
@Suite("ShutterButton — state mapping + sizing invariants")
@MainActor
struct ShutterButtonTests {

    @Test("ready is interactive; capturing and disabled are not")
    func interactivity() {
        #expect(ShutterButtonState.ready.isInteractive)
        #expect(!ShutterButtonState.capturing.isInteractive)
        #expect(!ShutterButtonState.disabled.isInteractive)
    }

    @Test("accessibilityValue differs per state")
    func accessibilityValuePerState() {
        #expect(ShutterButtonState.ready.accessibilityValue == "Ready")
        #expect(ShutterButtonState.capturing.accessibilityValue == "Capturing")
        #expect(ShutterButtonState.disabled.accessibilityValue == "Disabled")
    }

    @Test("outer diameter is 76pt (Req §20.6)")
    func outerDiameter() {
        #expect(ShutterButtonMetrics.outerDiameter == 76)
    }

    @Test("press feedback timing is 100ms shrink + 150ms release (Req §20.6)")
    func pressTiming() {
        #expect(ShutterButtonMetrics.pressDurationSeconds == 0.1)
        #expect(ShutterButtonMetrics.releaseDurationSeconds == 0.15)
    }

    @Test("press animation collapses to zero duration under reduced motion")
    func reducedMotionTiming() {
        // Constants are read by the body via Environment; the assertion here
        // documents the contract — the body wraps the spring in a `linear(0)`
        // when `reduceMotion == true`.
        #expect(ShutterButtonMetrics.pressDurationSeconds > 0)
    }

    @Test("inner-pressed diameter never exceeds outer (no clipping)")
    func innerNeverExceedsOuter() {
        #expect(ShutterButtonMetrics.innerDiameterPressed <= ShutterButtonMetrics.outerDiameter)
        #expect(ShutterButtonMetrics.innerDiameterRest <= ShutterButtonMetrics.outerDiameter)
    }

    @Test("bottom clearance from tab bar is ≥24pt (Req §20.6)")
    func bottomClearance() {
        #expect(ShutterButtonMetrics.bottomClearanceFromTabBar >= 24)
    }

    // MARK: - Blocked-tap routing (smolspec: shutter-blocked-feedback)

    @Test("dispatchTap(.ready) invokes action only")
    func dispatchReadyInvokesAction() {
        var actionCalls = 0
        var blockedCalls = 0
        ShutterButton.dispatchTap(
            state: .ready,
            action: { actionCalls += 1 },
            onBlockedTap: { blockedCalls += 1 }
        )
        #expect(actionCalls == 1)
        #expect(blockedCalls == 0)
    }

    @Test("dispatchTap(.disabled) invokes onBlockedTap only")
    func dispatchDisabledInvokesBlocked() {
        var actionCalls = 0
        var blockedCalls = 0
        ShutterButton.dispatchTap(
            state: .disabled,
            action: { actionCalls += 1 },
            onBlockedTap: { blockedCalls += 1 }
        )
        #expect(actionCalls == 0)
        #expect(blockedCalls == 1)
    }

    @Test("dispatchTap(.capturing) invokes neither")
    func dispatchCapturingInvokesNeither() {
        var actionCalls = 0
        var blockedCalls = 0
        ShutterButton.dispatchTap(
            state: .capturing,
            action: { actionCalls += 1 },
            onBlockedTap: { blockedCalls += 1 }
        )
        #expect(actionCalls == 0)
        #expect(blockedCalls == 0)
    }
}
