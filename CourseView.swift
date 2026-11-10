import SwiftUI

// MARK: - Cours : le compte à rebours jusqu'au cours, et où tu en es de ton objectif

struct CourseView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let c = journal.course {
                    Countdown(big: true)
                    CourseProgress()
                    recite
                    settings(c)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2").font(.system(size: 44))
                        Text("Ton cours").font(.title2.bold())
                        Text("Wird compte le temps qu’il reste avant ton cours et te montre où tu en es de ton objectif de la semaine.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Cours le vendredi à 19 h") { journal.startCourse() }
                            .buttonStyle(BigButtonStyle())
                        Text("Tu pourras changer le jour et l’heure ensuite.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .wirdGlass(26)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Cours")
    }

    /// Ce que tu as appris depuis le dernier cours.
    @ViewBuilder private var recite: some View {
        let ayat = journal.learnedSinceCourse(store)
        VStack(alignment: .leading, spacing: 6) {
            Text("À RÉCITER AU COURS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            if ayat.isEmpty {
                Text("Rien de nouveau depuis le dernier cours. Coche ton apprentissage chaque jour : ça s’ajoute ici.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(Passage.label(ayat, store))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(Passage.detail(ayat, store.pages(of: ayat))).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wirdGlass(26)
    }

    private func settings(_ c: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MON COURS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            HStack {
                Text("Jour")
                Spacer()
                Picker("Jour", selection: Binding(get: { c.weekday },
                                                  set: { journal.setCourse(weekday: $0, hour: c.hour ?? 19, minute: c.minute ?? 0) })) {
                    ForEach(Day.names, id: \.0) { d in Text(d.1).tag(d.0) }
                }
                .pickerStyle(.menu)
            }
            DatePicker("Heure", selection: Binding(get: { time(c) }, set: { d in
                let parts = Day.calendar.dateComponents([.hour, .minute], from: d)
                journal.setCourse(weekday: c.weekday, hour: parts.hour ?? 19, minute: parts.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            .environment(\.locale, Dates.fr)
            Divider()
            Button("Ne plus suivre de cours", role: .destructive) { journal.stopCourse() }
                .font(.subheadline)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wirdGlass(26)
    }

    private func time(_ c: Course) -> Date {
        Day.calendar.date(bySettingHour: c.hour ?? 19, minute: c.minute ?? 0, second: 0, of: .now) ?? .now
    }
}

/// Le compte à rebours : jours, heures, minutes, secondes, qui défilent en direct.
struct Countdown: View {
    var big = false
    @Environment(Journal.self) private var journal

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            if let next = journal.nextCourse(after: now) {
                let left = max(0, Int(next.timeIntervalSince(now)))
                let d = left / 86_400
                let h = (left % 86_400) / 3600
                let m = (left % 3600) / 60
                let s = left % 60
                VStack(alignment: .leading, spacing: big ? 12 : 6) {
                    HStack {
                        Label("Prochain cours", systemImage: "person.2").font(big ? .title3.bold() : .headline)
                        Spacer()
                        Text(Dates.dayShort(next).capitalized(with: Dates.fr) + " · " + Dates.hour(next))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: big ? 10 : 6) {
                        if d > 0 { unit(d, d > 1 ? "jours" : "jour") }
                        unit(h, "h")
                        unit(m, "min")
                        unit(s, "s")
                    }
                    .frame(maxWidth: .infinity, alignment: big ? .center : .leading)
                }
            }
        }
        .padding(big ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wirdGlass(26)
    }

    private func unit(_ v: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(String(format: "%02d", v))
                .font(.system(size: big ? 44 : 26, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
            Text(label).font(big ? .subheadline : .caption).foregroundStyle(.secondary)
        }
    }
}

/// Où tu en es de ton objectif depuis le dernier cours (par exemple 1,5 / 3 pages = 50 %).
struct CourseProgress: View {
    var compact = false
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal

    var body: some View {
        let ayat = journal.learnedSinceCourse(store)
        let done = store.pages(ayat, 0, ayat.count)
        let goal = journal.learning?.pagesPerWeek ?? 0
        let share = goal > 0 ? done / goal : 0
        let left = max(0, goal - done)
        VStack(alignment: .leading, spacing: 12) {
            if !compact {
                Text("TON OBJECTIF POUR CE COURS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            }
            if journal.learning == nil {
                Text("Fixe un objectif dans l’onglet Apprentissage pour voir ta progression ici.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    ZStack {
                        Ring(value: min(1, share), width: compact ? 7 : 10)
                        Text("\(Int((min(9.99, share) * 100).rounded())) %")
                            .font(.system(size: compact ? 15 : 22, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .frame(width: compact ? 62 : 96, height: compact ? 62 : 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Num.pages(done)) / \(Num.pagesLabel(goal))").font(compact ? .headline : .title3.bold())
                        Text("appris depuis le dernier cours").font(.caption).foregroundStyle(.secondary)
                        Text(left <= 0.01 ? "Objectif atteint, machAllah !" : "Encore \(Num.pagesLabel(left)) avant le cours")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(compact ? 16 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wirdGlass(26)
    }
}
