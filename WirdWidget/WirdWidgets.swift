import SwiftUI
import UIKit
import WidgetKit

// MARK: - Les widgets de Wird : passage du jour, prochain cours, série

@main
struct WirdWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        CourseWidget()
        StreakWidget()
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
        // Juste après le cours : le pourcentage repart à zéro.
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
            learning: WidgetPart(title: "Al-Mulk 1 → 6", detail: "6 versets · page 562", done: false),
            revision: WidgetPart(title: "An-Naba’ 1 → 30", detail: "30 versets · page 582", done: true),
            plan: "Cours dans 3 j · ≈ 1 page/jour")
        var s = WidgetSnapshot(today: day, tomorrow: day)
        s.hasLearning = true
        s.course = WidgetCourse(weekday: 6, hour: 19, minute: 0, goal: 3, done: 1.5,
                                forDate: WirdCal.add(3, to: .now), recite: "Al-Mulk 1 → 15")
        s.activeDays = (0..<9).map { WirdCal.key(WirdCal.add(-$0, to: .now)) }
        return s
    }
}

// MARK: - Style

private let bookmarkRed = Color(red: 0.84, green: 0.16, blue: 0.16)

private struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

extension View {
    fileprivate func wirdBackground() -> some View { modifier(WidgetBackground()) }
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
                        .foregroundStyle(Color(.systemBackground))
                }
        }
        .frame(width: size, height: size, alignment: .top)
    }
}

/// Message quand l'app n'a encore rien partagé.
private struct OpenWird: View {
    var text = "Ouvre Wird une fois pour afficher ton passage ici."
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiniLogo(size: 26)
            Spacer(minLength: 0)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Anneau de progression.
private struct Ring: View {
    let value: Double
    var width: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: width)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - 1. Passage du jour

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WirdToday", provider: WirdProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Passage du jour")
        .description("Ce que tu dois apprendre et réviser aujourd’hui dans ton Mushaf.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: WirdEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snap = entry.snap, snap.hasLearning {
                let day = snap.day(for: entry.date)
                switch family {
                case .systemMedium: medium(day)
                case .accessoryRectangular: rectangular(day)
                case .accessoryInline: inline(day)
                default: small(day)
                }
            } else if family == .accessoryInline {
                Text("Wird : ouvre l’app")
            } else if family == .accessoryRectangular {
                Text("Ouvre Wird pour voir ton passage").font(.caption)
            } else {
                OpenWird()
            }
        }
        .wirdBackground()
    }

    private func small(_ day: WidgetDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("Apprendre", done: day.learning?.done ?? false)
            Spacer(minLength: 0)
            if let p = day.learning {
                Text(p.title)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .strikethrough(p.done, color: .secondary)
                Text(p.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Tout est appris, machAllah !").font(.subheadline.weight(.semibold))
            }
            if let plan = day.plan, day.learning?.done == false {
                Text(plan).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ day: WidgetDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MiniLogo(size: 18)
                Text("Aujourd’hui").font(.caption.weight(.bold))
                Spacer()
                if let plan = day.plan { Text(plan).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            HStack(alignment: .top, spacing: 12) {
                column("Apprendre", "plus.circle", day.learning, empty: "Tout est appris")
                Divider()
                column("Réviser", "arrow.triangle.2.circlepath", day.revision, empty: "Rien à réviser")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ title: String, _ icon: String, _ p: WidgetPart?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: p?.done == true ? "checkmark.circle.fill" : icon)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(p?.done == true ? Color.primary : Color.secondary)
            if let p {
                Text(p.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(3).minimumScaleFactor(0.75)
                    .strikethrough(p.done, color: .secondary)
                Text(p.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(empty).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            MiniLogo(size: 18)
            Text(title).font(.caption.weight(.bold))
            Spacer(minLength: 0)
            if done { Image(systemName: "checkmark.circle.fill").font(.subheadline) }
        }
    }

    private func rectangular(_ day: WidgetDay) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: day.learning?.done == true ? "checkmark.circle.fill" : "book.closed")
                Text(day.learning?.done == true ? "Appris aujourd’hui" : "À apprendre")
            }
            .font(.caption2.weight(.semibold))
            Text(day.learning?.title ?? "Tout est appris")
                .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(day.revision.map { ($0.done ? "✓ " : "") + "Réviser " + $0.title } ?? day.learning?.detail ?? "")
                .font(.caption2).lineLimit(1)
        }
        .widgetAccentable()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ day: WidgetDay) -> some View {
        if let p = day.learning {
            return Text((p.done ? "✓ " : "") + p.title.replacingOccurrences(of: "\n", with: " · "))
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
        .description("Le temps qu’il reste avant ton cours et où tu en es de ton objectif.")
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
            } else {
                OpenWird(text: "Règle ton cours dans l’onglet Cours de Wird.")
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
            Text("Cours \(whenShort(days, next)) · \(Int(share * 100)) %")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Prochain cours").font(.caption2.weight(.semibold))
                countdown(days, next).font(.headline)
                Gauge(value: share) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                Text("\(WirdCal.pages(done)) / \(WirdCal.pages(c.goal)) pages").font(.caption2)
            }
            .widgetAccentable()
        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        MiniLogo(size: 18)
                        Text("Prochain cours").font(.caption.weight(.bold))
                    }
                    countdown(days, next)
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(next, format: .dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "fr_FR")))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let r = c.recite {
                        Text("À réciter : \(r)").font(.caption2).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                progress(share, done, c.goal, size: 96)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    MiniLogo(size: 18)
                    Text("Cours").font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                    Text(next, format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_FR")))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                countdown(days, next)
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Objectif").font(.caption2).foregroundStyle(.secondary)
                        Text("\(WirdCal.pages(done))/\(WirdCal.pages(c.goal)) p.").font(.caption.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    progress(share, done, c.goal, size: 52)
                }
            }
        }
    }

    /// Le jour même : un minuteur qui défile. Sinon : « Dans 3 jours ».
    @ViewBuilder private func countdown(_ days: Int, _ next: Date) -> some View {
        if days == 0 {
            Text(timerInterval: entry.date...next, countsDown: true)
        } else if days == 1 {
            Text("Demain \(next.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR"))))")
        } else {
            Text("Dans \(days) jours")
        }
    }

    private func whenShort(_ days: Int, _ next: Date) -> String {
        days == 0 ? "aujourd’hui" : days == 1 ? "demain" : "dans \(days) j"
    }

    private func progress(_ share: Double, _ done: Double, _ goal: Double, size: CGFloat) -> some View {
        ZStack {
            Ring(value: share, width: size > 60 ? 9 : 6)
            Text("\(Int((share * 100).rounded())) %")
                .font(.system(size: size > 60 ? 20 : 12, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 3. Série

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
                OpenWird(text: "Ouvre Wird une fois pour voir ta série.")
            }
        }
        .wirdBackground()
    }

    private func small(_ snap: WidgetSnapshot, _ n: Int) -> some View {
        let days = (0..<7).reversed().map { WirdCal.add(-$0, to: WirdCal.start(entry.date)) }
        let letters = ["D", "L", "M", "M", "J", "V", "S"]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(n > 0 ? bookmarkRed : .secondary)
                Spacer()
                MiniLogo(size: 18)
            }
            Spacer(minLength: 0)
            Text("\(n)")
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(n > 1 ? "jours d’affilée" : n == 1 ? "jour" : "Coche ton wird aujourd’hui")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
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
