import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Les widgets de Wird : prochain objectif, prochain cours, planning, série

@main
struct WirdWidgets: WidgetBundle {
    var body: some Widget {
        ObjectiveWidget()
        CourseWidget()
        PlanningWidget()
        ListenWidget()
        StreakWidget()
    }
}

// MARK: - Cocher depuis le widget

struct ToggleWirdIntent: AppIntent {
    static let title: LocalizedStringResource = "Cocher dans Wird"

    @Parameter(title: "Quoi")
    var kind: String

    init() {}

    init(kind: String) {
        self.kind = kind
    }

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.toggle(kind)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Données

struct WirdEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct WirdProvider: TimelineProvider {
    func placeholder(in context: Context) -> WirdEntry { WirdEntry(date: .now, snap: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (WirdEntry) -> Void) {
        let snap = WidgetSnapshot.load()
        completion(WirdEntry(date: .now, snap: snap ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WirdEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let now = Date()
        let midnight = WirdCal.add(1, to: WirdCal.start(now))
        var dates = [now]
        // Le jour du cours : le compte à rebours, puis le pourcentage repart à zéro juste après.
        if let c = snap?.course, let next = WirdCal.nextCourse(c, after: now), next < midnight {
            dates.append(next.addingTimeInterval(1))
        }
        // À minuit : le passage du lendemain.
        dates.append(midnight.addingTimeInterval(1))
        completion(Timeline(entries: dates.map { WirdEntry(date: $0, snap: snap) }, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let key = WirdCal.key(.now)
        let day = WidgetDay(
            key: key,
            learning: WidgetPart(title: "Al-Mulk 1 → 7", detail: "7 versets · page 562", done: false,
                                 count: 7, from: 0, to: 7, place: "page 562"),
            revision: WidgetPart(title: "An-Naba’ 1 → 30", detail: "30 versets · page 582", done: false,
                                 count: 30, from: 0, to: 30, place: "page 582"),
            plan: "Cours dans 3 j · ≈ 1 page/jour")
        var s = WidgetSnapshot(today: day, tomorrow: day)
        s.hasLearning = true
        s.course = WidgetCourse(weekday: 6, hour: 19, minute: 0, goal: 3, done: 1.5,
                                forDate: WirdCal.add(3, to: .now), recite: "Al-Mulk 1 → 15")
        s.activeDays = (1..<9).map { WirdCal.key(WirdCal.add(-$0, to: .now)) }
        let titles = ["Al-Mulk 8 → 14", "Al-Mulk 15 → 21", "Al-Mulk 22 → 30", "Al-Qalam 1 → 8", "Al-Qalam 9 → 16"]
        s.week = titles.enumerated().map { (i, t) -> WidgetPlanDay in
            let d = WirdCal.add(i + 1, to: .now)
            return WidgetPlanDay(key: WirdCal.key(d), date: d, title: t, count: 7)
        }
        return s
    }
}

// MARK: - Style (comme dans l'app : cartes sombres, petits titres en capitales)

private let bookmarkRed = Color(red: 0.84, green: 0.16, blue: 0.16)

extension View {
    fileprivate func wirdBackground() -> some View {
        containerBackground(for: .widget) { Color(.secondarySystemGroupedBackground) }
    }
}

/// « À APPRENDRE », « PROCHAIN COURS »…
private struct Caps: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Un grand nombre suivi de son unité : « 7 versets ».
private struct BigNumber: View {
    let value: String
    let unit: String
    var size: CGFloat = 44
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            Text(unit)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// La case à cocher (rond vide, ou rond plein avec une coche).
private struct CheckMark: View {
    let done: Bool
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Circle().fill(done ? Color.primary : Color.primary.opacity(0.06))
            Circle().strokeBorder(Color.primary.opacity(done ? 0 : 0.3), lineWidth: 2)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(done ? Color(.secondarySystemGroupedBackground) : Color.primary.opacity(0.3))
        }
        .frame(width: size, height: size)
    }
}

/// Bouton qui coche directement depuis l'écran d'accueil.
private struct CheckButton: View {
    let kind: String
    let done: Bool
    var size: CGFloat = 34
    var body: some View {
        Button(intent: ToggleWirdIntent(kind: kind)) {
            CheckMark(done: done, size: size)
        }
        .buttonStyle(.plain)
    }
}

/// Barre de progression.
private struct Bar: View {
    let value: Double
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.primary)
                    .frame(width: max(height, geo.size.width * max(0, min(1, value))))
            }
        }
        .frame(height: height)
    }
}

/// Le petit logo de Wird : un livre noir avec un « و » et un marque-page rouge.
private struct MiniLogo: View {
    var size: CGFloat = 20
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size * 0.08)
                .fill(bookmarkRed)
                .frame(width: size * 0.12, height: size * 0.5)
                .offset(x: size * 0.14, y: size * 0.62)
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(Color.primary)
                .frame(width: size * 0.7, height: size * 0.88)
                .overlay {
                    Text("و").font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Color(.secondarySystemGroupedBackground))
                }
        }
        .frame(width: size, height: size, alignment: .top)
    }
}

