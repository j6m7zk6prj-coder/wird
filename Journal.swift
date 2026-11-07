import SwiftUI
import UIKit

// MARK: - Le journal : un objectif d'apprentissage, un programme de révision, et ce que tu coches chaque jour

enum Direction: String, Codable, CaseIterable, Identifiable {
    /// An-Nâs, Al-Falaq, Al-Ikhlâs… en remontant vers Al-Fâtiha (comme on apprend souvent Juz Amma).
    case backward
    /// Al-Fâtiha, Al-Baqara… dans l'ordre du Mushaf.
    case forward
    var id: String { rawValue }
    var label: String { self == .backward ? "En partant de la fin" : "Dans l’ordre du Mushaf" }
    var hint: String { self == .backward ? "An-Nâs, Al-Falaq, Al-Ikhlâs…" : "Al-Fâtiha, Al-Baqara, Âl ‘Imrân…" }
}

/// Ton objectif d'apprentissage.
struct Learning: Codable {
    var direction: Direction = .backward
    /// Le prochain verset à apprendre (sa place dans l'ordre choisi).
    var position = 0
    /// Ce que tu connais commence ici (0 = tout ce qui est avant ta position).
    var knownFrom = 0
    var pagesPerWeek = 3.0
    var created = Date()
    var dayKey = ""
    var dayStart = 0
    var dayCount: Int?
    /// Versets appris chaque jour.
    var log: [String: Int] = [:]
}

/// Ton programme de révision.
struct Revision: Codable {
    /// Tout réviser en combien de jours.
    var days = 14
    /// Où tu reprends (place dans ce que tu connais).
    var position = 0
    var tours = 0
    var created = Date()
    var dayKey = ""
    var dayStart = 0
    var dayTours = 0
    var dayCount: Int?
    /// Versets révisés chaque jour.
    var log: [String: Int] = [:]
}

/// Ton cours (par exemple le vendredi), où tu récites ce que tu as appris.
struct Course: Codable {
    /// Jour du cours (1 = dimanche … 6 = vendredi, 7 = samedi).
    var weekday = 6
    /// Heure du cours (19 h 00 si rien n'est choisi).
    var hour: Int?
    var minute: Int?
    // Anciennes données (Wird 2.4), gardées pour pouvoir relire le fichier.
    var lastPosition = 0
    var sessions: [CourseSession] = []
}

struct CourseSession: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var from: Int?
    var to: Int?
    var count: Int
    var validated: Bool
    var note: String
    /// Où en était le cours avant (pour pouvoir annuler).
    var previous: Int?
}

/// Ce qu'il y a à faire aujourd'hui.
struct DayChunk {
    let seq: [Int]
    let from: Int
    let to: Int
    let done: Bool
    var ayat: ArraySlice<Int> { seq[from..<to] }
    var isEmpty: Bool { to <= from }
}

enum Day {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.firstWeekday = 2
        return c
    }

    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func weekday(_ date: Date) -> Int { calendar.component(.weekday, from: date) }
    /// Les jours de la semaine (numéro du calendrier, nom), du lundi au dimanche.
    static let names: [(Int, String)] = [(2, "Lundi"), (3, "Mardi"), (4, "Mercredi"), (5, "Jeudi"), (6, "Vendredi"), (7, "Samedi"), (1, "Dimanche")]
    static func name(_ weekday: Int) -> String { names.first { $0.0 == weekday }?.1 ?? "" }
    static func add(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
}

@MainActor
@Observable
final class Journal {
    private(set) var learning: Learning?
    private(set) var revision: Revision?
    var message: String?

    private(set) var course: Course?

    private struct SaveFile: Codable {
        var learning: Learning?
        var revision: Revision?
        var course: Course?
    }

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wird", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(SaveFile.self, from: data) {
            learning = f.learning
            revision = f.revision
            course = f.course
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(SaveFile(learning: learning, revision: revision, course: course)) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    var today: String { Day.key(.now) }

    // MARK: Apprentissage

    func setLearning(_ l: Learning, _ q: QuranStore) {
        learning = l
        var r = revision ?? Revision()
        if r.position >= (known(q)?.count ?? 0) { r.position = 0 }
        revision = r
        save()
    }

    /// La suite de versets dans l'ordre d'apprentissage.
    func sequence(_ q: QuranStore) -> [Int] { q.sequence(learning?.direction ?? .backward) }

    /// Ce que tu connais (dans l'ordre d'apprentissage).
    func known(_ q: QuranStore?) -> [Int]? {
        guard let q, let l = learning else { return nil }
        let seq = q.sequence(l.direction)
        return Array(seq[min(l.knownFrom, l.position)..<min(l.position, seq.count)])
    }

    func knownPages(_ q: QuranStore) -> Double {
        guard let k = known(q) else { return 0 }
        return q.pages(k, 0, k.count)
    }

    /// Versets par jour pour tenir l'objectif de la semaine, à partir d'une position.
    func learningChunk(_ q: QuranStore) -> DayChunk? {
        guard let l = learning else { return nil }
        let seq = q.sequence(l.direction)
        let start = l.dayKey == today ? l.dayStart : l.position
        guard start < seq.count else { return DayChunk(seq: seq, from: seq.count, to: seq.count, done: l.log[today] != nil) }
        let end: Int
        if let c = l.dayCount, l.dayKey == today {
            end = min(seq.count, start + max(1, c))
        } else {
            end = q.advance(seq, from: start, pages: l.pagesPerWeek / 7, limit: seq.count)
        }
        return DayChunk(seq: seq, from: start, to: end, done: l.log[today] != nil)
    }

