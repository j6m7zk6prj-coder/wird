import SwiftUI
import Charts

// MARK: - Progrès : chiffres, graphique, carte des 604 pages, badges

struct ProgressTab: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @State private var view = 0
    @State private var selectedPage: Int?

    var body: some View {
        let pages = tracker.learnedPages(store)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Le gros chiffre.
                HStack(spacing: 18) {
                    ZStack {
                        Ring(value: Double(tracker.known.count) / Double(QuranStore.ayahCount), width: 12)
                        VStack(spacing: 0) {
                            Text(percent(Double(tracker.known.count) / Double(QuranStore.ayahCount)))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("du Coran").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        line("\(pages) / 604", "pages apprises")
                        line("\(tracker.known.count)", "versets appris")
                        line("\(tracker.completeJuz(store)) juz · \(tracker.completeSurahs(store)) sourates", "complets")
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .glass(26)

                HStack(spacing: 12) {
                    tile("flame.fill", .orange, "\(tracker.streak)", "jours d’affilée")
                    tile("trophy.fill", .gold, "\(tracker.bestStreak)", "meilleure série")
                    tile("arrow.triangle.2.circlepath", .brand, "\(tracker.memory.values.reduce(0) { $0 + $1.reviews })", "révisions")
                }

                chart

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ta carte du Coran").font(.title3.bold())
                        Spacer()
                        Picker("Vue", selection: $view) {
                            Text("Pages").tag(0)
                            Text("Sourates").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    legend
                    if view == 0 { pageMap } else { surahList }
                }

                Badges()
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Progrès")
        .sheet(item: Binding(get: { selectedPage.map(PageID.init) }, set: { selectedPage = $0?.page })) { p in
            PageSheet(page: p.page)
        }
    }

    struct PageID: Identifiable { let page: Int; var id: Int { page } }

    private func percent(_ v: Double) -> String {
        v > 0 && v < 0.01 ? "< 1 %" : "\(Int((v * 100).rounded())) %"
    }

    private func line(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.headline.monospacedDigit())
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tile(_ symbol: String, _ color: Color, _ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(v).font(.title2.bold().monospacedDigit())
            Text(l).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glass(20)
    }

    // Les 30 derniers jours.
    private var chart: some View {
        let days = (0..<30).reversed().map { Day.add(-$0, to: Day.start(.now)) }
        let points = days.flatMap { d -> [(Date, String, Int)] in
            let a = tracker.activity[Day.key(d)] ?? DayActivity()
            return [(d, "Appris (versets)", a.learned), (d, "Révisé (pages)", a.reviewed), (d, "Lu (versets)", a.read)]
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("30 derniers jours").font(.headline)
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("Jour", p.0, unit: .day), y: .value("Quantité", p.2))
                        .foregroundStyle(by: .value("Type", p.1))
                        .cornerRadius(3)
                }
            }
            .chartForegroundStyleScale(["Appris (versets)": Color.brand, "Révisé (pages)": Color.gold, "Lu (versets)": Color(hex: 0x3F7FBF)])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Dates.fr))
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: 180)
        }
        .padding(16)
        .glass(24)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([Strength.solid, .soon, .weak, .partial, .none], id: \.rawValue) { s in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 11, height: 11)
                    Text(s.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .minimumScaleFactor(0.8)
    }

    // 30 juz, chacun avec ses pages en petits carrés.
    private var pageMap: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(1...30, id: \.self) { j in
                let first = store.page(store.juzRange(j).lowerBound)
                let last = store.page(store.juzRange(j).upperBound - 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Juz \(j)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 11), spacing: 4) {
                        ForEach(first...last, id: \.self) { p in
                            Button { selectedPage = p } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(tracker.strength(p, store).color)
                                    .aspectRatio(0.72, contentMode: .fit)
                                    .overlay {
                                        Text("\(p)").font(.system(size: 7, weight: .semibold)).foregroundStyle(.primary.opacity(0.45))
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Page \(p), \(tracker.strength(p, store).label)")
                        }
                    }
                }
            }
        }
        .padding(16)
        .glass(24)
    }

    private var surahList: some View {
        LazyVStack(spacing: 0) {
            ForEach(store.surahs) { s in
                let known = tracker.knownCount(in: store.surahRange(s.n))
                NavigationLink { SurahDetail(surah: s) } label: {
                    HStack(spacing: 12) {
                        Text("\(s.n)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.tr).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Spacer()
                                Text("\(known)/\(s.ayat.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(known), total: Double(s.ayat.count))
                                .tint(known == s.ayat.count ? Color(hex: 0x2FA36B) : .brand)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .glass(24)
    }
}

/// Une page de la carte : où elle en est, la réviser, la noter.
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
                        Text("\(page)")
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(s.color.gradient))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.surahs(onPage: page).map { store.name($0) }.joined(separator: ", ")).font(.headline)
                            Text("Juz \(store.juz(range.lowerBound)) · \(range.count) versets").font(.subheadline).foregroundStyle(.secondary)
                            Text(s.label).font(.subheadline.weight(.semibold)).foregroundStyle(s == .none ? Color.secondary : s.color)
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
                                Label(g.label, systemImage: g.symbol).foregroundStyle(g.color)
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

/// Les étapes fêtées.
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
        let juz = tracker.completeJuz(store)
        let best = max(tracker.bestStreak, tracker.streak)
        let finished = tracker.plans.contains { $0.position >= $0.total || $0.cycles > 0 }
        let khatm = tracker.plans.contains { $0.kind == .read && $0.total == QuranStore.ayahCount && ($0.position >= $0.total || $0.cycles > 0) }
        let list = [
            Badge(id: "p1", symbol: "leaf.fill", title: "Première page", won: pages >= 1),
            Badge(id: "s7", symbol: "flame.fill", title: "7 jours d’affilée", won: best >= 7),
            Badge(id: "p10", symbol: "book.closed.fill", title: "10 pages", won: pages >= 10),
            Badge(id: "j1", symbol: "seal.fill", title: "Un juz complet", won: juz >= 1),
            Badge(id: "goal", symbol: "target", title: "Objectif atteint", won: finished),
            Badge(id: "s30", symbol: "flame.circle.fill", title: "30 jours d’affilée", won: best >= 30),
            Badge(id: "p50", symbol: "books.vertical.fill", title: "50 pages", won: pages >= 50),
            Badge(id: "j5", symbol: "star.fill", title: "5 juz", won: juz >= 5),
            Badge(id: "khatm", symbol: "moon.stars.fill", title: "Coran lu en entier", won: khatm),
            Badge(id: "p100", symbol: "rosette", title: "100 pages", won: pages >= 100),
            Badge(id: "s100", symbol: "bolt.heart.fill", title: "100 jours d’affilée", won: best >= 100),
            Badge(id: "half", symbol: "circle.lefthalf.filled", title: "La moitié du Coran", won: pages >= 302),
            Badge(id: "all", symbol: "crown.fill", title: "Tout le Coran", won: pages >= 604)
        ]
        VStack(alignment: .leading, spacing: 12) {
            Text("Étapes").font(.title3.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(list) { b in
                    VStack(spacing: 8) {
                        Image(systemName: b.symbol)
                            .font(.title2)
                            .foregroundStyle(b.won ? Color.white : Color.secondary)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(b.won ? AnyShapeStyle(LinearGradient(colors: [.gold, .brand], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        Text(b.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(b.won ? .primary : .secondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glass(20)
                    .opacity(b.won ? 1 : 0.6)
                }
            }
        }
    }
}
