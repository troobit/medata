#if FIELD_LOOP
import SwiftUI

// The note sheet (ml-feedback-loop Req 1.2): typed entry and spoken entry in
// one surface, plus the optional carbohydrate-grams field a meal-linked note
// offers (Req 2.2).
//
// What the note is about is shown, not assumed: the screen id, the meal link
// when there is one, and the estimate frozen at invocation (Req 2.4). Those are
// functional signals — they tell the developer which capture this note will
// join Mac-side — not reassurance copy.
struct FieldNoteSheet: View {
    @Bindable var controller: FieldNoteController

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var carbsText = ""
    @State private var speech = FieldNoteSpeechModel()
    @State private var speechUsed = false
    @FocusState private var textFocused: Bool

    private var isMealLinked: Bool { controller.pendingMeal != nil }

    private var carbsValue: Double? {
        let trimmed = carbsText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || carbsValue != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $text)
                        .frame(minHeight: 110)
                        .focused($textFocused)
                        .accessibilityIdentifier("fieldNote.text")
                }
                speechSection
                if isMealLinked {
                    Section("Stated carbohydrate") {
                        HStack {
                            TextField("grams", text: $carbsText)
                                .keyboardType(.decimalPad)
                                .accessibilityIdentifier("fieldNote.carbs")
                            Text("g").foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                contextSection
            }
            .navigationTitle("Field note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        controller.save(
                            text: text,
                            carbsG: carbsValue,
                            speechUsed: speechUsed
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("fieldNote.save")
                }
            }
            .onAppear { textFocused = true }
            // The audio path is torn down whichever way the sheet leaves —
            // saved, cancelled, or swiped away — so no recording outlives the
            // surface that started it (Req 1.3).
            .onDisappear { Task { await speech.discard() } }
        }
    }

    // Typed and spoken entry in the same sheet (Req 1.2). Voice never replaces
    // the keyboard: the transcript lands IN the text editor above, where it is
    // edited like anything else, and an unavailable microphone costs nothing
    // but the button (Req 1.5).
    @ViewBuilder
    private var speechSection: some View {
        Section("Voice") {
            switch speech.state {
            case .unavailable(let reason):
                LabeledContent("Voice entry off", value: reason)
                    .font(.footnote)
                    .accessibilityIdentifier("fieldNote.speechUnavailable")
            case .preparing:
                LabeledContent("Voice", value: "preparing")
                    .font(.footnote)
            case .idle, .listening:
                Button {
                    Task { await toggleSpeech() }
                } label: {
                    Label(
                        speech.isListening ? "Stop and insert" : "Speak",
                        systemImage: speech.isListening ? "stop.circle" : "mic"
                    )
                }
                .accessibilityIdentifier("fieldNote.speak")
                if speech.isListening, !speech.volatile.isEmpty {
                    // Shown, never saved: a volatile hypothesis may never be
                    // reissued as final.
                    Text(speech.volatile)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func toggleSpeech() async {
        if speech.isListening {
            await speech.stop()
            let transcribed = speech.transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !transcribed.isEmpty else { return }
            text += text.isEmpty ? transcribed : " \(transcribed)"
            speechUsed = true
            await speech.discard()
        } else {
            textFocused = false
            await speech.start()
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        Section("Context") {
            LabeledContent("Screen", value: controller.pendingScreenID)
            // Whether this note is tied to an attempt must be readable at a
            // glance — from the capture screen a bare truncated id was not,
            // and an unlinked note said nothing at all. A linked attempt
            // shows when it happened; an unlinked note says so outright.
            if let meal = controller.pendingMeal {
                if let mealID = meal.mealID {
                    LabeledContent("Meal", value: mealID.uuidString.prefix(8).lowercased())
                }
                if meal.outcomeID != nil || meal.timestampMs != nil {
                    LabeledContent("Attempt", value: attemptDescription(meal))
                }
            } else {
                LabeledContent("Attempt", value: "none linked")
            }
            if let estimate = controller.pendingEstimate {
                LabeledContent(
                    "Estimate",
                    value: "\(Int(estimate.displayedTotalCarbsG.rounded())) g carbs"
                )
                ForEach(estimate.foods, id: \.classID) { food in
                    LabeledContent(
                        food.displayName,
                        value: "\(Int(food.massG.rounded())) g"
                    )
                    .font(.caption)
                }
            }
            if let reason = controller.pendingScreenshotError {
                LabeledContent("Screenshot", value: reason)
            }
        }
        .font(.footnote)
    }

    // "40 sec. ago" answers the capture-screen question — WHICH attempt this
    // note will join — in the terms the developer is thinking in; the short id
    // stays for the Mac-side join.
    private func attemptDescription(_ meal: FieldNoteMealLink) -> String {
        let id = meal.outcomeID.map { String($0.uuidString.prefix(8)).lowercased() }
        guard let timestampMs = meal.timestampMs else { return id ?? "linked" }
        let when = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let ago = formatter.localizedString(for: when, relativeTo: Date())
        return id.map { "\($0) · \(ago)" } ?? ago
    }
}
#endif
