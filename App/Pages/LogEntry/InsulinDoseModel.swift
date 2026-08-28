import Foundation
import Observation
import Persistence

// View-model for the insulin dose-entry sheet (PRD
// regression-suggestion-integration App 2–5). Opens pre-filled so the happy
// path stays two taps, and owns the shared digit-shift buffer. Floor 1 U, hard
// stop 60 U (the store accepts 0–60; the UI floor is deliberately 1 so a save
// can never read 0). `insulin_type` is filled from the per-kind Settings
// defaults at save time — the sheet never asks for the product name (App 5).
//
// The value is TYPED, not stepped (specs/ui/unified-entry-sheet Decision 1).
// The stepper and its hold-acceleration schedule are gone: the numeral is a
// render of a digit buffer, and a relative control mutates the value without
// the buffer, so the two disagree after any mixed sequence.
//
// What opens the sheet, highest precedence first (Req 3.1–3.3, Decision 2):
//
//   armed meal suggestion  →  the seed's own provenance caption
//   remembered value FOR THIS KIND  →  `last bolus` / `last basal`
//   fixed 10 U  →  `units`
//
// The per-kind scoping is the safety property: a 14 U basal can never become
// the opening value of the next bolus. The caption is the other half — a
// variable default that does not say where it came from is a number the user
// did not choose, on a surface that saves in two taps.
@Observable
@MainActor
final class InsulinDoseModel {
    static let minUnits = 1
    static let maxUnits = 60

    // The shared digit-shift buffer: whole units, so `1`, `2` reads 12 U.
    private(set) var entry = DigitEntry(
        decimals: 0,
        range: Double(InsulinDoseModel.minUnits)...Double(InsulinDoseModel.maxUnits))

    var units: Int { max(Int(entry.value.rounded()), 0) }

    var kind: InsulinKind = .bolus {
        didSet {
            guard kind != oldValue else { return }
            // Req 3.5: the newly selected kind's opening value has not been
            // edited, so it arrives with its own caption intact.
            loadOpeningValue()
        }
    }
    // The seed's provenance caption while the seeded value is untouched, nil
    // otherwise (specs/data/insulin-dosing design-direction §3.2). Cleared by
    // the first edit and never restored for this presentation.
    private(set) var seedCaption: String?
    // Administration time; the compact back-dating control writes here and the
    // saved event carries it (UTC ms conversion happens in the store).
    var timestamp = Date()
    private(set) var isSaving = false
    private(set) var saveError: String?
    // The id of the event the last successful save wrote. The dose schedule
    // needs it: an adjusted dose closes its occurrence with `wasNominal` false
    // and links THIS event, rather than the sheet writing one event and the
    // schedule writing another.
    private(set) var savedEventID: UUID?

    private let store: any PersistenceStore

    // One optional parameter, defaulted, changes nothing that does not opt in
    // (specs/data/insulin-dosing Req 6.3, 6.4). With no seed the sheet opens
    // at 10 U exactly as it always has.
    init(store: any PersistenceStore, seed: DoseSeed? = nil) {
        self.store = store
        self.armedSeed = seed
        loadOpeningValue()
    }

    // Held so a kind change can re-apply the precedence rule rather than
    // reconstructing it. An armed suggestion belongs to the meal, not to a
    // kind, so it outranks the remembered value for whichever kind is showing.
    private let armedSeed: DoseSeed?

    // MARK: - Opening value (Req 3.1–3.5)

    private static func rememberedKey(_ kind: InsulinKind) -> String {
        "dose.lastUnits.\(kind == .bolus ? "bolus" : "basal")"
    }

    static func remembered(_ kind: InsulinKind) -> Int? {
        let stored = UserDefaults.standard.integer(forKey: rememberedKey(kind))
        return stored >= minUnits ? stored : nil
    }

    private func loadOpeningValue() {
        if let armedSeed {
            entry.set(value: Double(min(max(armedSeed.units, Self.minUnits), Self.maxUnits)))
            seedCaption = armedSeed.provenance
        } else if let last = Self.remembered(kind) {
            entry.set(value: Double(min(max(last, Self.minUnits), Self.maxUnits)))
            seedCaption = kind == .bolus ? "last bolus" : "last basal"
        } else {
            entry.set(value: Double(Self.fixedDefaultUnits))
            seedCaption = nil
        }
    }

    static let fixedDefaultUnits = 10

    // MARK: - Typing

    // Every keystroke is an edit, so the provenance caption is consumed on the
    // first one and never restored for this presentation.
    func setDigits(_ raw: String) {
        entry.setDigits(raw)
        consumeSeedCaption()
    }

    /// Chips set the value absolutely, which is why they can coexist with the
    /// keypad where an arrow could not (Req 1.5).
    func apply(units value: Int) {
        entry.set(value: Double(min(max(value, Self.minUnits), Self.maxUnits)))
        consumeSeedCaption()
    }

    var canSave: Bool { entry.isInRange }

    // What sits under the numeral: the seed's provenance until the first
    // edit, the plain unit label after it.
    var unitsCaption: String { seedCaption ?? "units" }

    /// The named values worth one tap (Req 1.5): the armed suggestion, and the
    /// kind's remembered value where it differs from what is showing.
    var chips: [(title: String, units: Int)] {
        var out: [(String, Int)] = []
        if let armedSeed, armedSeed.units != units {
            out.append(("suggested \(armedSeed.units) U", armedSeed.units))
        }
        if let last = Self.remembered(kind), last != units {
            out.append((kind == .bolus ? "last \(last) U" : "last \(last) U", last))
        }
        return out
    }

    // Consumes the provenance caption. Must be driven by the INTENT to edit,
    // never by an observed change to `units`: `step(_:)` clamps, so pressing
    // − at 1 U or + at 60 U leaves the value untouched and a value observer
    // would never fire — the caption would survive an edit it was meant to be
    // consumed by.
    func consumeSeedCaption() {
        seedCaption = nil
    }

    // MARK: - Save (App 2)

    // One-tap save: writes the dose through the core API and returns true on
    // success so the view can dismiss. The Graph refreshes itself via the
    // store's `eventsDidChange` tick — no manual reload.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let dose = InsulinDose(
            timestamp: timestamp,
            units: Double(units),
            kind: kind,
            insulinType: InsulinProduct.name(for: kind)
        )
        do {
            try await store.saveInsulinDose(dose)
            savedEventID = dose.id
            // Req 3.1/3.6: remembered per kind, and outliving the process.
            UserDefaults.standard.set(units, forKey: Self.rememberedKey(kind))
            return true
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    // The per-kind product string (App 5) now lives in `InsulinProduct`
    // (App/SettingsKeys.swift): the dose schedule's notification handler writes
    // insulin events with the app not running, so the lookup had to be
    // reachable without this view-model existing.

    // MARK: - Pre-seeding from a scheduled dose (dose-schedule Req 5.1)

    // The ADJUST action's entry point: the sheet opens with the schedule's kind
    // and nominal amount already set, so a changed dose is an adjustment rather
    // than a fresh entry. Nothing is computed or pre-adjusted from recorded
    // activity — the magnitude of that relationship is unmeasured and this
    // does not invent one (Req 5.3).
    func seed(units: Int, kind: InsulinKind) {
        self.kind = kind
        entry.set(value: Double(min(max(units, Self.minUnits), Self.maxUnits)))
    }
}