    func toggleLearning(_ q: QuranStore) {
        guard var l = learning, let c = learningChunk(q) else { return }
        if l.log[today] != nil {
            l.position = l.dayStart
            l.log[today] = nil
            message = "Annulé"
        } else {
            if l.dayKey != today { l.dayKey = today; l.dayStart = l.position; l.dayCount = c.to - c.from }
            l.position = c.to
            l.log[today] = c.to - c.from
            message = "Apprentissage noté, bravo !"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        learning = l
        save()
    }

    /// Un verset de plus ou de moins aujourd'hui.
    func adjustLearning(_ delta: Int, _ q: QuranStore) {
        guard var l = learning, let c = learningChunk(q), !c.done else { return }
        if l.dayKey != today { l.dayKey = today; l.dayStart = l.position }
        l.dayCount = max(1, min(c.seq.count - c.from, (c.to - c.from) + delta))
        learning = l
        save()
    }

    // MARK: Révision

    func setRevision(days: Int) {
        var r = revision ?? Revision()
        r.days = max(1, days)
        revision = r
        save()
    }

    /// Reprendre la révision à ce verset (place dans ce que tu connais).
    func setRevisionStart(_ index: Int) {
        var r = revision ?? Revision()
        r.position = max(0, index)
        if r.dayKey == today, r.log[today] == nil { r.dayKey = "" }
        revision = r
        save()
    }

    func revisionPerDay(_ q: QuranStore) -> Double {
        knownPages(q) / Double(max(1, revision?.days ?? 14))
    }

    func revisionChunk(_ q: QuranStore) -> DayChunk? {
        guard let r = revision, let k = known(q), !k.isEmpty else { return nil }
        var start = r.dayKey == today ? r.dayStart : r.position
        if start >= k.count { start = 0 }
        let end: Int
        if let c = r.dayCount, r.dayKey == today {
            end = min(k.count, start + max(1, c))
        } else {
            end = q.advance(k, from: start, pages: revisionPerDay(q), limit: k.count)
        }
        return DayChunk(seq: k, from: start, to: end, done: r.log[today] != nil)
    }

    func toggleRevision(_ q: QuranStore) {
        guard var r = revision, let c = revisionChunk(q) else { return }
        if r.log[today] != nil {
            r.position = r.dayStart
            r.tours = r.dayTours
            r.log[today] = nil
            message = "Annulé"
        } else {
            if r.dayKey != today { r.dayKey = today; r.dayCount = c.to - c.from }
            r.dayStart = c.from
            r.dayTours = r.tours
            r.position = c.to
            if r.position >= c.seq.count {
                r.position = 0
                r.tours += 1
                message = "Tour de révision terminé, machAllah !"
            } else {
                message = "Révision notée, bravo !"
            }
            r.log[today] = c.to - c.from
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        revision = r
        save()
    }

    func adjustRevision(_ delta: Int, _ q: QuranStore) {
        guard var r = revision, let c = revisionChunk(q), !c.done else { return }
        if r.dayKey != today { r.dayKey = today; r.dayStart = c.from }
        r.dayCount = max(1, min(c.seq.count - c.from, (c.to - c.from) + delta))
        revision = r
        save()
    }

    // MARK: Journal

    /// Jours d'affilée où tu as coché au moins une chose.
    var streak: Int {
        var d = Day.start(.now)
        if !active(d) { d = Day.add(-1, to: d) }
        var n = 0
        while active(d) {
            n += 1
            d = Day.add(-1, to: d)
        }
        return n
    }

    func active(_ d: Date) -> Bool {
        let k = Day.key(d)
        return learning?.log[k] != nil || revision?.log[k] != nil
    }

    func resetAll() {
        learning = nil
        revision = nil
        course = nil
        save()
    }

    // MARK: Cours

    func startCourse(weekday: Int = 6, hour: Int = 19, minute: Int = 0) {
        course = Course(weekday: weekday, hour: hour, minute: minute)
        save()
    }

    func setCourse(weekday: Int, hour: Int, minute: Int) {
        var c = course ?? Course()
        c.weekday = weekday
        c.hour = hour
        c.minute = minute
        course = c
        save()
    }

    func stopCourse() {
        course = nil
        save()
    }

    /// Le prochain cours (date et heure), à partir de maintenant.
    func nextCourse(after now: Date = .now) -> Date? {
        guard let c = course else { return nil }
        let cal = Day.calendar
        var comps = DateComponents()
        comps.weekday = c.weekday
        comps.hour = c.hour ?? 19
        comps.minute = c.minute ?? 0
        comps.second = 0
        return cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
    }

    /// Le cours d'avant (une semaine plus tôt).
    func previousCourse(_ now: Date = .now) -> Date? {
        nextCourse(after: now).map { Day.add(-7, to: $0) }
    }

    /// Ce que tu as appris depuis le dernier cours (à réciter au prochain).
    func learnedSinceCourse(_ q: QuranStore, now: Date = .now) -> [Int] {
        guard let l = learning, let prev = previousCourse(now) else { return [] }
        var count = 0
        var d = Day.add(1, to: Day.start(prev))
        while d <= Day.start(now) {
            count += l.log[Day.key(d)] ?? 0
            d = Day.add(1, to: d)
        }
        let seq = q.sequence(l.direction)
        let end = min(l.position, seq.count)
        return Array(seq[max(0, end - count)..<end])
    }
}
