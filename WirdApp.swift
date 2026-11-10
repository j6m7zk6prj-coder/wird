import SwiftUI

@main
struct WirdApp: App {
    @State private var store = QuranStore()
    @State private var journal = Journal()
    /// Le lecteur de musique (onglet Écouter), prêt dès le lancement : les widgets peuvent le piloter.
    @State private var listen: ListenContext

    init() {
        _listen = State(initialValue: ListenContext())
    }

    var body: some Scene {
        WindowGroup {
            WirdRootView()
                .environment(store)
                .environment(journal)
                .listenEnvironment(listen)
                .tint(Color.primary)
                .task { await store.load() }
        }
    }
}

/// Cinq onglets : aujourd'hui (le journal), apprentissage, révision, cours, et Écouter (la musique).
struct WirdRootView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @Environment(\.scenePhase) private var phase
    @AppStorage("tab") private var tab = 0
    /// 0 = comme l'iPhone, 1 = clair, 2 = sombre.
    @AppStorage("theme") private var theme = 0
    /// Ouvert depuis le widget « Reprendre l'écoute » : on arrive sur Écouter.
    @State private var openedListen = false

    var body: some View {
        Group {
            if let error = store.error {
                ContentUnavailableView("Problème", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if !store.loaded {
                VStack(spacing: 14) {
                    WirdLogo(size: 120)
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { AppBackground() }
            } else {
                TabView(selection: $tab) {
                    NavigationStack { TodayView() }
                        .modifier(MiniPlayerInset(tab: 0))
                        .tabItem { Label("Aujourd’hui", systemImage: "checkmark.circle") }
                        .tag(0)
                    NavigationStack { LearningView() }
                        .modifier(MiniPlayerInset(tab: 1))
                        .tabItem { Label("Apprentissage", systemImage: "book.closed") }
                        .tag(1)
                    NavigationStack { RevisionView() }
                        .modifier(MiniPlayerInset(tab: 2))
                        .tabItem { Label("Révision", systemImage: "arrow.triangle.2.circlepath") }
                        .tag(2)
                    NavigationStack { CourseView() }
                        .modifier(MiniPlayerInset(tab: 3))
                        .tabItem { Label("Cours", systemImage: "person.2") }
                        .tag(3)
                    ListenTab()
                        .tabItem { Label("Écouter", systemImage: "headphones") }
                        .tag(ListenTab.tag)
                }
                .overlay(alignment: .top) { WirdBanner() }
                .modifier(ListenHost(selectedTab: tab))
                .onAppear { if !openedListen { tab = 0 } }
            }
        }
        .onOpenURL { url in
            if url.host == "listen" {
                openedListen = true
                tab = ListenTab.tag
            }
        }
        .onAppear(perform: applyTheme)
        .onChange(of: theme) { applyTheme() }
        // Widgets : mis à jour à chaque case cochée, à l'ouverture et quand on quitte l'app.
        .onChange(of: store.loaded) { connectWidgets() }
        .onChange(of: phase) {
            guard store.loaded else { return }
            if phase == .active { WidgetBridge.applyChecks(journal, store) }
            WidgetBridge.publish(journal, store)
        }
        .onAppear { connectWidgets() }
    }

    private func connectWidgets() {
        guard store.loaded else { return }
        let j = journal, s = store
        journal.onSave = { WidgetBridge.publish(j, s) }
        WidgetBridge.applyChecks(journal, store)
        WidgetBridge.publish(journal, store)
    }

    /// Clair, sombre ou comme l'iPhone : appliqué à toute l'app (fenêtres et feuilles).
    private func applyTheme() {
        let style: UIUserInterfaceStyle = theme == 1 ? .light : theme == 2 ? .dark : .unspecified
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}

/// D'où viennent les repères (pages, juz, hizb).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Wird") {
                    Text("Wird ne contient pas le texte du Coran : tu récites et tu lis dans ton propre Mushaf en papier. L’app sert seulement à suivre tes objectifs, tes révisions et ta progression.")
                }
                Section("Repères") {
                    Text("Pages (604) et juz du Mushaf de Médine, d’après les données du Complexe du Roi Fahd (KFGQPC, Hafs).")
                    Text("Quarts de hizb (rub‘) : données de Tanzil (tanzil.net), recalées sur les juz du Mushaf de Médine.")
                    Text("Noms des sourates et nombre de versets : Tanzil.")
                }
                Section("Design") {
                    Text("Logo dessiné pour Wird : un carnet avec un « و » et un marque-page rouge.")
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
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
