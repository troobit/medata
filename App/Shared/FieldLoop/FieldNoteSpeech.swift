#if FIELD_LOOP
// `@preconcurrency`: `AVAudioConverter.convert(to:error:)` takes a
// `@Sendable` input block, but the `AVAudioPCMBuffer` it must hand back is
// not `Sendable`. The block is invoked synchronously by `convert` on this
// same thread, so the capture is safe; the annotation says the API predates
// Sendable rather than that the buffer crosses a boundary.
@preconcurrency import AVFAudio
import AVFoundation
import Foundation
import OSLog
import Speech

// Spoken note entry (ml-feedback-loop Req 1.3, 1.5) on iOS 26's
// `SpeechAnalyzer` / `SpeechTranscriber`.
//
// Req 1.3 is satisfied structurally rather than by configuration: this API has
// no server path at all (unlike the legacy `SFSpeechRecognizer`, whose
// `requiresOnDeviceRecognition` flag was the only thing standing between a note
// and Apple's servers). The locale model is fetched once by the OS through
// `AssetInventory`; that download is a model fetch, not audio leaving the
// device, which is what the requirement constrains.
//
// Audio is never retained: the engine's buffers are converted, handed to the
// analyser, and dropped. Only the confirmed transcript survives the sheet.
//
// Every unavailable path — permission refused, microphone busy, locale
// unsupported, asset not installed — lands in `.unavailable(reason)`, which the
// sheet states while leaving typed entry untouched (Req 1.5).
@MainActor
@Observable
final class FieldNoteSpeechModel {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)
    }

    private static let log = Logger(subsystem: "ie.medata.app", category: "FieldNote")

    private(set) var state: State = .idle
    // What the analyser has finalised. `finalizeAndFinish` is the only thing
    // that promotes text into here: a volatile hypothesis may never be reissued
    // as a final result, so treating volatile text as the transcript would
    // silently invent words the developer never said.
    private(set) var transcript = ""
    // The live hypothesis, shown while listening and never saved.
    private(set) var volatile = ""

    private var speechAnalyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?

    var isListening: Bool { state == .listening }

    // The locale the transcriber will actually serve. `en_IE` is the developer's
    // locale and is not necessarily a supported one; `supportedLocale(equivalentTo:)`
    // is the framework's own mapping to the nearest served variant, so asking it
    // beats hard-coding `en_US` and beats assuming the current locale works.
    private static func resolveLocale() async -> Locale? {
        let current = Locale.current
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: current) {
            return equivalent
        }
        return await SpeechTranscriber.supportedLocales.first {
            $0.language.languageCode == current.language.languageCode
        }
    }

    func start() async {
        guard state != .listening else { return }
        state = .preparing
        volatile = ""

        guard await requestMicrophone() else {
            fail("microphone permission denied")
            return
        }
        guard let locale = await Self.resolveLocale() else {
            fail("no supported speech locale")
            return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        do {
            // Reservation first: the framework caps how many locales one app
            // may hold installed (`AssetInventory.maximumReservedLocales`), and
            // an unreserved locale can have its assets reclaimed underneath a
            // running transcriber. Idempotent, so this runs on every start.
            _ = try? await AssetInventory.reserve(locale: locale)
            // One-time, OS-mediated model download. Absent network on first
            // field launch lands here, and the sheet says so rather than
            // failing silently mid-sentence.
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                try await request.downloadAndInstall()
            }
        } catch {
            fail("speech model not installed")
            return
        }

        // The format lives on the analyser, not the transcriber: it is a
        // property of the whole module chain, not of one module.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            fail("no compatible audio format")
            return
        }
        let speechAnalyzer = SpeechAnalyzer(modules: [transcriber])
        self.speechAnalyzer = speechAnalyzer
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = builder

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        transcript += transcript.isEmpty ? text : " \(text)"
                        volatile = ""
                    } else {
                        volatile = text
                    }
                }
            } catch {
                Self.log.error(
                    "event=fieldnote.speech.results.failed error=\(String(describing: error), privacy: .public)"
                )
            }
        }

        do {
            try await speechAnalyzer.start(inputSequence: stream)
            try startAudio(analyzerFormat: format)
        } catch {
            Self.log.error(
                "event=fieldnote.speech.start.failed error=\(String(describing: error), privacy: .public)"
            )
            fail("microphone unavailable")
            return
        }
        state = .listening
    }

    // Stops the microphone and drains the analyser. Returns only once the
    // finalised text is in `transcript`, which is what the sheet then makes
    // editable (Req 1.3: the transcript is displayed for editing before save).
    func stop() async {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputBuilder?.finish()
        inputBuilder = nil
        try? await speechAnalyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        speechAnalyzer = nil
        transcriber = nil
        converter = nil
        volatile = ""
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        if state == .listening || state == .preparing { state = .idle }
    }

    // Called when the sheet closes without saving, and after a save: the audio
    // path is torn down either way and nothing about it is retained.
    func discard() async {
        await stop()
        transcript = ""
    }

    private func fail(_ reason: String) {
        state = .unavailable(reason)
        Self.log.notice("event=fieldnote.speech.unavailable reason=\(reason, privacy: .public)")
    }

    private func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    private func startAudio(analyzerFormat: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // The analyser states the format it wants; the hardware states what it
        // has. Converting explicitly is required — handing the analyser the
        // hardware format works on some devices and silently produces nothing
        // on others.
        converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                guard let self, let builder = inputBuilder else { return }
                guard let converted = convert(buffer, to: analyzerFormat) else { return }
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        if buffer.format == format { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: capacity
        ) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            Self.log.error(
                "event=fieldnote.speech.convert.failed error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }
}
#endif
