import AppIntents
import Foundation

// MARK: - Écouter : ce que le lecteur partage avec le widget « Reprendre l'écoute »

/// Le dernier morceau écouté et l'endroit où tu en étais.
struct ListenSnapshot: Codable {
    var trackID: String
    var title: String
    var artist: String
    var album: String
    /// Position (secondes) au moment `updated`.
    var position: Double
    var duration: Double
    var isPlaying: Bool
    var updated: Date
    /// La file d'attente, pour reprendre la suite après ce morceau.
    var queue: [String]

    static let kind = "WirdListen"
    static let file = "listen-snapshot.json"
    static let artworkFile = "listen-artwork.jpg"

    static func load() -> ListenSnapshot? { WirdShared.read(ListenSnapshot.self, file) }
    func save() { WirdShared.write(self, Self.file) }

    /// Où en est la lecture à une date donnée (elle avance toute seule pendant la lecture).
    func estimatedPosition(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(max(duration, position), position + max(0, date.timeIntervalSince(updated)))
    }

    static func saveArtwork(_ data: Data?) {
        guard let url = WirdShared.container?.appendingPathComponent(artworkFile) else { return }
        if let data {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func artworkData() -> Data? {
        guard let url = WirdShared.container?.appendingPathComponent(artworkFile) else { return nil }
        return try? Data(contentsOf: url)
    }
}

/// Ce que font les boutons du widget. Rempli par l'app au lancement ; le système lance Wird en arrière-plan si besoin.
enum ListenControl {
    @MainActor static var toggle: (@MainActor () -> Void)?
    @MainActor static var next: (@MainActor () -> Void)?
}

/// Lecture / pause depuis le widget, sans ouvrir l'app.
struct ToggleListeningIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Reprendre l’écoute"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ListenControl.toggle?()
        return .result()
    }
}

/// Morceau suivant depuis le widget.
struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Morceau suivant"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ListenControl.next?()
        return .result()
    }
}
