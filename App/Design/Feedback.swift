import SwiftUI

// What the app FEELS like (see App/Design/README.md).
//
// Haptics are the cheapest way to make a screen feel like a real control and
// the easiest thing to leave out — an audit on 2026-08-28 found the app had
// thirty-odd buttons that write a row and exactly two that vibrate.
//
// The two names below are intent, not waveform: `commitFeedback` is "something
// was written", `blockedFeedback` is "that did not work". Retuning what the
// whole app feels like is then a matter of changing the style on ONE line
// here, rather than hunting call sites.

extension View {
    /// A row was written — a dose logged, a meal recorded, a reading saved.
    /// `trigger` must CHANGE to fire, so pass a counter that increments on
    /// success, never a Bool that is already true.
    func commitFeedback(trigger: some Equatable) -> some View {
        sensoryFeedback(.success, trigger: trigger)
    }

    /// The tap did not do what it looked like it would — a blocked shutter, a
    /// refused save.
    func blockedFeedback(trigger: some Equatable) -> some View {
        sensoryFeedback(.warning, trigger: trigger)
    }
}
