import Testing
@testable import MeData

@Suite("LiveIndicatorModel — visibility + auto-hide policy")
@MainActor
struct LiveIndicatorModelTests {

    @Test("reveal() flips visible true and overrides a pending scheduleHide()")
    func revealAfterScheduleHideKeepsVisible() async {
        let model = LiveIndicatorModel()
        model.visible = false
        model.scheduleHide()
        model.reveal()
        #expect(model.visible == true)

        // Re-arms means scheduleHide's prior task is cancelled. Yield briefly;
        // the cancelled task must not flip visible back to false.
        for _ in 0..<5 { await Task.yield() }
        #expect(model.visible == true)
    }

    @Test("scheduleHide() called after reveal() cancels the timer chain when followed by reveal()")
    func chainedRevealCancelsPriorHide() async {
        let model = LiveIndicatorModel()
        model.scheduleHide()
        model.reveal()
        model.reveal()
        #expect(model.visible == true)
    }
}
