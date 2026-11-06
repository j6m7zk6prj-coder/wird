import SwiftUI

// MARK: - Les objectifs (apprendre, réviser, lire) et leur calcul jour par jour

enum PlanKind: String, Codable, CaseIterable, Identifiable {
    case memorize, review, read
    var id: String { rawValue }

    var label: String {
        switch self {
        case .memorize: return "Apprendre"
        case .review: return "Réviser"
        case .read: return "Lire"
        }
    }

    var symbol: String {
        switch self {
        case .memorize: return "brain.head.profile"
        case .review: return "arrow.triangle.2.circlepath"
        case .read: return "book"
        }
    }

    var color: Color {
        switch self {
        case .memorize: return .brand
        case .review: return .brand
        case .read: return .brand
        }
    }

    /// « C'est appris », « C'est révisé », « C'est lu ».
    var doneLabel: String {
        switch self {
        case .memorize: return "C’est appris"
        case .review: return "C’est révisé"
        case .read: return "C’est lu"
        }
    }
}

enum PlanUnit: String, Codable, CaseIterable, Identifiable {
    case ayahs, pages, rub, nisf, hizb, juz
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ayahs: return "Versets"
        case .pages: return "Pages"
        case .rub: return "Rub‘"
        case .nisf: return "Nisf"
        case .hizb: return "Hizb"
        case .juz: return "Juz"
        }
    }

    /// Explication courte : « ¼ de hizb ».
    var hint: String {
        switch self {
        case .ayahs: return "un par un"
        case .pages: return "du Mushaf"
        case .rub: return "¼ de hizb"
        case .nisf: return "½ hizb"
        case .hizb: return "½ juz"
        case .juz: return "1/30 du Coran"
        }
    }

    func count(_ n: Int) -> String {
        switch self {
        case .ayahs: return "\(n) verset\(n > 1 ? "s" : "")"
        case .pages: return "\(n) page\(n > 1 ? "s" : "")"
        case .rub: return "\(n) rub‘"
        case .nisf: return "\(n) nisf"
        case .hizb: return "\(n) hizb"
        case .juz: return "\(n) juz"
        }
    }

    /// Le maximum raisonnable par jour.
    var maxPerDay: Int {
        switch self {
        case .ayahs: return 300
        case .pages: return 40
        case .rub: return 40
        case .nisf: return 20
        case .hizb: return 20
        case .juz: return 10
        }
    }
}

enum PlanMode: String, Codable {
    /// « Je veux finir avant le … » : l'app calcule combien faire par jour.
    case deadline
    /// « Je fais tant par jour » : l'app calcule la date de fin.
    case pace
}

struct Plan: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: PlanKind
    var title: String
    /// Les versets à faire, dans l'ordre (numéros globaux 0…6235).
    var segments: [ClosedRange<Int>]
    var unit: PlanUnit = .ayahs
    var mode: PlanMode = .deadline
    var deadline = Date()
    var pace = 5
    /// Jours de repos (1 = dimanche … 7 = samedi).
    var restDays: [Int] = []
    /// Révision : on recommence au début une fois fini.
    var repeats = false
    var cycleDays = 30
    var cycles = 0

    /// Où tu en es : combien de versets de la liste sont faits.
    var position = 0
    var dayKey = ""
    var dayStart = 0
    var restartKey = ""
    /// Versets faits chaque jour (« 2026-11-06 » → 5).
    var log: [String: Int] = [:]
    var created = Date()
    var initialPerDay = 0

    var sequence: [Int] { segments.flatMap { Array($0) } }
    var total: Int { segments.reduce(0) { $0 + $1.count } }
    var progress: Double { total == 0 ? 0 : Double(min(position, total)) / Double(total) }
}

/// Ce qu'il y a à faire aujourd'hui pour un objectif.
struct DayTask {
    var from: Int
    var to: Int
    var perDay: Int
    var done: Bool
    var rest: Bool
    var finished: Bool
    var remaining: Int
    var studyDays: Int
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

    static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func weekday(_ date: Date) -> Int { calendar.component(.weekday, from: date) }
    static func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func add(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }

    /// Les jours de la semaine dans l'ordre français (lundi d'abord).
    static let week: [(Int, String)] = [(2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")]
}

@MainActor
extension Plan {
    /// Nombre d'unités (versets, pages, rub‘, hizb…) entre deux positions de la liste.
    func units(_ seq: [Int], from a: Int, to b: Int, _ q: QuranStore) -> Int {
        guard b > a else { return 0 }
        if unit == .ayahs { return b - a }
        var n = 0, last = -1
        for i in a..<min(b, seq.count) {
            let blk = q.block(seq[i], unit)
            if blk != last { n += 1; last = blk }
        }
        return n
    }

    /// Avance de `n` unités à partir de la position `a`.
    func advance(_ seq: [Int], from a: Int, by n: Int, _ q: QuranStore) -> Int {
        guard n > 0 else { return a }
        if unit == .ayahs { return min(seq.count, a + n) }
        var count = 0, last = -1, i = a
        while i < seq.count {
            let blk = q.block(seq[i], unit)
            if blk != last {
                if count == n { break }
                count += 1
                last = blk
            }
            i += 1
        }
        return i
    }

    /// Jours de travail entre deux dates (incluses), sans les jours de repos.
    func studyDays(from: Date, to: Date) -> Int {
        var d = Day.start(from), n = 0
        let end = Day.start(to)
        var guardCount = 0
        while d <= end, guardCount < 4000 {
            if !restDays.contains(Day.weekday(d)) { n += 1 }
            d = Day.add(1, to: d)
            guardCount += 1
        }
        return max(1, n)
    }

    func task(_ q: QuranStore, now: Date = .now) -> DayTask {
        let seq = sequence
        let key = Day.key(now)
        let start = dayKey == key ? dayStart : position
        let remaining = units(seq, from: start, to: seq.count, q)
        let days = studyDays(from: now, to: deadline)
        let perDay: Int
        switch mode {
        case .deadline: perDay = max(1, Int((Double(remaining) / Double(days)).rounded(.up)))
        case .pace: perDay = max(1, pace)
        }
        let rest = restDays.contains(Day.weekday(now))
        let target = rest ? start : advance(seq, from: start, by: perDay, q)
        let finished = !repeats && start >= seq.count
        let done = restartKey == key || (!rest && position >= target && (log[key] ?? 0) > 0) || (finished && (log[key] ?? 0) > 0)
        return DayTask(from: start, to: target, perDay: perDay, done: done, rest: rest, finished: finished,
                       remaining: remaining, studyDays: days)
    }

    /// Date de fin : la date choisie, ou celle calculée avec ton rythme.
    func finishDate(_ q: QuranStore, now: Date = .now) -> Date {
        if mode == .deadline { return deadline }
        let seq = sequence
        let key = Day.key(now)
        let start = dayKey == key ? dayStart : position
        var left = units(seq, from: start, to: seq.count, q)
        var d = Day.start(now)
        var guardCount = 0
        while left > 0, guardCount < 20000 {
            if !restDays.contains(Day.weekday(d)) { left -= max(1, pace) }
            if left > 0 { d = Day.add(1, to: d) }
            guardCount += 1
        }
        return d
    }

    /// Marque la tâche du jour (ou une partie) comme faite. Renvoie les versets faits.
    mutating func complete(_ q: QuranStore, upTo target: Int? = nil, now: Date = .now) -> [Int] {
        let seq = sequence
        let key = Day.key(now)
        if dayKey != key { dayKey = key; dayStart = position }
        let t = task(q, now: now)
        var end = min(seq.count, target ?? max(t.to, position))
        if t.rest && target == nil { end = advance(seq, from: position, by: t.perDay, q) }
        guard end > position else { return [] }
        let done = Array(seq[position..<end])
        log[key, default: 0] += done.count
        position = end
        if repeats, position >= seq.count {
            position = 0
            dayStart = 0
            cycles += 1
            restartKey = key
            if mode == .deadline { deadline = Day.add(max(1, cycleDays) - 1, to: Day.start(Day.add(1, to: now))) }
        }
        return done
    }

    mutating func undoToday(now: Date = .now) {
        let key = Day.key(now)
        guard dayKey == key else { return }
        if restartKey == key { restartKey = ""; cycles = max(0, cycles - 1) }
        position = dayStart
        log[key] = nil
    }
}

// MARK: - La mémoire de chaque page (révision espacée)

enum Strength: Int {
    case none, partial, solid, soon, weak

    var color: Color {
        switch self {
        case .none: return Color.primary.opacity(0.05)
        case .partial: return Color.primary.opacity(0.14)
        case .solid: return Color.primary
        case .soon: return Color.primary.opacity(0.55)
        case .weak: return Color.primary.opacity(0.3)
        }
    }

    var label: String {
        switch self {
        case .none: return "Pas encore apprise"
        case .partial: return "En cours"
        case .solid: return "Solide"
        case .soon: return "À revoir"
        case .weak: return "Fragile"
        }
    }
}

enum Grade: Int, CaseIterable, Identifiable {
    case hard, ok, easy
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .hard: return "Difficile"
        case .ok: return "Moyen"
        case .easy: return "Facile"
        }
    }
    var symbol: String {
        switch self {
        case .hard: return "tortoise.fill"
        case .ok: return "hand.thumbsup.fill"
        case .easy: return "bolt.fill"
        }
    }
    var color: Color {
        switch self {
        case .hard: return .brand
        case .ok: return .brand
        case .easy: return .brand
        }
    }
}

