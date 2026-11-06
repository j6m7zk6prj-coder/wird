import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

// MARK: - Écouter : un récitateur, verset par verset, avec répétition

struct Reciter: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String

    static let all: [Reciter] = [
        Reciter(id: "Alafasy_128kbps", name: "Mishary Al-Afasy", note: "Voix claire, rythme moyen"),
        Reciter(id: "Husary_128kbps", name: "Mahmoud Al-Husary", note: "Lent et très net, idéal pour apprendre"),
        Reciter(id: "Husary_Muallim_128kbps", name: "Al-Husary (enseignement)", note: "Pour répéter après lui"),
        Reciter(id: "Minshawy_Murattal_128kbps", name: "Al-Minshawi", note: "Murattal"),
        Reciter(id: "Abdul_Basit_Murattal_192kbps", name: "Abdul Basit", note: "Murattal"),
        Reciter(id: "Abdurrahmaan_As-Sudais_192kbps", name: "Abdurrahman As-Sudais", note: "Rythme rapide"),
        Reciter(id: "Saood_ash-Shuraym_128kbps", name: "Saud Ash-Shuraym", note: "Rythme rapide"),
        Reciter(id: "MaherAlMuaiqly128kbps", name: "Maher Al-Muaiqly", note: "Rythme moyen"),
        Reciter(id: "Ghamadi_40kbps", name: "Saad Al-Ghamdi", note: "Léger, consomme peu de données")
    ]

    static func named(_ id: String) -> Reciter { all.first { $0.id == id } ?? all[0] }

    func url(surah: Int, ayah: Int) -> URL? {
        URL(string: "https://everyayah.com/data/\(id)/" + String(format: "%03d%03d", surah, ayah) + ".mp3")
    }
}

struct AyahRef: Hashable {
    let g: Int
    let surah: Int
    let ayah: Int
}

@MainActor
@Observable
final class Recitation {
    private(set) var queue: [AyahRef] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var loading = false
    private(set) var error: String?
    private(set) var title = ""
    /// Combien de fois chaque verset est répété (0 = sans fin).
    var repeatEach = UserDefaults.standard.object(forKey: "repeatEach") as? Int ?? 1 {
        didSet { UserDefaults.standard.set(repeatEach, forKey: "repeatEach") }
    }
    /// Recommencer tout le passage à la fin.
    var loopAll = false
    var speed: Float = UserDefaults.standard.object(forKey: "speed") as? Float ?? 1 {
        didSet {
            UserDefaults.standard.set(speed, forKey: "speed")
            if isPlaying { player.rate = speed }
        }
    }

    private let player = AVPlayer()
    private var done = 0
    private var endObserver: NSObjectProtocol?
    private var statusObserver: AnyCancellable?
    private var remoteReady = false

    var current: AyahRef? { queue.indices.contains(index) ? queue[index] : nil }

    func play(_ list: [AyahRef], from start: Int = 0, title: String) {
        guard !list.isEmpty else { return }
        queue = list
        index = min(max(0, start), list.count - 1)
        self.title = title
        done = 0
        error = nil
        activateSession()
        load()
    }

    func toggle() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else if current != nil {
            activateSession()
            if player.currentItem == nil { load() } else { player.playImmediately(atRate: speed); isPlaying = true }
        }
        updateNowPlaying()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        loading = false
        queue = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func next() {
        guard !queue.isEmpty else { return }
        done = 0
        if index + 1 < queue.count {
            index += 1
            load()
        } else if loopAll {
            index = 0
            load()
        } else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            updateNowPlaying()
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        done = 0
        index = max(0, index - 1)
        load()
    }

    private func load() {
        guard let a = current else { return }
        let reciter = Reciter.named(UserDefaults.standard.string(forKey: "reciter") ?? Reciter.all[0].id)
        guard let url = reciter.url(surah: a.surah, ayah: a.ayah) else { return }
        let item = AVPlayerItem(url: url)
        loading = true
        statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay: self.loading = false
                case .failed:
                    self.loading = false
                    self.isPlaying = false
                    self.error = "Impossible de charger l’audio. Vérifie ta connexion internet."
                default: break
                }
            }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishedOne() }
        }
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: speed)
        isPlaying = true
        updateNowPlaying()
    }

    private func finishedOne() {
        done += 1
        if repeatEach == 0 || done < repeatEach {
            player.seek(to: .zero)
            player.playImmediately(atRate: speed)
        } else {
            next()
        }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupRemote()
    }

    // Écran verrouillé : titre et boutons lecture / pause.
    private func setupRemote() {
        guard !remoteReady else { return }
        remoteReady = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let a = current else { return }
        let reciter = Reciter.named(UserDefaults.standard.string(forKey: "reciter") ?? Reciter.all[0].id)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "\(title) · verset \(a.ayah)",
            MPMediaItemPropertyArtist: reciter.name,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0
        ]
    }
}

// MARK: - S'enregistrer pour se réécouter

struct Recording: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

@MainActor
@Observable
final class VoiceRecorder {
    private(set) var recording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var playing: URL?
    private(set) var list: [Recording] = []
    private(set) var denied = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?

    static let folder: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Enregistrements", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() { refresh() }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        list = files.filter { $0.pathExtension == "m4a" }.map { url in
            Recording(url: url, date: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    func start(title: String) async {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { denied = true; return }
        stopPlaying()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let stamp = Date.now.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_FR")))
        let clean = "\(title) — \(stamp)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "h")
        let url = Self.folder.appendingPathComponent(clean + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder = r
        r.record()
        recording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = self.recorder?.currentTime ?? 0
            }
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        recording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        refresh()
    }

    func play(_ r: Recording) {
        if playing == r.url { stopPlaying(); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: r.url)
        player?.play()
        playing = player == nil ? nil : r.url
        let duration = player?.duration ?? 0
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.2))
            if self?.playing == r.url, self?.player?.isPlaying != true { self?.playing = nil }
        }
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        playing = nil
    }

    func delete(_ r: Recording) {
        if playing == r.url { stopPlaying() }
        try? FileManager.default.removeItem(at: r.url)
        refresh()
    }
}
