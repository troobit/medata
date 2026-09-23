#if FIELD_LOOP
import OSLog
import Persistence
import SwiftUI
import UIKit

// The always-reachable note affordance (ml-feedback-loop Req 1.1).
//
// Every screen except Home is a `.fullScreenCover`, and a cover presents above
// anything laid over the app's root view — so an overlay inside `AppRoot` would
// be buried the moment Capture or Records opened. The affordance therefore
// lives in its own `UIWindow` above `.alert`, which nothing the app presents
// can cover.
//
// Passthrough is explicit rather than inherited: the window is full-screen, so
// without an override it would swallow every touch in the app. `hitTest`
// returns nil everywhere outside the button's current frame, which the SwiftUI
// overlay reports on every layout pass and on every change of its drag offset
// (`.offset` moves only the rendering, so layout callbacks alone go stale).
//
// Being a separate window, the button is absent from screenshots of the main
// window by construction (Req 1.4) — no hide-then-render dance.
@MainActor
final class FieldNoteWindow: UIWindow {
    // In window coordinates; the two windows are full-screen and aligned, so
    // this is also the SwiftUI `.global` frame the overlay reports.
    var buttonFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Once the sheet is up this window owns the screen: the sheet's fields
        // need touches, and so does the backdrop the drag-to-dismiss uses.
        if rootViewController?.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }
        guard buttonFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

@MainActor
@Observable
final class FieldNoteController {
    static let shared = FieldNoteController()

    static let log = Logger(subsystem: "ie.medata.app", category: "FieldNote")

    private static let offsetXKey = "fieldNote.button.offsetX"
    private static let offsetYKey = "fieldNote.button.offsetY"

    // The main scene window, retained from the moment it joins the scene.
    // Screenshots render THIS window and never "the key window", which becomes
    // the note window as soon as the sheet takes first responder.
    private(set) weak var mainWindow: UIWindow?
    private var noteWindow: FieldNoteWindow?

    var isPresentingSheet = false
    // Injected once at launch by `MedataApp` (App/App.swift). The note window
    // lives outside `AppRoot`'s view tree, so nothing reaches it through the
    // SwiftUI environment.
    private(set) var store: (any PersistenceStore)?
    private(set) var buildStamp = "unstamped"
    private(set) var modelVersion = "unknown"

    // Handed to the sheet, which owns them from present until save.
    private(set) var pendingScreenshot: UIImage?
    private(set) var pendingScreenshotError: String?
    private(set) var pendingScreenID = "home"
    private(set) var pendingMeal: FieldNoteMealLink?
    private(set) var pendingEstimate: EstimateSnapshot?

    // Where the developer parked the button. Persisted so a relaunch mid-field
    // session does not put it back over the shutter.
    var buttonOffset: CGSize {
        didSet {
            let defaults = UserDefaults.standard
            defaults.set(Double(buttonOffset.width), forKey: Self.offsetXKey)
            defaults.set(Double(buttonOffset.height), forKey: Self.offsetYKey)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        buttonOffset = CGSize(
            width: defaults.double(forKey: Self.offsetXKey),
            height: defaults.double(forKey: Self.offsetYKey)
        )
    }

    func configure(store: any PersistenceStore, buildStamp: String, modelVersion: String) {
        self.store = store
        self.buildStamp = buildStamp
        self.modelVersion = modelVersion
    }

    // Called once, when the app's own window joins its scene. Idempotent: a
    // second call with the same scene is a no-op, so a SwiftUI re-render of the
    // installer cannot stack windows.
    func install(mainWindow window: UIWindow) {
        mainWindow = window
        guard noteWindow == nil, let scene = window.windowScene else { return }
        let note = FieldNoteWindow(windowScene: scene)
        note.windowLevel = .alert + 1
        note.backgroundColor = .clear
        note.isUserInteractionEnabled = true
        let host = UIHostingController(rootView: FieldNoteOverlay(controller: self))
        host.view.backgroundColor = .clear
        note.rootViewController = host
        // NOT makeKeyAndVisible: the main window keeps key until the sheet
        // actually needs first responder (see `presentSheet`).
        note.isHidden = false
        noteWindow = note
        Self.log.notice("event=fieldnote.window.installed level=\(note.windowLevel.rawValue, privacy: .public)")
    }

    func reportButtonFrame(_ frame: CGRect) {
        noteWindow?.buttonFrame = frame
    }

    // Req 1.4: the screenshot is taken HERE — at the tap, before the sheet
    // exists — against the retained main window. Req 1.6: nothing on this path
    // can fail the note; a failed render is recorded as a reason and the sheet
    // opens anyway.
    // `meal`/`screenID` override the mounted context, for surfaces that offer a
    // note about a row rather than about themselves — the Records meal-row
    // context menu, where the screen is a list and the subject is one meal in
    // it. Everything else passes nothing and takes the frontmost context.
    func invoke(meal: FieldNoteMealLink? = nil, screenID: String? = nil) {
        let context = FieldNoteContext.shared
        pendingScreenID = screenID ?? context.screenID
        pendingMeal = meal ?? context.meal
        pendingEstimate = meal == nil ? context.estimate : nil
        pendingScreenshot = nil
        pendingScreenshotError = nil
        let window = mainWindow
        Task {
            let shot = await FieldScreenshot.capture(window: window)
            pendingScreenshot = shot.image
            pendingScreenshotError = shot.failureReason
            presentSheet()
        }
    }

    private func presentSheet() {
        // The sheet's text field needs first responder, and a non-key window
        // cannot host one reliably. Handed back on dismissal.
        noteWindow?.makeKey()
        isPresentingSheet = true
    }

    // Freezes the note and hands it to the store. Fire-and-forget by design
    // (Req 1.6): nothing here is awaited by the UI and nothing here can fail
    // the capture flow, so the sheet dismisses on the same run loop turn.
    func save(text: String, carbsG: Double?, speechUsed: Bool) {
        let note = FieldNote(
            id: UUID(),
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            screenID: pendingScreenID,
            text: text,
            carbsG: carbsG,
            meal: pendingMeal,
            estimateSnapshot: pendingEstimate,
            screenshot: nil,
            screenshotError: pendingScreenshotError,
            speechUsed: speechUsed,
            buildStamp: buildStamp,
            modelVersion: modelVersion
        )
        var stamped = note
        // PNG encoding on the main actor, before the hop: UIImage is not
        // Sendable, and Data is.
        let png = pendingScreenshot?.pngData()
        if png != nil { stamped.screenshot = "\(note.filenameStem).png" }
        Task { await FieldNoteStore.shared.save(stamped, screenshotPNG: png) }
        // Req 3.2: the outcome row this note is about must outlive the
        // eviction bound it would otherwise fall out of. Both keys are used
        // where both exist — the id path is keyed on the id alone, so a note
        // saved before `persistAttemptRecord`'s detached save lands is still
        // protected when the row arrives, while the meal path also catches the
        // retries around the same meal (and is the ONLY path a note taken from
        // history has, where no attempt id is on screen).
        if let meal = stamped.meal, let store {
            Task {
                if let outcomeID = meal.outcomeID {
                    try? await store.markOutcomeProtected(id: outcomeID)
                }
                if let mealID = meal.mealID {
                    try? await store.markOutcomesProtected(mealID: mealID)
                }
            }
        }
    }

    func sheetDismissed() {
        pendingScreenshot = nil
        pendingScreenshotError = nil
        mainWindow?.makeKey()
    }
}

// Zero-size probe that hands the controller the app's own window the moment it
// joins the scene. A `UIWindowSceneDelegate` would be the textbook route, but
// this app has no app delegate at all and adding one for a developer-phase
// affordance would put `#if FIELD_LOOP` into the app's launch spine. The probe
// also yields the main-window reference the screenshot path requires, which a
// scene delegate would still have to look up.
struct FieldNoteWindowInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { ProbeView() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            FieldNoteController.shared.install(mainWindow: window)
        }
    }
}

