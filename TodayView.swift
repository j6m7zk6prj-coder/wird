import SwiftUI

// MARK: - Aujourd'hui : deux cases à cocher, et ton journal

struct TodayView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @State private var settings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    WirdLogo(size: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Dates.long(.now).capitalized(with: Dates.fr)).font(.headline)
                        Text(Dates.hijri(.now)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if journal.course != nil {
                    Countdown()
                }

                DayCard(kind: .learning)
                DayCard(kind: .revision)

                JournalHistory()
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Aujourd’hui")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Réglages")
            }
        }
        .sheet(isPresented: $settings) { WirdSettingsView() }
    }
}

enum CardKind { case learning, revision }

/// La carte du jour : quoi faire dans ton Mushaf, et la grosse case « fait ».
struct DayCard: View {
    let kind: CardKind
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @State private var setup = false

    var body: some View {
        let chunk = kind == .learning ? journal.learningChunk(store) : journal.revisionChunk(store)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(kind == .learning ? "Apprentissage" : "Révision",
                      systemImage: kind == .learning ? "plus.circle" : "arrow.triangle.2.circlepath")
                    .font(.title3.bold())
                Spacer()
                if let chunk, chunk.done {
                    Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(Color.primary)
                }
            }

            if journal.learning == nil {
                Text("Indique où tu en es et ton objectif de la semaine.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { setup = true } label: { Text("Commencer") }
                    .buttonStyle(BigButtonStyle())
            } else if let chunk, !chunk.isEmpty {
                passage(chunk)
                if kind == .learning, !chunk.done, let plan = journal.coursePlan(store) {
                    PlanLine(plan: plan)
                }
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if kind == .learning { journal.toggleLearning(store) } else { journal.toggleRevision(store) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: chunk.done ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                            Text(chunk.done ? "C’est fait" : "Je l’ai fait")
                                .font(.headline)
                        }
                        .foregroundStyle(chunk.done ? Color.onBrand : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background {
                            if chunk.done {
                                Capsule().fill(Color.primary)
                                    .shadow(color: Color.black.opacity(0.15), radius: 12, y: 5)
                            } else {
                                Capsule().strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                    }
                    .buttonStyle(WirdPressStyle())
                    if !chunk.done {
                        Menu {
                            Button("Un verset de plus", systemImage: "plus") { adjust(1) }
                            Button("Un verset de moins", systemImage: "minus") { adjust(-1) }
                        } label: {
                            Image(systemName: "plusminus")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(width: 56, height: 56)
                                .wirdGlassCircle()
                        }
                        .accessibilityLabel("Changer le nombre de versets")
                    }
                }
            } else if kind == .learning {
                Text("Tu as terminé tout ce que tu voulais apprendre, machAllah !")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Rien à réviser pour l’instant : coche d’abord ton apprentissage.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wirdGlass(26)
        .sheet(isPresented: $setup) { LearningSetup() }
    }

    private func adjust(_ d: Int) {
        if kind == .learning { journal.adjustLearning(d, store) } else { journal.adjustRevision(d, store) }
    }

    /// « Al-Mulk 1 → 6 » · « 6 versets · page 562 ».
    private func passage(_ c: DayChunk) -> some View {
        let ayat = Array(c.ayat)
        let pages = store.pages(of: ayat)
        return VStack(alignment: .leading, spacing: 4) {
            Text(Passage.label(ayat, store))
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(Passage.detail(ayat, pages))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// « Cours dans 3 jours · encore 1,5 page → 0,5 page par jour ».
struct PlanLine: View {
    let plan: CoursePlan

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
            Text(text).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var when: String {
        switch plan.daysLeft {
        case 1: return "Cours demain"
        default: return "Cours dans \(plan.daysLeft) jours"
        }
    }

    private var text: String {
        if plan.reached {
            return "\(when) : objectif de \(Num.pagesLabel(plan.goal)) déjà atteint, machAllah. Tu prends de l’avance."
        }
        if plan.daysLeft == 1 {
            return "\(when) : il te reste \(Num.pagesLabel(plan.remaining)) sur \(Num.pages(plan.goal)), à faire aujourd’hui."
        }
        return "\(when) : il te reste \(Num.pagesLabel(plan.remaining)) sur \(Num.pages(plan.goal)), soit ≈ \(Num.pagesLabel(plan.today)) par jour."
    }
}

enum Passage {
    /// Le passage à ouvrir dans ton Mushaf. En ordre « de la fin », il peut couvrir plusieurs sourates.
    @MainActor
    static func label(_ ayat: [Int], _ q: QuranStore) -> String {
        guard let first = ayat.first, let last = ayat.last else { return "" }
        // Découpe en morceaux consécutifs (une sourate après l'autre).
        var parts: [String] = []
        var a = first, prev = first
        for g in ayat.dropFirst() {
            if g != prev + 1 {
                parts.append(q.label(from: a, to: prev))
                a = g
            }
            prev = g
        }
        parts.append(q.label(from: a, to: last))
        if parts.count <= 2 { return parts.joined(separator: "\n") }
        // Beaucoup de petites sourates : du début à la fin du passage.
        let surahs = Set(ayat.map { q.ref($0).surah }).count
        return q.label(first) + " → " + q.label(last) + " (\(surahs) sourates)"
    }

    static func detail(_ ayat: [Int], _ pages: [Int]) -> String {
        let v = "\(ayat.count) verset\(ayat.count > 1 ? "s" : "")"
        guard let lo = pages.min(), let hi = pages.max() else { return v }
        return v + " · " + (lo == hi ? "page \(lo)" : "pages \(lo)–\(hi)")
    }
}

/// Les 14 derniers jours : coché ou pas, pour l'apprentissage et la révision.
struct JournalHistory: View {
    @Environment(Journal.self) private var journal

    var body: some View {
        let days = (0..<14).map { Day.add(-$0, to: Day.start(.now)) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mon journal").font(.title3.bold())
                Spacer()
                if journal.streak > 0 {
                    Label("\(journal.streak) jour\(journal.streak > 1 ? "s" : "")", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                }
            }
            HStack {
                Spacer()
                Text("Appr.").frame(width: 52)
                Text("Rév.").frame(width: 52)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let key = Day.key(d)
                    HStack {
                        Text(d == Day.start(.now) ? "Aujourd’hui" : Dates.dayShort(d).capitalized(with: Dates.fr))
                            .font(.subheadline)
                        Spacer()
                        mark(journal.learning.map { $0.log[key] != nil }, d, journal.learning?.created)
                            .frame(width: 52)
                        mark(journal.revision.map { $0.log[key] != nil }, d, journal.revision?.created)
                            .frame(width: 52)
                    }
                    .padding(.vertical, 10)
                    if d != days.last { Divider() }
                }
            }
        }
        .padding(18)
        .wirdGlass(26)
    }

    /// ✓ fait, ✕ pas fait, — pas encore commencé.
    @ViewBuilder
    private func mark(_ done: Bool?, _ d: Date, _ created: Date?) -> some View {
        if done == true {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.primary)
        } else if let created, d >= Day.start(created), d < Day.start(.now) {
            Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        } else {
            Text("–").foregroundStyle(.tertiary)
        }
    }
}
