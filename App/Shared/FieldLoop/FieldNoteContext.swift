#if FIELD_LOOP
import SwiftUI

// Which screen the developer is looking at, and what meal it is about
// (ml-feedback-loop Req 1.4 / 2.1). The app has no app-wide screen enum — the
// shell is `AppRoot.ActiveSheet` covers over `HomeView`, each cover holding its
// own `NavigationStack` keyed by its own route enum — so screen identity is
// composed here from what the surfaces themselves declare.
//
// The composition is a stack, not a single value. Each `.fieldScreen(…)` mount
// point pushes an entry keyed by a token owned by that view's `@State` and pops
// it on disappear; the top of the stack is the current screen. That survives
// SwiftUI's freedom to run a pushed view's `onAppear` before the covered view's
// `onDisappear` — removal is by token, never by position — and it gives the
// design's "sheets inside covers fall back to the hosting cover's id" for free:
// a sheet that mounts nothing simply leaves the cover's entry on top.
@MainActor
@Observable
final class FieldNoteContext {
    static let shared = FieldNoteContext()

    struct Entry: Identifiable, Equatable {
        let id: UUID
        var screenID: String
        var meal: FieldNoteMealLink?
        var estimate: EstimateSnapshot?
    }

    private(set) var stack: [Entry] = []

    // `home` is the launch root and the only screen that can be on-screen with
    // nothing mounted (a mount races its own first frame), so it is the floor
    // rather than an "unknown" sentinel that would need interpreting Mac-side.
    var screenID: String { stack.last?.screenID ?? "home" }

    // The frontmost meal surface, if any. Read at note-save time, so a note
    // taken on Records after backing out of a meal carries no stale link.
    var meal: FieldNoteMealLink? {
        guard let top = stack.last, let meal = top.meal, !meal.isEmpty else { return nil }
        return meal
    }

    var estimate: EstimateSnapshot? {
        guard stack.last?.meal != nil else { return nil }
        return stack.last?.estimate
    }

    var isMealLinked: Bool { meal != nil }

    func push(_ entry: Entry) {
        stack.removeAll { $0.id == entry.id }
        stack.append(entry)
    }

    func update(_ entry: Entry) {
        guard let index = stack.firstIndex(where: { $0.id == entry.id }) else {
            push(entry)
            return
        }
        stack[index] = entry
    }

    func pop(token: UUID) {
        stack.removeAll { $0.id == token }
    }
}

// The capture cover is the one screen whose identity is a state, not a place:
// a note about "the shutter never armed" and one about "it refused" are about
// different things on the same cover.
extension CaptureState {
    var fieldScreenID: String {
        switch self {
        case .initialising: return "capture.initialising"
        case .permissionDenied: return "capture.permissionDenied"
        case .trackingLost: return "capture.trackingLost"
        case .ready: return "capture.ready"
        case .capturing: return "capture.capturing"
        case .estimating: return "capture.estimating"
        case .showingResult: return "capture.result"
        case .refused: return "capture.refused"
        }
    }
}

extension View {
    // The one mount point (~8 uses). A plain screen passes an id; a meal
    // surface passes its join keys and the estimate as it is currently
    // displayed. `estimate` is a VALUE, not a closure, on purpose: the
    // displayed figures on ResultView live in the view struct's own `@State`,
    // so a closure captured once at mount would freeze the pre-adjustment
    // numbers and quietly contradict Req 2.4.
    func fieldScreen(
        _ id: String,
        meal: FieldNoteMealLink? = nil,
        estimate: EstimateSnapshot? = nil
    ) -> some View {
        modifier(FieldScreenModifier(screenID: id, meal: meal, estimate: estimate))
    }
}

private struct FieldScreenModifier: ViewModifier {
    let screenID: String
    let meal: FieldNoteMealLink?
    let estimate: EstimateSnapshot?

    // Owned by this view instance, so the entry it registered is the entry it
    // removes — identity survives re-renders and sibling mounts of the same id.
    @State private var token = UUID()

    private var entry: FieldNoteContext.Entry {
        .init(id: token, screenID: screenID, meal: meal, estimate: estimate)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { FieldNoteContext.shared.push(entry) }
            .onDisappear { FieldNoteContext.shared.pop(token: token) }
            .onChange(of: entry) { _, new in
                FieldNoteContext.shared.update(new)
            }
    }
}
#endif
