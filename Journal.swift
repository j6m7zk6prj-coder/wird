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

/// Ce qu'il reste à apprendre avant le prochain cours, réparti sur les jours restants.
struct CoursePlan {
    /// Jours d'apprentissage avant le cours, aujourd'hui compris (le jour du cours ne compte pas).
    let daysLeft: Int
    /// Objectif par cours (= les pages par semaine).
    let goal: Double
    /// Pages déjà apprises pour ce cours, sans compter aujourd'hui.
    let done: Double
    var remaining: Double { max(0, goal - done) }
    /// Pages à apprendre aujourd'hui.
    var today: Double { remaining > 0.01 ? remaining / Double(max(1, daysLeft)) : goal / 7 }
    var reached: Bool { remaining <= 0.01 }
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
    /// Nombre de jours entre deux dates (à minuit).
    static func between(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: start(a), to: start(b)).day ?? 0
    }
}

@MainActor
@Observable
final class Journal {
    private(set) var learning: Learning?
    private(set) var revision: Revision?
    var message: String?

    private(set) var course: Course?

    /// Appelé après chaque enregistrement (pour mettre à jour les widgets).
    @ObservationIgnored var onSave: (@MainActor () -> Void)?

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
        onSave?()
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
    func learningChunk(_ q: QuranStore, now: Date = .now, using alt: Learning? = nil) -> DayChunk? {
        guard let l = alt ?? learning else { return nil }
        let today = Day.key(now)
        let seq = q.sequence(l.direction)
        let start = l.dayKey == today ? l.dayStart : l.position
        guard start < seq.count else { return DayChunk(seq: seq, from: seq.count, to: seq.count, done: l.log[today] != nil) }
        let end: Int
        if let c = l.dayCount, l.dayKey == today {
            end = min(seq.count, start + max(1, c))
        } else {
            end = q.advance(seq, from: start, pages: coursePlan(q, now: now, using: l)?.today ?? l.pagesPerWeek / 7, limit: seq.count)
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

    func revisionChunk(_ q: QuranStore, now: Date = .now, using alt: Revision? = nil) -> DayChunk? {
        guard let r = alt ?? revision, let k = known(q), !k.isEmpty else { return nil }
        let today = Day.key(now)
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

    // MARK: Widgets

    /// L'apprentissage comme si tu cochais (ou décochais) aujourd'hui.
    func learningFlipped(_ q: QuranStore, now: Date = .now) -> Learning? {
        guard var l = learning, let c = learningChunk(q, now: now) else { return nil }
        let key = Day.key(now)
        if l.log[key] != nil {
            l.position = l.dayStart
            l.log[key] = nil
        } else {
            guard !c.isEmpty else { return nil }
            l.dayKey = key
            l.dayStart = c.from
            l.dayCount = c.to - c.from
            l.position = c.to
            l.log[key] = c.to - c.from
        }
        return l
    }

    /// La révision comme si tu cochais (ou décochais) aujourd'hui.
    func revisionFlipped(_ q: QuranStore, now: Date = .now) -> Revision? {
        guard var r = revision, let c = revisionChunk(q, now: now) else { return nil }
        let key = Day.key(now)
        if r.log[key] != nil {
            r.position = r.dayStart
            r.tours = r.dayTours
            r.log[key] = nil
        } else {
            guard !c.isEmpty else { return nil }
            r.dayKey = key
            r.dayCount = c.to - c.from
            r.dayStart = c.from
            r.dayTours = r.tours
            r.position = c.to
            if r.position >= c.seq.count {
                r.position = 0
                r.tours += 1
            }
            r.log[key] = c.to - c.from
        }
        return r
    }

    /// Le programme des prochains jours (aujourd'hui compris), si tu coches chaque jour.
    func learningForecast(_ q: QuranStore, from now: Date = .now, days: Int) -> [(date: Date, chunk: DayChunk)] {
        guard var l = learning else { return [] }
        var out: [(date: Date, chunk: DayChunk)] = []
        for i in 0..<days {
            let date = i == 0 ? now : Day.add(i, to: Day.start(now)).addingTimeInterval(60)
            guard let c = learningChunk(q, now: date, using: l), !c.isEmpty else { break }
            out.append((date: date, chunk: c))
            let key = Day.key(date)
            if l.log[key] == nil {
                l.dayKey = key
                l.dayStart = c.from
                l.dayCount = c.to - c.from
                l.position = c.to
                l.log[key] = c.to - c.from
            }
        }
        return out
    }

    /// Ce que tu as coché sur les widgets depuis la dernière ouverture de l'app.
    func applyWidgetChecks(_ checks: [WidgetCheck], _ q: QuranStore) {
        var changed = false
        for c in checks {
            if c.kind == "learning", var l = learning {
                if c.done, l.log[c.day] == nil, c.to > c.from {
                    let start = l.dayKey == c.day ? l.dayStart : l.position
                    guard start == c.from else { continue }
                    l.dayKey = c.day
                    l.dayStart = c.from
                    l.dayCount = c.to - c.from
                    l.position = c.to
                    l.log[c.day] = c.to - c.from
                } else if !c.done, l.log[c.day] != nil, l.dayKey == c.day, l.position == c.to {
                    l.position = l.dayStart
                    l.log[c.day] = nil
                } else {
                    continue
                }
                learning = l
                changed = true
            } else if c.kind == "revision", var r = revision, let k = known(q) {
                if c.done, r.log[c.day] == nil, c.to > c.from {
                    r.dayKey = c.day
                    r.dayCount = c.to - c.from
                    r.dayStart = c.from
                    r.dayTours = r.tours
                    r.position = c.to
                    if r.position >= k.count {
                        r.position = 0
                        r.tours += 1
                    }
                    r.log[c.day] = c.to - c.from
                } else if !c.done, r.log[c.day] != nil, r.dayKey == c.day {
                    r.position = r.dayStart
                    r.tours = r.dayTours
                    r.log[c.day] = nil
                } else {
                    continue
                }
                revision = r
                changed = true
            }
        }
        if changed {
            message = "Coché depuis le widget"
            save()
        }
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

    /// Le jour du prochain cours où tu récites (le jour même s'il n'a pas encore eu lieu).
    private func courseDay(_ now: Date) -> Date? {
        nextCourse(after: now).map { Day.start($0) }
    }

    /// Versets cochés entre deux jours (`from` inclus, `to` exclu), sans dépasser aujourd'hui.
    private func logged(_ l: Learning, from: Date, to: Date, now: Date) -> Int {
        var count = 0
        var d = Day.start(from)
        let last = Day.start(now)
        while d < to && d <= last {
            count += l.log[Day.key(d)] ?? 0
            d = Day.add(1, to: d)
        }
        return count
    }

    /// Ce que tu as appris pour le prochain cours (à y réciter) : depuis le jour du cours précédent.
    func learnedSinceCourse(_ q: QuranStore, now: Date = .now) -> [Int] {
        guard let l = learning, let day = courseDay(now) else { return [] }
        let count = logged(l, from: Day.add(-7, to: day), to: day, now: now)
        // Si le cours est aujourd'hui, ce que tu as appris aujourd'hui compte déjà pour le suivant.
        let after = logged(l, from: day, to: Day.add(1, to: Day.start(now)), now: now)
        let seq = q.sequence(l.direction)
        let end = max(0, min(l.position, seq.count) - after)
        return Array(seq[max(0, end - count)..<end])
    }

    /// Combien apprendre aujourd'hui pour tenir l'objectif avant le cours.
    /// Exemple : 3 pages, déjà 1,5 page faite, cours dans 3 jours → 0,5 page par jour.
    func coursePlan(_ q: QuranStore, now: Date = .now, using alt: Learning? = nil) -> CoursePlan? {
        guard let l = alt ?? learning, var end = courseDay(now) else { return nil }
        let today = Day.start(now)
        // Le jour du cours, ce que tu apprends compte pour le cours suivant.
        if end <= today { end = Day.add(7, to: end) }
        let start = Day.add(-7, to: end)
        let days = max(1, Day.between(today, end))
        // Ce qui est déjà appris pour ce cours, avant aujourd'hui.
        let count = logged(l, from: start, to: today, now: now)
        let seq = q.sequence(l.direction)
        let from = min(l.dayKey == Day.key(now) ? l.dayStart : l.position, seq.count)
        let done = q.pages(seq, max(0, from - count), from)
        return CoursePlan(daysLeft: days, goal: l.pagesPerWeek, done: done)
    }
}

// MARK: - Couleurs : noir et blanc

extension Color {
    /// Noir en thème clair, blanc en thème sombre.
    static let brand = Color.primary
    /// Le texte posé sur un fond `brand`.
    static let onBrand = Color(uiColor: .systemBackground)
}

// MARK: - Nombres

enum Num {
    /// « 1,5 » ou « 3 ».
    static func pages(_ v: Double) -> String {
        let r = (v * 2).rounded() / 2
        if r == 0 && v > 0 { return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }

    static func pagesLabel(_ v: Double) -> String {
        let t = pages(v)
        return t + (v > 1.25 ? " pages" : " page")
    }
}
