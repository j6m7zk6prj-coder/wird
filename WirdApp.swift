import SwiftUI

@main
struct WirdApp: App {
    @State private var store = QuranStore()
    @State private var tracker = Tracker()
    @State private var recitation = Recitation()
    @State private var recorder = VoiceRecorder()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(tracker)
                .environment(recitation)
                .environment(recorder)
                .tint(.brand)
                .task { await store.load() }
        }
    }
}

/// Les onglets : aujourd'hui, objectifs, le Coran, ta progression.
struct RootView: View {
    @Environment(QuranStore.self) private var store
    @AppStorage("tab") private var tab = 0

    var body: some View {
        Group {
            if let error = store.error {
                ContentUnavailableView("Problème", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if !store.loaded {
                VStack(spacing: 14) {
                    Text("وِرْد").font(.custom(Fonts.quranName, size: 54)).foregroundStyle(Color.brand)
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { AppBackground() }
            } else {
                TabView(selection: $tab) {
                    NavigationStack { TodayView() }
                        .tabItem { Label("Aujourd’hui", systemImage: "sun.horizon.fill") }
                        .tag(0)
                    NavigationStack { PlansView() }
                        .tabItem { Label("Objectifs", systemImage: "target") }
                        .tag(1)
                    NavigationStack { LibraryView() }
                        .tabItem { Label("Coran", systemImage: "book.fill") }
                        .tag(2)
                    NavigationStack { ProgressTab() }
                        .tabItem { Label("Progrès", systemImage: "chart.bar.fill") }
                        .tag(3)
                }
                .overlay(alignment: .top) { Banner() }
            }
        }
    }
}

// MARK: - Le Coran : reprendre la lecture, et la liste des sourates

struct LibraryView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @State private var reading: ReadingPosition?
    @State private var query = ""
    @State private var about = false

    private var filtered: [Surah] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.surahs }
        return store.surahs.filter { $0.tr.lowercased().contains(q) || $0.ar.contains(q) || String($0.n) == q || French.surahName($0.n).lowercased().contains(q) }
    }