/// Quand le widget n'a rien à afficher.
private struct EmptyWird: View {
    var text = "Ouvre Wird une fois pour afficher ton programme ici."
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiniLogo(size: 24)
            Spacer(minLength: 0)
            Text(WirdShared.group == nil
                 ? "Le widget n’est pas relié à Wird. Réinstalle l’app avec iLoader."
                 : text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func versets(_ n: Int) -> String { n > 1 ? "versets" : "verset" }

private func courseWhen(_ days: Int, _ next: Date) -> String {
    let time = next.formatted(.dateTime.hour().minute().locale(WirdCal.fr))
    if days == 0 { return "aujourd’hui à \(time)" }
    if days == 1 { return "demain à \(time)" }
    return "dans \(days) jours"
}

// MARK: - 1. Prochain objectif

struct ObjectiveWidget: Widget {
    var body: some WidgetConfiguration {
        // Même identifiant que l'ancien « Passage du jour » : s'il est déjà posé, il est remplacé.
        StaticConfiguration(kind: "WirdToday", provider: WirdProvider()) { entry in
            ObjectiveWidgetView(entry: entry)
        }
        .configurationDisplayName("Prochain objectif")
        .description("Les versets à apprendre aujourd’hui. Coche-les directement ici.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ObjectiveWidgetView: View {
    let entry: WirdEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snap = entry.snap, snap.hasLearning {
                let day = snap.day(for: entry.date)
                let next = snap.week.first { $0.key > day.key }
                switch family {
                case .systemMedium: medium(day)
                case .accessoryCircular: circular(day)
                case .accessoryRectangular: rectangular(day)
                case .accessoryInline: inline(day)
                default: small(day, next)
                }
            } else if family == .accessoryInline {
                Text("Wird : ouvre l’app")
            } else if family == .accessoryCircular {
                Image(systemName: "book.closed")
            } else if family == .accessoryRectangular {
                Text("Ouvre Wird pour voir ton objectif").font(.caption)
            } else {
                EmptyWird()
            }
        }
        .wirdBackground()
    }

    private func small(_ day: WidgetDay, _ next: WidgetPlanDay?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Caps(day.learning?.done == true ? "Fait aujourd’hui" : "À apprendre")
                    .padding(.top, 4)
                Spacer(minLength: 4)
                if let p = day.learning { CheckButton(kind: "learning", done: p.done, size: 32) }
            }
            Spacer(minLength: 0)
            if let p = day.learning {
                if p.done {
                    Text("C’est fait !")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    if let next {
                        Text("Demain : \(next.count) \(versets(next.count))")
                            .font(.caption.weight(.semibold))
                        Text(next.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    BigNumber(value: "\(p.count)", unit: versets(p.count), size: 44)
                    Text(p.title.replacingOccurrences(of: "\n", with: " · "))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text(p.place).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Tout est appris, machAllah !").font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ day: WidgetDay) -> some View {
        HStack(spacing: 14) {
            row("À apprendre", "learning", day.learning, empty: "Tout est appris")
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            row("À réviser", "revision", day.revision, empty: "Rien à réviser")
        }
    }

    private func row(_ title: String, _ kind: String, _ p: WidgetPart?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Caps(title).padding(.top, 4)
                Spacer(minLength: 4)
                if let p { CheckButton(kind: kind, done: p.done, size: 30) }
            }
            Spacer(minLength: 0)
            if let p {
                BigNumber(value: "\(p.count)", unit: versets(p.count), size: 34)
                    .opacity(p.done ? 0.4 : 1)
                Text(p.title.replacingOccurrences(of: "\n", with: " · "))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .strikethrough(p.done, color: .secondary)
                Text(p.place).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(empty).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func circular(_ day: WidgetDay) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            if let p = day.learning, !p.done {
                VStack(spacing: -2) {
                    Text("\(p.count)").font(.system(.title2, design: .rounded).weight(.bold))
                    Text("vers.").font(.system(size: 9, weight: .semibold))
                }
            } else {
                Image(systemName: "checkmark").font(.title3.weight(.bold))
            }
        }
        .widgetAccentable()
    }

    private func rectangular(_ day: WidgetDay) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: day.learning?.done == true ? "checkmark.circle.fill" : "book.closed")
                Text(day.learning?.done == true ? "Fait aujourd’hui" : "À apprendre")
            }
            .font(.caption2.weight(.semibold))
            if let p = day.learning {
                Text("\(p.count) \(versets(p.count))").font(.headline)
                Text(p.title.replacingOccurrences(of: "\n", with: " · ")).font(.caption2).lineLimit(1)
            } else {
                Text("Tout est appris").font(.headline)
            }
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ day: WidgetDay) -> some View {
        if let p = day.learning {
            return Text((p.done ? "✓ " : "") + "\(p.count) \(versets(p.count)) · " + p.title.replacingOccurrences(of: "\n", with: " · "))
        }
        return Text("Wird : tout est appris")
    }
}

// MARK: - 2. Prochain cours

struct CourseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WirdCourse", provider: WirdProvider()) { entry in
            CourseWidgetView(entry: entry)
        }
        .configurationDisplayName("Prochain cours")
        .description("Dans combien de temps est ton cours, et où tu en es de ton objectif.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CourseWidgetView: View {
    let entry: WirdEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let c = entry.snap?.course, let next = WirdCal.nextCourse(c, after: entry.date) {
                content(c, next)
            } else if family == .accessoryInline {
                Text("Wird : règle ton cours")
            } else if family == .accessoryCircular {
                Image(systemName: "person.2")
            } else if family == .accessoryRectangular {
                Text("Règle ton cours dans Wird").font(.caption)
            } else {
                EmptyWird(text: entry.snap == nil
                          ? "Ouvre Wird une fois pour voir ton prochain cours."
                          : "Règle ton cours dans l’onglet Cours de Wird.")
            }
        }
        .wirdBackground()
    }

    @ViewBuilder private func content(_ c: WidgetCourse, _ next: Date) -> some View {
        // Après le cours, ce qui a été appris compte pour le suivant.
        let done = entry.date >= c.forDate ? 0 : c.done
        let share = c.goal > 0 ? min(1, done / c.goal) : 0
        let days = WirdCal.between(entry.date, next)
        switch family {
        case .accessoryCircular:
            Gauge(value: share) {
                Image(systemName: "person.2")
            } currentValueLabel: {
                Text(days == 0 ? "Auj." : "\(days) j")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryInline:
            Text("Cours \(courseWhen(days, next))")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Prochain cours").font(.caption2.weight(.semibold))
                countdown(days, next, size: 17)
                Gauge(value: share) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
            .widgetAccentable()
        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Caps("Prochain cours")
                    Spacer(minLength: 0)
                    countdown(days, next, size: 44)
                    Text(next, format: .dateTime.weekday(.wide).hour().minute().locale(WirdCal.fr))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Caps("À réciter")
                    Text(c.recite ?? "Rien encore")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(3).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    goal(done, c.goal, share)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Caps("Prochain cours")
                Spacer(minLength: 0)
                countdown(days, next, size: 44)
                Text(next, format: .dateTime.weekday(.wide).hour().minute().locale(WirdCal.fr))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                goal(done, c.goal, share)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// Le jour même : un minuteur qui défile. Sinon « 3 jours » ou « Demain ».
    @ViewBuilder private func countdown(_ days: Int, _ next: Date, size: CGFloat) -> some View {
        if days == 0 {
            Text(timerInterval: entry.date...next, countsDown: true)
                .font(.system(size: size * 0.7, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
        } else if days == 1 {
            BigNumber(value: "Demain", unit: next.formatted(.dateTime.hour().minute().locale(WirdCal.fr)), size: size * 0.7)
        } else {
            BigNumber(value: "\(days)", unit: "jours", size: size)
        }
    }

    private func goal(_ done: Double, _ goal: Double, _ share: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Bar(value: share)
            Text("\(WirdCal.pages(done)) / \(WirdCal.pages(goal)) pages")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 3. Planning (grand widget)

struct PlanningWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WirdPlanning", provider: WirdProvider()) { entry in
            PlanningWidgetView(entry: entry)
        }
        .configurationDisplayName("Planning")
        .description("Ton prochain objectif à cocher, ta révision, les jours à venir et ton cours.")
        .supportedFamilies([.systemLarge])
    }
}

struct PlanningWidgetView: View {
    let entry: WirdEntry

    var body: some View {
        Group {
            if let snap = entry.snap, snap.hasLearning {
                content(snap)
            } else {
                EmptyWird()
            }
        }
        .wirdBackground()
    }

    private func content(_ snap: WidgetSnapshot) -> some View {
        let day = snap.day(for: entry.date)
        let streak = snap.streak(at: entry.date)
        let upcoming = Array(snap.week.filter { $0.key > day.key }.prefix(day.revision == nil ? 5 : 4))
        return VStack(alignment: .leading, spacing: 10) {
            // En-tête
            HStack(spacing: 8) {
                MiniLogo(size: 20)
                Text("Planning").font(.system(.headline, design: .rounded))
                Spacer()
                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").foregroundStyle(bookmarkRed)
                        Text("\(streak)").monospacedDigit()
                    }
                    .font(.subheadline.weight(.bold))
                }
            }

            // Le prochain objectif, à cocher
            if let p = day.learning {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Caps(p.done ? "Fait aujourd’hui" : "Prochain objectif")
                        BigNumber(value: "\(p.count)", unit: versets(p.count), size: 40)
                            .opacity(p.done ? 0.4 : 1)
                        Text(p.title.replacingOccurrences(of: "\n", with: " · "))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .strikethrough(p.done, color: .secondary)
                        Text(day.plan.map { p.place + " · " + $0 } ?? p.place)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    CheckButton(kind: "learning", done: p.done, size: 50)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.06)))
            } else {
                Text("Tout est appris, machAllah !").font(.headline)
            }

            // La révision du jour
            if let r = day.revision {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Caps("Révision")
                        Text(r.title.replacingOccurrences(of: "\n", with: " · ") + " · \(r.count) v.")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .strikethrough(r.done, color: .secondary)
                    }
                    Spacer(minLength: 0)
                    CheckButton(kind: "revision", done: r.done, size: 30)
                }
                .padding(.horizontal, 12)
            }

            // Les jours à venir
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Caps("À venir")
                    ForEach(upcoming, id: \.key) { d in
                        planRow(d, isCourse: isCourseDay(d.date, snap.course))
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer(minLength: 0)

            // Le cours
            if let c = snap.course, let next = WirdCal.nextCourse(c, after: entry.date) {
                let done = entry.date >= c.forDate ? 0 : c.done
                let share = c.goal > 0 ? min(1, done / c.goal) : 0
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Cours \(courseWhen(WirdCal.between(entry.date, next), next))")
                        Spacer()
                        Text("\(WirdCal.pages(done)) / \(WirdCal.pages(c.goal)) pages").foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))
                    Bar(value: share, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func planRow(_ d: WidgetPlanDay, isCourse: Bool) -> some View {
        HStack(spacing: 8) {
            Text(d.date.formatted(.dateTime.weekday(.abbreviated).locale(WirdCal.fr)).capitalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(d.title).font(.footnote).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if isCourse {
                Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.secondary)
            }
            Text("\(d.count) v.").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func isCourseDay(_ date: Date, _ c: WidgetCourse?) -> Bool {
        guard let c else { return false }
        return WirdCal.calendar.component(.weekday, from: date) == c.weekday
    }
}

// MARK: - 4. Série

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WirdStreak", provider: WirdProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Ma série")
        .description("Les jours d’affilée où tu as fait ton wird, et ta semaine.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct StreakWidgetView: View {
    let entry: WirdEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snap = entry.snap {
                let n = snap.streak(at: entry.date)
                if family == .accessoryCircular {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 0) {
                            Image(systemName: "flame.fill").font(.caption)
                            Text("\(n)").font(.system(.title3, design: .rounded).weight(.bold))
                        }
                    }
                    .widgetAccentable()
                } else {
                    small(snap, n)
                }
            } else {
                EmptyWird(text: "Ouvre Wird une fois pour voir ta série.")
            }
        }
        .wirdBackground()
    }

    private func small(_ snap: WidgetSnapshot, _ n: Int) -> some View {
        let days = (0..<7).reversed().map { WirdCal.add(-$0, to: WirdCal.start(entry.date)) }
        let letters = ["D", "L", "M", "M", "J", "V", "S"]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Caps("Ma série")
                Spacer()
                Image(systemName: "flame.fill").foregroundStyle(n > 0 ? bookmarkRed : .secondary)
            }
            Spacer(minLength: 0)
            BigNumber(value: "\(n)", unit: n > 1 ? "jours" : "jour", size: 44)
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let wd = WirdCal.calendar.component(.weekday, from: d)
                    VStack(spacing: 3) {
                        Circle()
                            .fill(snap.isActive(d) ? Color.primary : Color.primary.opacity(0.12))
                            .frame(width: 11, height: 11)
                        Text(letters[wd - 1]).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - 5. Reprendre l'écoute

struct ListenEntry: TimelineEntry {
    let date: Date
    let snap: ListenSnapshot?
    let artwork: UIImage?
}

struct ListenProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListenEntry { ListenEntry(date: .now, snap: .sample, artwork: nil) }

    func getSnapshot(in context: Context, completion: @escaping (ListenEntry) -> Void) {
        completion(entry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ListenEntry>) -> Void) {
        let e = entry(preview: false)
        // Pendant la lecture : on se remet à jour à la fin du morceau.
        if let s = e.snap, s.isPlaying, s.duration > 0 {
            let end = s.updated.addingTimeInterval(max(1, s.duration - s.position) + 1)
            completion(Timeline(entries: [e], policy: .after(end)))
        } else {
            completion(Timeline(entries: [e], policy: .never))
        }
    }

    private func entry(preview: Bool) -> ListenEntry {
        let snap = ListenSnapshot.load()
        let art = snap == nil ? nil : ListenSnapshot.artworkData().flatMap { UIImage(data: $0) }
        return ListenEntry(date: .now, snap: snap ?? (preview ? .sample : nil), artwork: art)
    }
}

