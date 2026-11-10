import Foundation

// MARK: - Ce que l'app partage avec les widgets (via le groupe d'apps)

enum WirdShared {
    static let defaultGroup = "group.com.wird.app"

    /// Le groupe partagé entre l'app et les widgets.
    /// iLoader, SideStore et AltStore le renomment à l'installation (souvent « group.com.wird.app.ABCDE12345 ») :
    /// on cherche donc le vrai nom, d'abord dans le profil installé avec l'app, puis on essaie les noms probables.
    static let group: String? = findGroup()

    static var container: URL? {
        group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = container?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let url = container?.appendingPathComponent(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func findGroup() -> String? {
        var bundles = [Bundle.main]
        // Dans le widget : l'app qui le contient (Wird.app/PlugIns/WirdWidget.appex).
        if Bundle.main.bundleURL.pathExtension == "appex",
           let host = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) {
            bundles.append(host)
        }
        var names: [String] = []
        for b in bundles {
            names += provisionedGroups(b.bundleURL)
            names += b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        }
        let ids = bundles.compactMap { $0.bundleIdentifier }
        for id in ids {
            let app = id.hasSuffix(".widget") ? String(id.dropLast(".widget".count)) : id
            names.append("group." + app)
            for part in id.split(separator: ".") where part.count == 10 && part.allSatisfy({ $0.isUppercase || $0.isNumber }) {
                names.append(defaultGroup + "." + String(part))
            }
        }
        names.append(defaultGroup)
        for g in names where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) != nil {
            return g
        }
        return nil
    }

    /// Les groupes écrits dans le profil de l'app (embedded.mobileprovision).
    private static func provisionedGroups(_ bundle: URL) -> [String] {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("embedded.mobileprovision")),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound),
                                                                       options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
}

/// Un passage à faire : « Al-Mulk 1 → 7 », 7 versets, page 562.
struct WidgetPart: Codable, Hashable {
    var title: String
    var detail: String
    var done: Bool
    /// Nombre de versets.
    var count: Int
    /// Place du passage dans la suite (pour que l'app retrouve ce qui a été coché).
    var from: Int
    var to: Int
    /// « page 562 » ou « pages 562–563 ».
    var place: String
}

/// Ce qu'il y a à faire un jour donné.
struct WidgetDay: Codable, Hashable {
    var key: String
    var learning: WidgetPart?
    var revision: WidgetPart?
    /// « Cours dans 3 j · ≈ 1 page par jour ».
    var plan: String?
}

/// Un jour du planning à venir.
struct WidgetPlanDay: Codable, Hashable {
    var key: String
    var date: Date
    var title: String
    var count: Int
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

/// Une case cochée (ou décochée) sur un widget. L'app l'enregistre à sa prochaine ouverture.
struct WidgetCheck: Codable, Hashable {
    /// « learning » ou « revision ».
    var kind: String
    var day: String
    var from: Int
    var to: Int
    var done: Bool

    static let file = "widget-checks.json"
    static func all() -> [WidgetCheck] { WirdShared.read([WidgetCheck].self, file) ?? [] }
    static func save(_ list: [WidgetCheck]) { WirdShared.write(list, file) }
}

struct WidgetSnapshot: Codable {
    var updated = Date()
    var hasLearning = false
    var today: WidgetDay
    /// Le lendemain, calculé à l'avance pour que le widget change tout seul à minuit.
    var tomorrow: WidgetDay
    /// Le passage de demain si on coche (ou décoche) aujourd'hui depuis le widget.
    var tomorrowLearningAlt: WidgetPart?
    var tomorrowRevisionAlt: WidgetPart?
    /// Les prochains jours d'apprentissage (à partir de demain), si tu tiens le rythme.
    var week: [WidgetPlanDay] = []
    var course: WidgetCourse?
    /// Les jours où tu as coché quelque chose (« 2026-11-10 »).
    var activeDays: [String] = []

    static let file = "widget-snapshot.json"

    static func load() -> WidgetSnapshot? { WirdShared.read(WidgetSnapshot.self, file) }
    func save() { WirdShared.write(self, Self.file) }

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

    /// Coche ou décoche depuis un widget : le widget change tout de suite, l'app suit à sa prochaine ouverture.
    static func toggle(_ kind: String, at date: Date = .now) {
        guard var s = load() else { return }
        let learning = kind == "learning"
        let isToday = WirdCal.key(date) <= s.today.key
        var day = isToday ? s.today : s.tomorrow
        guard var part = learning ? day.learning : day.revision, part.count > 0 else { return }
        part.done.toggle()
        if learning { day.learning = part } else { day.revision = part }

        if isToday {
            s.today = day
            // Le passage de demain dépend de ce qui est fait aujourd'hui.
            if learning, let alt = s.tomorrowLearningAlt {
                s.tomorrowLearningAlt = s.tomorrow.learning
                s.tomorrow.learning = alt
            } else if !learning, let alt = s.tomorrowRevisionAlt {
                s.tomorrowRevisionAlt = s.tomorrow.revision
                s.tomorrow.revision = alt
            }
        } else {
            s.tomorrow = day
        }

        s.activeDays.removeAll { $0 == day.key }
        if day.learning?.done == true || day.revision?.done == true { s.activeDays.append(day.key) }
        s.save()

        var checks = WidgetCheck.all()
        if let i = checks.firstIndex(where: { $0.kind == kind && $0.day == day.key }) {
            // Coché puis décoché avant d'ouvrir l'app : rien à faire.
            checks.remove(at: i)
        } else {
            checks.append(WidgetCheck(kind: kind, day: day.key, from: part.from, to: part.to, done: part.done))
        }
        WidgetCheck.save(checks)
    }
}

// MARK: - Dates (mêmes règles que dans l'app)

enum WirdCal {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.firstWeekday = 2
        return c
    }

    static let fr = Locale(identifier: "fr_FR")

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
