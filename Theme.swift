import SwiftUI
import UIKit

// MARK: - Liquid Glass (iOS 26), verre dépoli avant

extension View {
    func glass(_ radius: CGFloat = 24, interactive: Bool = false) -> some View {
        modifier(GlassStyle(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive))
    }

    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassStyle(shape: Capsule(), interactive: interactive))
    }

    func glassCircle() -> some View {
        modifier(GlassStyle(shape: Circle(), interactive: true))
    }
}

struct GlassStyle<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05), .white.opacity(0.18)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Le gros bouton : une lumière d'étoile, avec un léger halo.
struct BigButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onStar)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Star.fill))
            .shadow(color: Color.starGlow, radius: configuration.isPressed ? 6 : 16)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Couleurs de l'espace

extension Color {
    /// La lumière des étoiles : un blanc bleuté, pour les accents.
    static let star = Color(red: 0.76, green: 0.84, blue: 1.0)
    /// Le texte posé sur la lumière d'étoile : bleu nuit.
    static let onStar = Color(red: 0.03, green: 0.06, blue: 0.16)
    static let starGlow = Color(red: 0.45, green: 0.6, blue: 1.0).opacity(0.45)
    /// Le fond de l'espace.
    static let night = Color(red: 0.012, green: 0.024, blue: 0.063)
}

enum Star {
    static let fill = LinearGradient(colors: [.white, Color(red: 0.78, green: 0.85, blue: 1.0)],
                                     startPoint: .top, endPoint: .bottom)
}

// MARK: - Le ciel et le logo (dessinés pour Wird, rangés dans theme.json)

@MainActor
enum ThemeArt {
    private struct File: Decodable {
        let sky: String
        let logo: String
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "theme", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    private static func image(_ base64: String?, scale: CGFloat) -> UIImage? {
        guard let base64, let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data, scale: scale)
    }

    static let sky = image(file?.sky, scale: 3)
    static let logo = image(file?.logo, scale: 2)
}

/// Le logo de Wird : un « و » lumineux, entouré d'une orbite.
struct WirdLogo: View {
    var size: CGFloat = 56

    var body: some View {
        if let img = ThemeArt.logo {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text("و").font(.system(size: size * 0.8, weight: .bold)).foregroundStyle(Color.star)
                .frame(width: size, height: size)
        }
    }
}

/// Le fond : le ciel de nuit qui dérive très lentement, des étoiles qui scintillent,
/// et de temps en temps une étoile filante.
struct AppBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.night
                if let sky = ThemeArt.sky {
                    Image(uiImage: sky)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width * 1.12, height: geo.size.height * 1.12)
                        .offset(x: drift ? -geo.size.width * 0.04 : geo.size.width * 0.04,
                                y: drift ? geo.size.height * 0.02 : -geo.size.height * 0.02)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                if !reduceMotion {
                    Twinkles()
                }
                // Un voile en haut et en bas pour que le texte reste lisible.
                LinearGradient(colors: [Color.night.opacity(0.55), .clear, .clear, Color.night.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 90).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Des étoiles qui s'allument et s'éteignent doucement, et une étoile filante de temps en temps.
struct Twinkles: View {
    private struct Twinkle {
        let x: Double, y: Double, size: Double, speed: Double, phase: Double, bright: Bool
    }

    private static let stars: [Twinkle] = {
        var rng = SeededRandom(seed: 7)
        return (0..<55).map { i in
            Twinkle(x: rng.next(), y: rng.next(), size: 0.8 + rng.next() * 1.8,
                    speed: 0.6 + rng.next() * 1.6, phase: rng.next() * 6.28, bright: i % 9 == 0)
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for s in Self.stars {
                    let glow = 0.5 + 0.5 * sin(t * s.speed + s.phase)
                    let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
                    let r = s.size * (s.bright ? 1.6 : 1) * (0.7 + 0.5 * glow)
                    let alpha = (s.bright ? 0.35 : 0.15) + (s.bright ? 0.65 : 0.6) * glow * glow
                    // halo
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 4, y: p.y - r * 4, width: r * 8, height: r * 8)),
                             with: .radialGradient(Gradient(colors: [Color.star.opacity(alpha * 0.35), .clear]),
                                                   center: p, startRadius: 0, endRadius: r * 4))
                    // cœur
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                             with: .color(.white.opacity(alpha)))
                    // aigrettes des plus brillantes
                    if s.bright {
                        let l = r * 5 * glow
                        var cross = Path()
                        cross.move(to: CGPoint(x: p.x - l, y: p.y)); cross.addLine(to: CGPoint(x: p.x + l, y: p.y))
                        cross.move(to: CGPoint(x: p.x, y: p.y - l)); cross.addLine(to: CGPoint(x: p.x, y: p.y + l))
                        ctx.stroke(cross, with: .color(.white.opacity(alpha * 0.5)), lineWidth: 0.6)
                    }
                }
                shootingStar(ctx, size, t)
            }
        }
    }

    /// Toutes les 11 secondes, une étoile filante traverse le ciel en 1,2 s.
    private func shootingStar(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let period = 11.0, duration = 1.2
        let cycle = floor(t / period)
        let local = t - cycle * period
        guard local < duration else { return }
        var rng = SeededRandom(seed: UInt64(abs(Int(cycle)) % 100_000 + 1))
        let start = CGPoint(x: size.width * (0.15 + rng.next() * 0.7), y: size.height * (0.05 + rng.next() * 0.35))
        let angle = 0.45 + rng.next() * 0.35
        let length = size.width * 0.55
        let k = local / duration
        let head = CGPoint(x: start.x + cos(angle) * length * k, y: start.y + sin(angle) * length * k)
        let tail = CGPoint(x: head.x - cos(angle) * size.width * 0.18, y: head.y - sin(angle) * size.width * 0.18)
        let fade = sin(k * .pi)
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.85 * fade)]),
                                               startPoint: tail, endPoint: head),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 1.6, y: head.y - 1.6, width: 3.2, height: 3.2)),
                 with: .color(.white.opacity(fade)))
    }
}

/// Un hasard toujours le même (les étoiles restent à leur place).
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 1_000_000) / 1_000_000
    }
}

/// Un anneau de progression.
struct Ring: View {
    let value: Double
    var color: Color = .star
    var width: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.1), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

/// Petit message en haut de l'écran (« C'est noté »…).
struct Banner: View {
    @Environment(Journal.self) private var journal

    var body: some View {
        Group {
            if let message = journal.message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .glassCapsule()
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.2))
                        if journal.message == message { journal.message = nil }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: journal.message)
        .allowsHitTesting(false)
    }
}

// MARK: - Dates

enum Dates {
    static let fr = Locale(identifier: "fr_FR")

    /// « vendredi 6 novembre ».
    static func long(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(fr))
    }

    /// « sam. 7 nov. ».
    static func dayShort(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr))
    }

    /// « mars 2031 ».
    static func monthYear(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).year().locale(fr))
    }

    /// « 6 nov. 2026 ».
    static func short(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year().locale(fr))
    }

    /// La date de l'Hégire : « 15 joumada al oula 1448 ».
    static func hijri(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.locale = fr
        f.dateFormat = "d MMMM y"
        return f.string(from: d)
    }
}