struct PageMemory: Codable, Hashable {
    var learned: Date
    var last: Date
    /// Nombre de jours avant la prochaine révision.
    var interval: Double
    var reviewedKey = ""
    var reviews = 0

    func ratio(_ now: Date = .now) -> Double {
        now.timeIntervalSince(last) / 86_400 / max(0.5, interval)
    }

    func nextReview() -> Date { last.addingTimeInterval(interval * 86_400) }
}

struct DayActivity: Codable, Hashable {
    var learned = 0
    var reviewed = 0
    var read = 0
    var total: Int { learned + reviewed + read }
}

// MARK: - Le carnet : tout ce que tu fais, enregistré sur l'iPhone

@MainActor
@Observable
final class Tracker {
    private(set) var plans: [Plan] = []
    private(set) var known: Set<Int> = []
    private(set) var memory: [Int: PageMemory] = [:]
    private(set) var activity: [String: DayActivity] = [:]
    var message: String?

    private struct SaveFile: Codable {
        var plans: [Plan]
        var known: [Int]
        var memory: [Int: PageMemory]
        var activity: [String: DayActivity]
    }

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wird", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("carnet.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.fileURL), let f = try? JSONDecoder().decode(SaveFile.self, from: data) {
            plans = f.plans
            known = Set(f.known)
            memory = f.memory
            activity = f.activity
        }
    }

    private func save() {
        let f = SaveFile(plans: plans, known: known.sorted(), memory: memory, activity: activity)
        if let data = try? JSONEncoder().encode(f) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    // MARK: Objectifs

    func add(_ plan: Plan, _ q: QuranStore) {
        var p = plan
        p.initialPerDay = p.task(q).perDay
        p.dayKey = ""
        plans.append(p)
        message = "Objectif créé"
        save()
    }

    func update(_ plan: Plan) {
        guard let i = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[i] = plan
        save()
    }

    func delete(_ id: UUID) {
        plans.removeAll { $0.id == id }
        save()
    }

    func plan(_ id: UUID) -> Plan? { plans.first { $0.id == id } }

    /// La tâche du jour est faite (ou une partie, jusqu'à `target`).
    func complete(_ id: UUID, _ q: QuranStore, upTo target: Int? = nil) {
        guard let i = plans.firstIndex(where: { $0.id == id }) else { return }
        let done = plans[i].complete(q, upTo: target)
        let key = Day.key(.now)
        switch plans[i].kind {
        case .memorize:
            learn(done, q)
            activity[key, default: DayActivity()].learned += done.count
        case .review:
            let pages = q.pages(of: done)
            for p in pages { grade(p, .ok, save: false) }
            activity[key, default: DayActivity()].reviewed += pages.count
        case .read:
            activity[key, default: DayActivity()].read += done.count
        }
        if plans[i].cycles > 0, plans[i].restartKey == key {
            message = "Tour complet terminé, bravo !"
        } else if plans[i].position >= plans[i].total {
            message = "Objectif terminé, machAllah !"
        } else {
            message = "Bien joué, c’est noté"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        save()
    }

    func undo(_ id: UUID) {
        guard let i = plans.firstIndex(where: { $0.id == id }) else { return }
        let key = Day.key(.now)
        let count = plans[i].log[key] ?? 0
        plans[i].undoToday()
        if plans[i].kind == .memorize { activity[key]?.learned = max(0, (activity[key]?.learned ?? 0) - count) }
        if plans[i].kind == .read { activity[key]?.read = max(0, (activity[key]?.read ?? 0) - count) }
        save()
    }

    // MARK: Mémoire

    /// Ces versets sont appris : les pages qu'ils touchent entrent dans la révision.
    func learn(_ ayat: [Int], _ q: QuranStore, date: Date = .now, interval: Double = 1) {
        for g in ayat {
            known.insert(g)
            let p = q.page(g)
            if memory[p] == nil {
                memory[p] = PageMemory(learned: date, last: date, interval: interval)
            }
        }
    }

    /// « Je connais déjà » : marque des versets comme appris (il y a un moment).
    func markKnown(_ range: Range<Int>, _ q: QuranStore) {
        let past = Day.add(-30, to: .now)
        for g in range {
            known.insert(g)
            let p = q.page(g)
            if memory[p] == nil {
                // Révisions étalées : toutes les pages ne reviennent pas le même jour.
                memory[p] = PageMemory(learned: past, last: Day.add(-(p % 7), to: .now), interval: Double(4 + p % 9))
            }
        }
        save()
    }

    func forget(_ range: Range<Int>, _ q: QuranStore) {
        for g in range { known.remove(g) }
        for p in Set(range.map { q.page($0) }) where !q.pageRange(p).contains(where: { known.contains($0) }) {
            memory[p] = nil
        }
        save()
    }

    func grade(_ page: Int, _ g: Grade, save shouldSave: Bool = true) {
        guard var m = memory[page] else { return }
        let key = Day.key(.now)
        switch g {
        case .easy: m.interval = max(3, m.interval * 2.5)
        case .ok: m.interval = max(2, m.interval * 1.6)
        case .hard: m.interval = 1
        }
        m.interval = min(m.interval, 90)
        m.last = .now
        if m.reviewedKey != key {
            m.reviews += 1
            if shouldSave { activity[key, default: DayActivity()].reviewed += 1 }
        }
        m.reviewedKey = key
        memory[page] = m
        if shouldSave { save() }
    }

    func reviewedToday(_ page: Int) -> Bool { memory[page]?.reviewedKey == Day.key(.now) }

    func knownCount(in range: Range<Int>) -> Int { range.reduce(0) { $0 + (known.contains($1) ? 1 : 0) } }

    func strength(_ page: Int, _ q: QuranStore) -> Strength {
        guard let m = memory[page] else { return .none }
        let r = q.pageRange(page)
        if r.contains(where: { !known.contains($0) }) { return .partial }
        let ratio = m.ratio()
        if ratio < 1 { return .solid }
        if ratio < 2 { return .soon }
        return .weak
    }

    /// Pages apprises ces 7 derniers jours (révision récente).
    func recentPages() -> [Int] {
        let limit = Day.add(-7, to: Day.start(.now))
        let today = Day.key(.now)
        return memory.filter { $0.value.learned >= limit && Day.key($0.value.learned) != today }.keys.sorted()
    }

    /// Pages anciennes à revoir aujourd'hui, les plus fragiles d'abord.
    func oldPages(limit: Int) -> [Int] {
        let recentLimit = Day.add(-7, to: Day.start(.now))
        let old = memory.filter { $0.value.learned < recentLimit }
        let doneToday = old.filter { reviewedToday($0.key) }.keys.sorted()
        let due = old.filter { !reviewedToday($0.key) && $0.value.ratio() >= 1 }
            .sorted { $0.value.ratio() > $1.value.ratio() }
            .map(\.key)
        return doneToday + due.prefix(max(0, limit - doneToday.count))
    }

    // MARK: Statistiques

    func learnedPages(_ q: QuranStore) -> Int {
        (1...604).filter { p in
            let r = q.pageRange(p)
            return !r.isEmpty && r.allSatisfy { known.contains($0) }
        }.count
    }

    func completeHizb(_ q: QuranStore) -> Int {
        (1...60).filter { h in q.hizbRange(h).allSatisfy { known.contains($0) } }.count
    }

    func completeJuz(_ q: QuranStore) -> Int {
        (1...30).filter { j in q.juzRange(j).allSatisfy { known.contains($0) } }.count
    }

    func completeSurahs(_ q: QuranStore) -> Int {
        (1...114).filter { s in q.surahRange(s).allSatisfy { known.contains($0) } }.count
    }

    /// Jours d'affilée avec au moins une chose faite.
    var streak: Int {
        var d = Day.start(.now)
        if (activity[Day.key(d)]?.total ?? 0) == 0 { d = Day.add(-1, to: d) }
        var n = 0
        while (activity[Day.key(d)]?.total ?? 0) > 0 {
            n += 1
            d = Day.add(-1, to: d)
        }
        return n
    }

    var bestStreak: Int {
        let days = activity.filter { $0.value.total > 0 }.keys.compactMap(Day.date).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, Day.add(1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        return best
    }

    func resetAll() {
        plans = []
        known = []
        memory = [:]
        activity = [:]
        save()
    }
}

extension Color {
    /// Wird est en noir et blanc : noir en thème clair, blanc en thème sombre.
    static let brand = Color.primary
    static let gold = Color.secondary
    /// Le texte posé sur un fond `brand` (blanc en clair, noir en sombre).
    static let onBrand = Color(uiColor: .systemBackground)
}
