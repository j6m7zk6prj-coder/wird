import Foundation

// MARK: - Ce que l'app partage avec les widgets (via le groupe d'apps)

enum WirdShared {
    static let defaultGroup = "group.com.wird.app"
    static let key = "widget.snapshot"

    /// Le groupe partagé entre l'app et les widgets. Les outils d'installation (SideStore, AltStore…)
    /// renomment parfois le groupe : ils l'indiquent alors dans « ALTAppGroups ».
    static var group: String {
        let renamed = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        for g in renamed + [defaultGroup] where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) != nil {
            return g
        }
        return renamed.first ?? defaultGroup
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }
}

/// Un passage à faire : « Al-Mulk 1 → 6 » · « 6 versets · page 562 ».
struct WidgetPart: Codable, Hashable {
    var title: String
    var detail: String
    var done: Bool
}

/// Ce qu'il y a à faire un jour donné.
struct WidgetDay: Codable, Hashable {
    var key: String
    var learning: WidgetPart?
    var revision: WidgetPart?
    /// « Cours dans 3 j · ≈ 1 page par jour ».
    var plan: String?
}

/// Le cours de la semaine.
struct WidgetCourse: Codable, Hashable {
    var weekday: Int
    var hour: Int
    var minute: Int
    /// Objectif (pages) et pages déjà apprises pour le cours `forDate`.
    var goal: Double
    var done: Double
    var forDate: Date
    /// Ce qu'il faudra réciter au cours.
    var recite: String?
}

struct WidgetSnapshot: Codable {
    var updated = Date()
    var hasLearning = false
    var today: WidgetDay
    /// Le lendemain, calculé à l'avance pour que le widget change tout seul à minuit.
    var tomorrow: WidgetDay
    var course: WidgetCourse?
    /// Les jours où tu as coché quelque chose (« 2026-11-10 »).
    var activeDays: [String] = []

    static func load() -> WidgetSnapshot? {
        guard let data = WirdShared.defaults?.data(forKey: WirdShared.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            WirdShared.defaults?.set(data, forKey: WirdShared.key)
        }
    }

    /// Le bon jour à afficher pour une date (aujourd'hui, ou le lendemain après minuit).
    func day(for date: Date) -> WidgetDay {
        WirdCal.key(date) <= today.key ? today : tomorrow
    }

    /// Jours d'affilée avec au moins une case cochée.
    func streak(at date: Date) -> Int {
        let set = Set(activeDays)
        var d = WirdCal.start(date)
        if !set.contains(WirdCal.key(d)) { d = WirdCal.add(-1, to: d) }
        var n = 0
        while set.contains(WirdCal.key(d)) {
            n += 1
            d = WirdCal.add(-1, to: d)
        }
        return n
    }

    func isActive(_ date: Date) -> Bool { activeDays.contains(WirdCal.key(date)) }
}

// MARK: - Dates (mêmes règles que dans l'app)

enum WirdCal {
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
    static func add(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
    static func between(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: start(a), to: start(b)).day ?? 0
    }

    static func nextCourse(_ c: WidgetCourse, after date: Date) -> Date? {
        var comps = DateComponents()
        comps.weekday = c.weekday
        comps.hour = c.hour
        comps.minute = c.minute
        comps.second = 0
        return calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
    }

    /// « 1,5 » ou « 3 ».
    static func pages(_ v: Double) -> String {
        let r = (v * 2).rounded() / 2
        if r == 0 && v > 0 { return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
        return r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }
}