// The button, and the sheet it raises. Hosted in the note window, so both sit
// above every cover in the app.
private struct FieldNoteOverlay: View {
    @Bindable var controller: FieldNoteController

    @State private var dragOffset: CGSize = .zero
    // The button's layout frame BEFORE `.offset` is applied. `.offset` is a
    // render-time translation that geometry callbacks never see, so the hit
    // region handed to the window must add the current offset itself — and
    // re-report on every offset change, which `onGeometryChange` alone never
    // fires for. Missing this left the hit region parked at the home corner
    // after the first drag: the visible button was outside it and dead.
    @State private var homeFrame: CGRect = .zero

    private var offset: CGSize {
        CGSize(
            width: controller.buttonOffset.width + dragOffset.width,
            height: controller.buttonOffset.height + dragOffset.height
        )
    }

    var body: some View {
        button
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 120)
            .sheet(isPresented: $controller.isPresentingSheet, onDismiss: {
                controller.sheetDismissed()
            }) {
                FieldNoteSheet(controller: controller)
            }
    }

    private var button: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color.black.opacity(0.55), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .offset(offset)
            // The hit area the window's `hitTest` allows through: the layout
            // frame shifted by the live offset, re-reported both when layout
            // moves and when the offset does, so a dragged button stays live
            // and the rest of the screen stays passthrough.
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                homeFrame = frame
                reportFrame()
            }
            .onChange(of: offset) {
                reportFrame()
            }
            .onTapGesture { controller.invoke() }
            .gesture(
                // minimumDistance keeps a tap a tap: below the threshold the
                // drag never starts and `onTapGesture` wins.
                DragGesture(minimumDistance: 10)
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        controller.buttonOffset = clampedOffset(CGSize(
                            width: controller.buttonOffset.width + value.translation.width,
                            height: controller.buttonOffset.height + value.translation.height
                        ))
                        dragOffset = .zero
                    }
            )
            .accessibilityIdentifier("fieldNote.button")
            .accessibilityLabel("Field note")
    }

    private func reportFrame() {
        controller.reportButtonFrame(
            homeFrame.offsetBy(dx: offset.width, dy: offset.height)
        )
    }

    // A committed park must keep the whole button on screen — an offset that
    // pushes it off-screen (or mostly off) leaves nothing to grab back.
    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        guard homeFrame != .zero, let bounds = controller.mainWindow?.bounds else {
            return proposed
        }
        return CGSize(
            width: min(
                max(proposed.width, bounds.minX - homeFrame.minX),
                bounds.maxX - homeFrame.maxX
            ),
            height: min(
                max(proposed.height, bounds.minY - homeFrame.minY),
                bounds.maxY - homeFrame.maxY
            )
        )
    }
}
#endif
