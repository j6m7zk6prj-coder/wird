import SwiftUI

// MARK: - Progrès : ce que tu connais, ta régularité, ta mémoire, juz par juz

struct ProgressTab: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                KnowledgeCard()
                RegularityCard()
                MemoryCard()
                JuzList()
                Badges()
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Progrès")
    }
}

/// Une carte avec un titre et une phrase d'explication.
struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glass(24)
    }
}

/// Une barre de progression simple, noire (ou blanche en sombre).
struct Bar: View {
    let value: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.primary)
                    .frame(width: value > 0 ? max(height, geo.size.width * CGFloat(min(1, value))) : 0)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
    }
}

// MARK: 1. Ce que tu connais

private struct KnowledgeCard: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    var body: some View {
        let share = Double(tracker.known.count) / Double(QuranStore.ayahCount)
        VStack(alignment: .leading, spacing: 14) {
            Text("TU CONNAIS PAR CŒUR").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(percent(share)).font(.system(size: 48, weight: .bold, design: .rounded))
                Text("du Coran").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            Bar(value: share, height: 10)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    number("\(tracker.learnedPages(store))", "/ 604", "pages")
                    number("\(tracker.completeHizb(store))", "/ 60", "hizb")
                }
                GridRow {
                    number("\(tracker.completeJuz(store))", "/ 30", "juz")
                    number("\(tracker.completeSurahs(store))", "/ 114", "sourates")
                }
            }
            Text("On ne compte que ce qui est su en entier : une page à moitié apprise n’est pas encore comptée.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glass(26)
    }

    private func percent(_ v: Double) -> String {
        if v <= 0 { return "0 %" }
        if v < 0.01 { return "< 1 %" }
        return "\(Int((v * 100).rounded())) %"
    }

    private func number(_ v: String, _ total: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(v).font(.title2.bold().monospacedDigit())
                Text(total).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: 2. Ta régularité

private struct RegularityCard: View {
    @Environment(Tracker.self) private var tracker

    var body: some View {
        let days = (0..<7).reversed().map { Day.add(-$0, to: Day.start(.now)) }
        let week = days.reduce(DayActivity()) { sum, d in
            let a = tracker.activity[Day.key(d)] ?? DayActivity()
            return DayActivity(learned: sum.learned + a.learned, reviewed: sum.reviewed + a.reviewed, read: sum.read + a.read)
        }
        Card(title: "Ta régularité", subtitle: "Un jour compte dès que tu as appris, révisé ou lu quelque chose.") {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let active = (tracker.activity[Day.key(d)]?.total ?? 0) > 0
                    let today = Day.key(d) == Day.key(.now)
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(active ? Color.primary : Color.primary.opacity(0.06))
                            if active {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.onBrand)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay { if today { Circle().strokeBorder(Color.primary, lineWidth: 1.5).padding(-4) } }
                        Text(letter(d)).font(.caption2.weight(today ? .bold : .regular)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                Text(tracker.streak == 0 ? "Pas de série en cours" : "\(tracker.streak) jour\(tracker.streak > 1 ? "s" : "") d’affilée")
                    .font(.headline)
                Spacer()
                Text("Record : \(max(tracker.bestStreak, tracker.streak))").font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("CES 7 DERNIERS JOURS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                line("Versets appris", week.learned)
                line("Pages révisées", week.reviewed)
                line("Versets lus", week.read)
            }
        }
    }

    private func letter(_ d: Date) -> String {
        Day.week.first { $0.0 == Day.weekday(d) }?.1 ?? ""
    }

    private func line(_ label: String, _ v: Int) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text("\(v)").font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

// MARK: 3. Ta mémoire

/// Le petit rond qui montre la solidité d'une page.
struct StrengthDot: View {
    let strength: Strength
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch strength {
            case .solid: Circle().fill(Color.primary)
            case .soon: Circle().fill(Color.primary.opacity(0.45))
            case .weak: Circle().strokeBorder(Color.primary, lineWidth: 1.6)
            case .partial: Circle().strokeBorder(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, dash: [2, 2]))
            case .none: Circle().fill(Color.primary.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct MemoryCard: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    var body: some View {
        let states = tracker.memory.keys.map { tracker.strength($0, store) }
        let solid = states.filter { $0 == .solid }.count
        let soon = states.filter { $0 == .soon }.count
        let weak = states.filter { $0 == .weak }.count
        let total = max(1, solid + soon + weak)
        Card(title: "Ta mémoire", subtitle: "L’état des pages que tu connais. Chaque révision les rend plus solides.") {
            if solid + soon + weak == 0 {
                Text("Rien pour l’instant. Termine une tâche « À apprendre » ou indique ce que tu connais déjà dans les Réglages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        if solid > 0 { Capsule().fill(Color.primary).frame(width: geo.size.width * CGFloat(solid) / CGFloat(total)) }
                        if soon > 0 { Capsule().fill(Color.primary.opacity(0.45)).frame(width: geo.size.width * CGFloat(soon) / CGFloat(total)) }
                        if weak > 0 { Capsule().strokeBorder(Color.primary, lineWidth: 1.5).frame(width: geo.size.width * CGFloat(weak) / CGFloat(total)) }
                    }
                }
                .frame(height: 12)
                row(.solid, solid, "Bien en mémoire, rien à faire")
                row(.soon, soon, "À revoir dans les prochains jours")
                row(.weak, weak, "À revoir en priorité")
            }
        }
    }

    private func row(_ s: Strength, _ n: Int, _ help: String) -> some View {
        HStack(spacing: 12) {
            StrengthDot(strength: s, size: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.label).font(.subheadline.weight(.semibold))
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(n) page\(n > 1 ? "s" : "")").font(.subheadline.monospacedDigit())
        }
    }
}

// MARK: 4. Juz par juz

private struct JuzList: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    var body: some View {
        Card(title: "Juz par juz", subtitle: "Touche un juz pour voir ses pages et ses hizb.") {
            VStack(spacing: 0) {
                ForEach((1...30).reversed(), id: \.self) { j in
                    JuzRow(juz: j)
                    if j > 1 { Divider().padding(.leading, 42) }
                }
            }
        }
    }
}

private struct JuzRow: View {
    let juz: Int
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    private var share: Double {
        let range = store.juzRange(juz)
        return Double(tracker.knownCount(in: range)) / Double(max(1, range.count))
    }

    private var name: String {
        switch juz {
        case 30: return "Juz Amma"
        case 29: return "Juz Tabarak"
        default: return "Juz \(juz) · " + store.label(store.juzRange(juz).lowerBound)
        }
    }

    var body: some View {
        let value = share
        let complete = value >= 1
        NavigationLink { JuzDetail(juz: juz) } label: {
            HStack(spacing: 12) {
                Text("\(juz)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(complete ? Color.primary : Color.primary.opacity(0.06)))
                    .foregroundStyle(complete ? Color.onBrand : Color.primary)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        Text(percentText(value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Bar(value: value, height: 5)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func percentText(_ v: Double) -> String {
        let n = Int((v * 100).rounded())
        return "\(n) %"
    }
}

/// Un juz : ses 2 hizb, et toutes ses pages.
struct JuzDetail: View {
    let juz: Int
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @State private var selected: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                legend
                HizbSection(hizb: 2 * juz - 1, selected: $selected)
                HizbSection(hizb: 2 * juz, selected: $selected)
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: sheetItem) { p in
            PageSheet(page: p.page)
        }
    }

    private var title: String {
        switch juz {
        case 30: return "Juz Amma"
        case 29: return "Juz Tabarak"
        default: return "Juz \(juz)"
        }
    }

    private var sheetItem: Binding<PageID?> {
        Binding(get: { selected.map { PageID(page: $0) } }, set: { selected = $0?.page })
    }

    struct PageID: Identifiable { let page: Int; var id: Int { page } }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach([Strength.solid, .soon, .weak, .partial, .none], id: \.rawValue) { s in
                HStack(spacing: 6) {
                    StrengthDot(strength: s, size: 12)
                    Text(s.label).font(.caption)
                }
            }
        }
        .padding(14)
        .glass(18)
    }
}

/// Un hizb : ses pages en petites cases.
private struct HizbSection: View {
    let hizb: Int
    @Binding var selected: Int?
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    private var range: Range<Int> { store.hizbRange(hizb) }
    private var firstPage: Int { store.page(range.lowerBound) }
    private var lastPage: Int { store.page(range.upperBound - 1) }

    private var subtitle: String {
        let known = tracker.knownCount(in: range)
        let share = Double(known) / Double(max(1, range.count))
        let percent = Int((share * 100).rounded())
        return store.label(range.lowerBound) + " · pages \(firstPage)–\(lastPage) · \(percent) % su"
    }

    var body: some View {
        Card(title: "Hizb \(hizb)", subtitle: subtitle) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(firstPage...lastPage, id: \.self) { p in
                    Button { selected = p } label: { PageTile(page: p) }
                        .buttonStyle(PressStyle())
                }
            }
        }
    }
}

/// Une page dans la grille : son numéro, en noir plein si elle est solide.
struct PageTile: View {
    let page: Int
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    var body: some View {
        let s = tracker.strength(page, store)
        Text("\(page)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(s == .solid || s == .soon ? Color.onBrand : (s == .none ? Color.secondary : Color.primary))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                switch s {
                case .solid: shape.fill(Color.primary)
                case .soon: shape.fill(Color.primary.opacity(0.45))
                case .weak: shape.strokeBorder(Color.primary, lineWidth: 1.6)
                case .partial: shape.strokeBorder(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                case .none: shape.fill(Color.primary.opacity(0.05))
                }
            }
            .accessibilityLabel("Page \(page), \(s.label)")
    }
}

/// Une page : où elle en est, la réviser, la noter.
struct PageSheet: View {
    let page: Int
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = tracker.strength(page, store)
        let range = store.pageRange(page)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        PageTile(page: page).frame(width: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.surahs(onPage: page).map { store.name($0) }.joined(separator: ", ")).font(.headline)
                            Text("Juz \(store.juz(range.lowerBound)) · hizb \(store.hizb(range.lowerBound)) · \(range.count) versets")
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                StrengthDot(strength: s)
                                Text(s.label).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    if let m = tracker.memory[page], s != .partial {
                        LabeledContent("Prochaine révision", value: Dates.short(m.nextReview()))
                        LabeledContent("Révisée", value: "\(m.reviews) fois")
                    }
                }
                Section {
                    NavigationLink {
                        StudyView(ayat: Array(range), title: "Page \(page)", mode: tracker.memory[page] == nil ? .free : .review([page]))
                    } label: {
                        Label(tracker.memory[page] == nil ? "Ouvrir la page" : "Réviser maintenant", systemImage: "play.fill")
                    }
                }
                if tracker.memory[page] != nil {
                    Section("Je viens de la réciter, c’était…") {
                        ForEach(Grade.allCases.reversed()) { g in
                            Button {
                                tracker.grade(page, g)
                                dismiss()
                            } label: {
                                Label(g.label, systemImage: g.symbol)
                            }
                        }
                    }
                }
                Section {
                    if s == .none || s == .partial {
                        Button("Je connais cette page", systemImage: "checkmark.seal") { tracker.markKnown(range, store) }
                    }
                    if s != .none {
                        Button("Je ne la connais plus", systemImage: "xmark.circle", role: .destructive) { tracker.forget(range, store) }
                    }
                }
            }
            .navigationTitle("Page \(page)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: 5. Les étapes

struct Badges: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    struct Badge: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let won: Bool
    }

    var body: some View {
        let pages = tracker.learnedPages(store)
        let hizb = tracker.completeHizb(store)
        let juz = tracker.completeJuz(store)
        let best = max(tracker.bestStreak, tracker.streak)
        let finished = tracker.plans.contains { $0.position >= $0.total || $0.cycles > 0 }
        let khatm = tracker.plans.contains { $0.kind == .read && $0.total == QuranStore.ayahCount && ($0.position >= $0.total || $0.cycles > 0) }
        let list = [
            Badge(id: "p1", symbol: "leaf.fill", title: "Première page", won: pages >= 1),
            Badge(id: "s7", symbol: "flame.fill", title: "7 jours d’affilée", won: best >= 7),
            Badge(id: "h1", symbol: "seal.fill", title: "Un hizb complet", won: hizb >= 1),
            Badge(id: "j1", symbol: "seal.fill", title: "Un juz complet", won: juz >= 1),
            Badge(id: "goal", symbol: "target", title: "Objectif atteint", won: finished),
            Badge(id: "s30", symbol: "flame.circle.fill", title: "30 jours d’affilée", won: best >= 30),
            Badge(id: "j5", symbol: "star.fill", title: "5 juz", won: juz >= 5),
            Badge(id: "khatm", symbol: "moon.stars.fill", title: "Coran lu en entier", won: khatm),
            Badge(id: "p100", symbol: "rosette", title: "100 pages", won: pages >= 100),
            Badge(id: "s100", symbol: "bolt.heart.fill", title: "100 jours d’affilée", won: best >= 100),
            Badge(id: "half", symbol: "circle.lefthalf.filled", title: "La moitié du Coran", won: hizb >= 30),
            Badge(id: "all", symbol: "crown.fill", title: "Tout le Coran", won: pages >= 604)
        ]
        let won = list.filter(\.won).count
        Card(title: "Étapes", subtitle: "\(won) sur \(list.count) atteintes") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(list) { b in
                    VStack(spacing: 8) {
                        Image(systemName: b.symbol)
                            .font(.title3)
                            .foregroundStyle(b.won ? Color.onBrand : Color.secondary)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(b.won ? Color.primary : Color.primary.opacity(0.06)))
                        Text(b.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(b.won ? Color.primary : Color.secondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(b.won ? 1 : 0.55)
                }
            }
        }
    }
}
