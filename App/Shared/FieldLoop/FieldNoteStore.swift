#if FIELD_LOOP
import Foundation
import OSLog

// Note persistence (ml-feedback-loop Req 3.1): one JSON file plus one PNG per
// note in `Documents/notes/`, following `CaptureBundleRecorder` rather than a
// `meals.sqlite` table.
//
// The file-per-note shape is what buys the requirement's exemptions for free:
// `deleteAllData()` and every other delete path reach `events` rows and the
// `meals/` artefact directory and nothing else, so notes are outside them by
// construction rather than by a rule someone has to remember. `Documents` is
// already exposed to the Files app and the wired pull (`UIFileSharingEnabled`),
// and pull-side dedup is filename-keyed — which is why `filenameStem` carries
// both the timestamp and the note id.
//
// An actor, like the recorder, so two quick notes serialise their writes; every
// failure is logged and swallowed (Req 1.6).
actor FieldNoteStore {
    static let shared = FieldNoteStore()

    private static let log = Logger(subsystem: "ie.medata.app", category: "FieldNote")

    private let directoryURL: URL

    init(directoryURL: URL = URL.documentsDirectory.appendingPathComponent(
        "notes", isDirectory: true
    )) {
        self.directoryURL = directoryURL
    }

    // The PNG is written first: a pull that lands between the two writes then
    // sees an orphan image rather than a note naming a file that does not
    // exist. `.atomic` on both, so neither can be read half-written.
    func save(_ note: FieldNote, screenshotPNG: Data?) {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            if let screenshotPNG {
                let imageURL = directoryURL
                    .appendingPathComponent(note.filenameStem)
                    .appendingPathExtension("png")
                try screenshotPNG.write(to: imageURL, options: .atomic)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(note)
            let noteURL = directoryURL
                .appendingPathComponent(note.filenameStem)
                .appendingPathExtension("json")
            try data.write(to: noteURL, options: .atomic)
            Self.log.notice(
                "event=fieldnote.saved stem=\(note.filenameStem, privacy: .public) screen=\(note.screenID, privacy: .public) mealLinked=\(note.meal != nil, privacy: .public) screenshot=\(note.screenshot != nil, privacy: .public)"
            )
        } catch {
            Self.log.error(
                "event=fieldnote.save.failed stem=\(note.filenameStem, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    // Used by FieldMaintenance's manifest pass (Decision 14).
    func deleteNote(stem: String) throws {
        for ext in ["json", "png"] {
            let url = directoryURL.appendingPathComponent(stem).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func fileURL(stem: String, extension ext: String) -> URL {
        directoryURL.appendingPathComponent(stem).appendingPathExtension(ext)
    }
}
#endif
