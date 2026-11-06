import SwiftUI
import UIKit

// MARK: - Le lecteur : pages qui se tournent comme un vrai livre

/// Ouvre le Mushaf à une sourate (ou à la dernière page lue).
struct MushafReader: View {
    let start: ReadingPosition
    @Environment(QuranStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var current: ReadingPosition
    @State private var pageLabel = ""
    @State private var chrome = true

    init(start: ReadingPosition) {
        self.start = start
        _current = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            Color(Mushaf.paper).ignoresSafeArea()
            GeometryReader { geo in
                PageCurlView(store: store, start: start, size: geo.size) { pos, label in
                    current = pos
                    pageLabel = label
                    store.last = pos
                } onTap: {
                    withAnimation(.easeInOut(duration: 0.25)) { chrome.toggle() }
                }
                .ignoresSafeArea(edges: .bottom)
            }

            if chrome {
                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        Spacer()
                        if let s = store.surah(current.surah) {
                            VStack(spacing: 0) {
                                Text(s.tr).font(.subheadline.weight(.semibold))
                                Text("Verset \(current.ayah)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    Spacer()
                    Text(pageLabel)
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
                .foregroundStyle(Color(Mushaf.ink))
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chrome)
        .preferredColorScheme(.light)
    }
}

/// Le UIPageViewController d'iOS en mode « page qui se tourne » (comme Livres).
struct PageCurlView: UIViewControllerRepresentable {
    let store: QuranStore
    let start: ReadingPosition
    let size: CGSize
    var onPage: (ReadingPosition, String) -> Void
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        // Reliure à droite, comme un Mushaf : on tourne les pages de gauche à droite.
        let vc = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                      options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.max.rawValue)])
        vc.isDoubleSided = false
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        vc.view.backgroundColor = Mushaf.paper
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.cancelsTouchesInView = false
        vc.view.addGestureRecognizer(tap)
        context.coordinator.open(vc, at: start, size: size)
        return vc
    }

    func updateUIViewController(_ vc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        // L'écran a changé de taille (rotation…) : on refait la mise en page à la même place.
        if context.coordinator.size != size, size.width > 0 {
            let pos = context.coordinator.position
            context.coordinator.cache = [:]
            context.coordinator.open(vc, at: pos, size: size)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView
        var size: CGSize = .zero
        var cache: [Int: [Mushaf.Page]] = [:]
        var position = ReadingPosition(surah: 1, ayah: 1)

        init(_ parent: PageCurlView) { self.parent = parent }

        /// Marges de la page : le texte ne touche jamais les bords.
        private var textSize: CGSize {
            CGSize(width: max(100, size.width - 2 * MushafPageController.sideMargin),
                   height: max(100, size.height - MushafPageController.topMargin - MushafPageController.bottomMargin))
        }

        @MainActor func pages(_ surah: Int) -> [Mushaf.Page] {
            if let p = cache[surah] { return p }
            guard let s = parent.store.surah(surah) else { return [] }
            let p = Mushaf.paginate(s, size: textSize, rules: parent.store.rules)
            cache[surah] = p
            return p
        }

        @MainActor func controller(_ page: Mushaf.Page) -> MushafPageController? {
            guard let s = parent.store.surah(page.surah) else { return nil }
            let count = pages(page.surah).count
            return MushafPageController(page: page, surah: s, pageCount: count, rules: parent.store.rules)
        }

        @MainActor func open(_ vc: UIPageViewController, at pos: ReadingPosition, size: CGSize) {
            self.size = size
            let list = pages(pos.surah)
            let page = list.last { $0.firstAyah <= pos.ayah } ?? list.first
            guard let page, let c = controller(page) else { return }
            vc.setViewControllers([c], direction: .forward, animated: false)
            report(page)
        }

        @MainActor private func report(_ page: Mushaf.Page) {
            let pos = ReadingPosition(surah: page.surah, ayah: page.firstAyah)
            position = pos
            let label = "Page \(page.index + 1) sur \(pages(page.surah).count)"
            let callback = parent.onPage
            // Après la mise à jour de l'écran (jamais pendant).
            DispatchQueue.main.async { callback(pos, label) }
        }

        @MainActor private func neighbour(of vc: UIViewController, step: Int) -> UIViewController? {
            guard let c = vc as? MushafPageController else { return nil }
            let list = pages(c.page.surah)
            let i = c.page.index + step
            if list.indices.contains(i) { return controller(list[i]) }
            // Fin de sourate : on passe à la suivante (ou on revient à la fin de la précédente).
            let next = c.page.surah + (step > 0 ? 1 : -1)
            guard (1...114).contains(next) else { return nil }
            let other = pages(next)
            guard let target = step > 0 ? other.first : other.last else { return nil }
            return controller(target)
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            MainActor.assumeIsolated { neighbour(of: vc, step: 1) }
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            MainActor.assumeIsolated { neighbour(of: vc, step: -1) }
        }

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            MainActor.assumeIsolated {
                guard completed, let c = pvc.viewControllers?.first as? MushafPageController else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                report(c.page)
            }
        }

        @objc func tapped() {
            MainActor.assumeIsolated { parent.onTap() }
        }
    }
}

/// Une page du Mushaf : papier, cadre fin, texte coloré selon le tajwid, numéro de page.
final class MushafPageController: UIViewController {
    static let sideMargin: CGFloat = 22
    static let topMargin: CGFloat = 70
    static let bottomMargin: CGFloat = 64

    let page: Mushaf.Page
    private let surah: Surah
    private let pageCount: Int
    private let rules: [String]

    init(page: Mushaf.Page, surah: Surah, pageCount: Int, rules: [String]) {
        self.page = page
        self.surah = surah
        self.pageCount = pageCount
        self.rules = rules
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Mushaf.paper

        // Léger dégradé vers la reliure (à droite), comme une vraie page.
        let shade = CAGradientLayer()
        shade.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.06).cgColor]
        shade.startPoint = CGPoint(x: 0.82, y: 0.5)
        shade.endPoint = CGPoint(x: 1, y: 0.5)
        shade.name = "shade"
        view.layer.addSublayer(shade)

        // Cadre doré fin.
        let frame = UIView()
        frame.translatesAutoresizingMaskIntoConstraints = false
        frame.layer.borderColor = Mushaf.ornament.withAlphaComponent(0.55).cgColor
        frame.layer.borderWidth = 1
        frame.layer.cornerRadius = 6
        frame.isUserInteractionEnabled = false
        view.addSubview(frame)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.attributedText = Mushaf.text(for: page, surah: surah, rules: rules, tajweed: true)
        view.addSubview(label)

        let number = UILabel()
        number.translatesAutoresizingMaskIntoConstraints = false
        number.text = (page.index + 1).arabicDigits
        number.font = Fonts.quran(17)
        number.textColor = Mushaf.ornament
        view.addSubview(number)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = surah.ar
        title.font = Fonts.quran(17)
        title.textColor = Mushaf.ornament
        view.addSubview(title)

        let m = Self.sideMargin
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -m),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.topMargin),
            frame.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: m - 10),
            frame.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(m - 10)),
            frame.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.topMargin - 12),
            frame.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(Self.bottomMargin - 14)),
            number.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            number.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(Self.bottomMargin - 46)),
            title.trailingAnchor.constraint(equalTo: frame.trailingAnchor),
            title.bottomAnchor.constraint(equalTo: frame.topAnchor, constant: -4)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first { $0.name == "shade" }?.frame = view.bounds
    }
}
