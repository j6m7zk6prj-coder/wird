import SwiftUI
import UniformTypeIdentifiers

// MARK: - Écouter : le lecteur de musique, intégré à Wird

/// Tout ce dont le lecteur a besoin, créé une seule fois au lancement de Wird.
@MainActor
final class ListenContext {
    let settings: AppSettings
    let library: Library
    let player: Player
    let ui: UIState

    init() {
        settings = AppSettings()
        library = Library()
        player = Player(library: library, settings: settings)
        ui = UIState()
        // Les boutons des widgets « Reprendre l'écoute » pilotent ce lecteur.
        let player = player
        ListenControl.toggle = { player.widgetToggle() }
        ListenControl.next = { player.next() }
        // Wird : le son tel quel, sans effet.
        if player.effect != .original { player.setEffect(.original) }
    }
}

extension View {
    /// Donne accès au lecteur, à la bibliothèque et aux réglages de musique.
    func listenEnvironment(_ c: ListenContext) -> some View {
        environment(c.library)
            .environment(c.player)
            .environment(c.settings)
            .environment(c.ui)
    }
}

/// L'onglet Écouter.
struct ListenTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack { HomeView() }
            .modifier(MiniPlayerInset(tab: ListenTab.tag, always: true))
            .tint(settings.tint)
            .modifier(SystemAppearanceReader())
    }

    static let tag = 4
}

/// Découvrir, ouvert en plein écran depuis Écouter.
struct DiscoverScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack { FeedView(onClose: { dismiss() }) }
    }
}

/// Ce que le lecteur ajoute à toute l'app : lecteur plein écran, feuilles, import, Collection.
struct ListenHost: ViewModifier {
    let selectedTab: Int
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(UIState.self) private var ui
    @Environment(\.scenePhase) private var phase
    /// La Collection est chargée (cachée) peu après le lancement, pour s'ouvrir sans attendre.
    @State private var shelfMounted = false
    /// Le mini-lecteur s'agrandit en lecteur plein écran (et s'y referme en glissant vers le bas).
    @Namespace private var playerZoom

    func body(content: Content) -> some View {
        @Bindable var ui = ui
        content
            .overlay(alignment: .top) { ListenBanner() }
            .modifier(PlayerPresenter(isPresented: $ui.showPlayer, namespace: playerZoom, sourceID: "miniPlayer-\(selectedTab)"))
            .environment(\.playerZoomNamespace, playerZoom)
            .sheet(item: $ui.editing) { target in
                ArtworkEditor(trackID: target.id)
            }
            .overlay {
                if shelfMounted {
                    ShelfView(visible: ui.showShelf, onClose: { ui.showShelf = false })
                        .environment(\.colorScheme, .dark)
                        .opacity(ui.showShelf ? 1 : 0)
                        .allowsHitTesting(ui.showShelf)
                        .accessibilityHidden(!ui.showShelf)
                        .animation(.smooth(duration: 0.32), value: ui.showShelf)
                }
            }
            .onChange(of: ui.showShelf) { _, shown in
                if shown { shelfMounted = true }
            }
            .sheet(item: $ui.editingInfo) { target in
                TrackInfoEditor(trackID: target.id)
            }
            .sheet(item: $ui.addToPlaylist) { target in
                AddToPlaylistSheet(target: target)
            }
            .fileImporter(isPresented: $ui.importing, allowedContentTypes: [.audio, .lrc], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await library.importFiles(urls) }
                }
            }
            .task {
                if settings.autoImport { await library.scanInbox() }
                player.publishWidget()
                // La Collection 3D n'est préparée que si tu as de la musique, et sans ralentir l'ouverture.
                guard !library.tracks.isEmpty else { return }
                try? await Task.sleep(for: .seconds(2.5))
                let playing = player.currentID.flatMap { library.track($0) }?.albumKey
                let start = library.albums.firstIndex { $0.id == playing } ?? 0
                await ShelfSceneController.warmUp(library: library, settings: settings, start: start)
                shelfMounted = true
                if settings.lockScreenAnimation {
                    try? await Task.sleep(for: .seconds(6))
                    player.warmUpcomingLockArtwork()
                    let recent = library.tracks
                        .filter { library.motion($0) != nil }
                        .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
                        .prefix(12)
                    for t in recent {
                        if let m = library.motion(t) {
                            LockScreenArtwork.shared.warm(source: m.url, kind: m.kind)
                        }
                    }
                }
            }
            .onChange(of: phase) { _, newPhase in
                if newPhase == .active, settings.autoImport { Task { await library.scanInbox() } }
                if newPhase == .active { player.warmUpcomingLockArtwork() }
                // En quittant l'app : le widget garde l'endroit exact où tu t'es arrêté.
                if newPhase != .active { player.publishWidget(force: true) }
            }
            .onChange(of: library.artworkRevision) { _, _ in
                player.updateNowPlaying()
            }
    }
}

/// Place le mini-lecteur au-dessus de la barre d'onglets.
/// Dans les autres onglets de Wird, il n'apparaît que quand un morceau est chargé.
struct MiniPlayerInset: ViewModifier {
    var tab = 0
    var always = false
    @Environment(UIState.self) private var ui
    @Environment(Player.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if always || player.currentID != nil {
                MiniPlayer(zoomID: "miniPlayer-\(tab)") { ui.showPlayer = true }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: player.currentID)
    }
}

/// Bandeau de confirmation du lecteur, en haut de l'écran.
struct ListenBanner: View {
    @Environment(Library.self) private var library

    var body: some View {
        Group {
            if library.isImporting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Import en cours…").font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .glassCapsule()
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let message = library.message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .glassCapsule()
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if library.message == message { library.message = nil }
                    }
            }
        }
        .animation(.smooth(duration: 0.3), value: library.message)
        .animation(.smooth(duration: 0.3), value: library.isImporting)
        .allowsHitTesting(false)
    }
}

/// Lit si l'iPhone est en mode clair ou sombre (pour le mode Auto du lecteur).
struct SystemAppearanceReader: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .onAppear { update() }
            .onChange(of: scheme) { _, _ in update() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in update() }
    }

    private func update() {
        let light = scheme == .light
        if settings.systemIsLight != light { settings.systemIsLight = light }
    }
}

// MARK: - Ouverture du lecteur façon Musique

private struct PlayerZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var playerZoomNamespace: Namespace.ID? {
        get { self[PlayerZoomNamespaceKey.self] }
        set { self[PlayerZoomNamespaceKey.self] = newValue }
    }
}

/// Le mini-lecteur sert de point de départ : le lecteur en sort en s'agrandissant.
struct PlayerZoomSource: ViewModifier {
    var id = "miniPlayer-0"
    @Environment(\.playerZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        } else {
            content
        }
    }
}

/// iOS 18 et plus : le lecteur sort du mini-lecteur et y rentre quand tu le glisses vers le bas.
/// Avant iOS 18 : feuille classique.
struct PlayerPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let namespace: Namespace.ID
    var sourceID = "miniPlayer-0"

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.fullScreenCover(isPresented: $isPresented) {
                NowPlayingView()
                    .environment(\.colorScheme, .dark)
                    .overlay(alignment: .top) { Grabber() }
                    .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                NowPlayingView()
                    .environment(\.colorScheme, .dark)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(40)
                    .presentationBackground(.black)
            }
        }
    }
}

/// La petite barre en haut du lecteur : on le referme en glissant vers le bas.
struct Grabber: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.4))
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }
}