extension ListenSnapshot {
    static var sample: ListenSnapshot {
        ListenSnapshot(trackID: "", title: "Sourate Al-Mulk", artist: "Mishary Alafasy", album: "",
                       position: 95, duration: 410, isPlaying: false, updated: .now, queue: [])
    }
}

struct ListenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ListenSnapshot.kind, provider: ListenProvider()) { entry in
            ListenWidgetView(entry: entry)
        }
        .configurationDisplayName("Reprendre l’écoute")
        .description("Le dernier morceau écouté : reprends-le là où tu t’étais arrêté.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ListenWidgetView: View {
    let entry: ListenEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snap {
                switch family {
                case .systemMedium: medium(s)
                case .accessoryCircular: circular(s)
                case .accessoryRectangular: rectangular(s)
                case .accessoryInline: Label(s.title, systemImage: s.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                default: small(s)
                }
            } else if family == .accessoryInline {
                Text("Wird : rien en écoute")
            } else if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "headphones")
                }
            } else if family == .accessoryRectangular {
                Text("Lance un morceau dans Wird").font(.caption)
            } else {
                EmptyWird(text: "Lance un morceau dans l’onglet Écouter de Wird pour le reprendre ici.")
            }
        }
        .widgetURL(URL(string: "wird://listen"))
        .wirdBackground()
    }

    private func label(_ s: ListenSnapshot) -> String { s.isPlaying ? "En lecture" : "Reprendre" }

    private func artwork(_ side: CGFloat, corner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.primary.opacity(0.08))
            if let img = entry.artwork {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.36, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private func playButton(_ s: ListenSnapshot, size: CGFloat) -> some View {
        Button(intent: ToggleListeningIntent()) {
            ZStack {
                Circle().fill(Color.primary)
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color(.secondarySystemGroupedBackground))
                    .offset(x: s.isPlaying ? 0 : size * 0.04)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.isPlaying ? "Pause" : "Lecture")
    }

    /// La barre de lecture : elle avance toute seule pendant la lecture.
    @ViewBuilder private func progress(_ s: ListenSnapshot) -> some View {
        if s.isPlaying, s.duration > 1 {
            let start = s.updated.addingTimeInterval(-s.position)
            let end = start.addingTimeInterval(max(s.duration, s.position + 1))
            ProgressView(timerInterval: start...end, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.linear)
                .tint(.primary)
        } else {
            Bar(value: s.duration > 0 ? s.position / s.duration : 0, height: 4)
        }
    }

    private func time(_ v: Double) -> String {
        let t = Int(max(0, v.isFinite ? v : 0))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func small(_ s: ListenSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                artwork(58, corner: 10)
                Spacer(minLength: 4)
                playButton(s, size: 40)
            }
            Spacer(minLength: 0)
            Caps(label(s))
            Text(s.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(s.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, 6)
            progress(s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: ListenSnapshot) -> some View {
        HStack(spacing: 14) {
            artwork(122, corner: 14)
            VStack(alignment: .leading, spacing: 2) {
                Caps(label(s))
                Text(s.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(s.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                progress(s)
                if !s.isPlaying {
                    HStack {
                        Text(time(s.position))
                        Spacer()
                        Text("-" + time(s.duration - s.position))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    playButton(s, size: 38)
                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suivant")
                    .disabled(!s.isPlaying)
                    .opacity(s.isPlaying ? 1 : 0.35)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func circular(_ s: ListenSnapshot) -> some View {
        Button(intent: ToggleListeningIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }

    private func rectangular(_ s: ListenSnapshot) -> some View {
        HStack(spacing: 8) {
            Button(intent: ToggleListeningIntent()) {
                Image(systemName: s.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(label(s)).font(.caption2.weight(.semibold))
                Text(s.title).font(.headline).lineLimit(1)
                Text(s.artist).font(.caption2).lineLimit(1)
            }
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