    var body: some View {
        List {
            if query.isEmpty, let last = store.last, let s = store.surah(last.surah) {
                Section {
                    Button { reading = last } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "book.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(LinearGradient(colors: [Color(hex: 0x1F8A66), Color(hex: 0x0F5A43)],
                                                           startPoint: .top, endPoint: .bottom),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reprendre la lecture").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(s.tr).font(.headline)
                                Text("Verset \(last.ayah)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(s.ar).font(.custom(Fonts.quranName, size: 24))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section(query.isEmpty ? "Sourates" : "Résultats") {
                ForEach(filtered) { s in
                    NavigationLink { SurahDetail(surah: s) } label: {
                        SurahRow(surah: s, learned: Double(tracker.knownCount(in: store.surahRange(s.n))) / Double(max(1, s.ayat.count)))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground() }
        .navigationTitle("Coran")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { about = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Sources")
            }
        }
        .searchable(text: $query, prompt: "Rechercher une sourate")
        .fullScreenCover(item: $reading) { pos in
            MushafReader(start: pos).environment(store)
        }
        .sheet(isPresented: $about) { AboutView().environment(store) }
    }
}

extension ReadingPosition: Identifiable {
    var id: String { "\(surah):\(ayah)" }
}

struct SurahRow: View {
    let surah: Surah
    var learned: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.gold.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: learned)
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(surah.n)").font(.caption.weight(.bold)).monospacedDigit()
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(surah.tr).font(.body.weight(.semibold))
                Text("\(French.surahName(surah.n)) · \(surah.ayat.count) versets")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(surah.ar)
                .font(.custom(Fonts.quranName, size: 22))
                .foregroundStyle(Color(hex: 0x0F5A43))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Une sourate : la lire, l'apprendre, dire qu'on la connaît, en faire un objectif.
struct SurahDetail: View {
    let surah: Surah
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @State private var reading: ReadingPosition?
    @State private var newPlan = false

    var body: some View {
        let range = store.surahRange(surah.n)
        let known = tracker.knownCount(in: range)
        let pages = Set(range.map { store.page($0) }).sorted()
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(surah.ar).font(.custom(Fonts.quranName, size: 46)).foregroundStyle(Color.brand)
                    Text(surah.tr).font(.title2.bold())
                    Text("\(French.surahName(surah.n)) · \(surah.isMeccan ? "Mecquoise" : "Médinoise")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                HStack(spacing: 0) {
                    stat("\(surah.ayat.count)", "versets")
                    stat(pages.count == 1 ? "p. \(pages[0])" : "p. \(pages.first ?? 1)–\(pages.last ?? 1)", "\(pages.count) page\(pages.count > 1 ? "s" : "")")
                    stat("\(Int((Double(known) / Double(max(1, surah.ayat.count)) * 100).rounded())) %", "apprise")
                }
                .padding(.vertical, 14)
                .glass(22)

                VStack(spacing: 10) {
                    Button { reading = ReadingPosition(surah: surah.n, ayah: 1) } label: {
                        Label("Lire dans le Mushaf", systemImage: "book.pages")
                    }
                    .buttonStyle(BigButtonStyle())
                    NavigationLink {
                        StudyView(ayat: Array(range), title: surah.tr, mode: .free)
                    } label: {
                        Label("Apprendre et écouter", systemImage: "headphones")
                    }
                    .buttonStyle(BigButtonStyle(color: .gold))
                }

                VStack(spacing: 0) {
                    Button {
                        if known == range.count { tracker.forget(range, store) } else { tracker.markKnown(range, store) }
                    } label: {
                        row(known == range.count ? "Je ne la connais plus" : "Je la connais déjà",
                            known == range.count ? "xmark.circle" : "checkmark.seal.fill")
                    }
                    Divider().padding(.leading, 50)
                    Button { newPlan = true } label: {
                        row("Créer un objectif pour cette sourate", "target")
                    }
                }
                .glass(22)
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $reading) { pos in
            MushafReader(start: pos).environment(store)
        }
        .sheet(isPresented: $newPlan) { PlanEditor(surah: surah.n) }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit())
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(Color.brand).frame(width: 24)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

/// Sources du texte et licences (obligatoire : le texte de Tanzil doit être cité).
struct AboutView: View {
    @Environment(QuranStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Texte du Coran") {
                    Text("Texte uthmani de Tanzil (tanzil.net), intégré tel quel, sans aucune modification. Il a été vérifié lettre par lettre avec le texte du Complexe du Roi Fahd (Médine) : 114 sourates, 6 236 versets.")
                    Text(store.sourceNotice).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Pages et juz") {
                    Text("Numéros de page (604 pages) et de juz du Mushaf de Médine, d’après les données du Complexe du Roi Fahd (KFGQPC, Hafs).")
                }
                Section("Tajwid") {
                    Text("Les couleurs du tajwid viennent des annotations du projet « quran-tajweed » (Collin Fair), licence Creative Commons Attribution 4.0.")
                    Text(store.tajweedNotice).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Récitations") {
                    Text("Les récitations audio sont lues en ligne depuis everyayah.com.")
                }
                Section("Police") {
                    Text("Amiri Quran, par Khaled Hosny — licence SIL Open Font License 1.1.")
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

/// Le sens des noms des sourates, en français.
enum French {
    static let names = [
        "L’Ouverture", "La Vache", "La Famille d’Imran", "Les Femmes", "La Table servie", "Les Bestiaux",
        "Les Murailles", "Le Butin", "Le Repentir", "Jonas", "Houd", "Joseph", "Le Tonnerre", "Abraham",
        "Al-Hijr", "Les Abeilles", "Le Voyage nocturne", "La Caverne", "Marie", "Ta-Ha", "Les Prophètes",
        "Le Pèlerinage", "Les Croyants", "La Lumière", "Le Discernement", "Les Poètes", "Les Fourmis",
        "Le Récit", "L’Araignée", "Les Romains", "Louqman", "La Prosternation", "Les Coalisés", "Saba",
        "Le Créateur", "Ya-Sin", "Les Rangées", "Sad", "Les Groupes", "Le Pardonneur", "Les Versets détaillés",
        "La Consultation", "L’Ornement", "La Fumée", "L’Agenouillée", "Al-Ahqaf", "Muhammad",
        "La Victoire éclatante", "Les Appartements", "Qaf", "Qui éparpillent", "Le Mont", "L’Étoile",
        "La Lune", "Le Tout Miséricordieux", "L’Événement", "Le Fer", "La Discussion", "L’Exode",
        "L’Éprouvée", "Le Rang", "Le Vendredi", "Les Hypocrites", "La Grande Perte", "Le Divorce",
        "L’Interdiction", "La Royauté", "La Plume", "Celle qui montre la vérité", "Les Voies d’ascension",
        "Noé", "Les Djinns", "L’Enveloppé", "Le Revêtu d’un manteau", "La Résurrection", "L’Homme",
        "Les Envoyés", "La Nouvelle", "Les Anges qui arrachent", "Il s’est renfrogné", "L’Obscurcissement",
        "La Rupture", "Les Fraudeurs", "La Déchirure", "Les Constellations", "L’Astre nocturne",
        "Le Très-Haut", "L’Enveloppante", "L’Aube", "La Cité", "Le Soleil", "La Nuit", "Le Jour montant",
        "L’Ouverture de la poitrine", "Le Figuier", "L’Adhérence", "La Destinée", "La Preuve",
        "La Secousse", "Les Coursiers", "Le Fracas", "La Course aux richesses", "Le Temps",
        "Les Calomniateurs", "L’Éléphant", "Quraych", "L’Ustensile", "L’Abondance", "Les Infidèles",
        "Le Secours", "Les Fibres", "Le Monothéisme pur", "L’Aube naissante", "Les Hommes"
    ]

    static func surahName(_ n: Int) -> String { names.indices.contains(n - 1) ? names[n - 1] : "" }
}
