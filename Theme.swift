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

/// Le gros bouton doré.
struct BigButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onGold)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Gold.fill))
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
            .shadow(color: Color.goldShadow, radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - L'or de Wird

extension Color {
    /// Or lisible : plus profond en thème clair, plus lumineux en sombre.
    static let gold = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.87, green: 0.72, blue: 0.40, alpha: 1)
                                      : UIColor(red: 0.62, green: 0.46, blue: 0.15, alpha: 1)
    })
    /// Le texte posé sur l'or.
    static let onGold = Color(red: 0.11, green: 0.08, blue: 0.02)
    static let goldShadow = Color(red: 0.55, green: 0.38, blue: 0.08).opacity(0.35)
}

enum Gold {
    /// Feuille d'or : reflets clairs et sombres en diagonale.
    static let fill = LinearGradient(
        colors: [Color(red: 0.96, green: 0.84, blue: 0.52), Color(red: 0.78, green: 0.58, blue: 0.22),
                 Color(red: 0.97, green: 0.86, blue: 0.56), Color(red: 0.66, green: 0.47, blue: 0.16)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Motifs et logo (dessinés pour Wird, rangés dans theme.json)

@MainActor
enum ThemeArt {
    private struct File: Decodable {
        let patternDark: String
        let patternLight: String
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

    static let patternDark = image(file?.patternDark, scale: 2.2)
    static let patternLight = image(file?.patternLight, scale: 2.2)
    static let logo = image(file?.logo, scale: 2)
}

/// Le logo de Wird : le « و » doré posé sur le W.
struct WirdLogo: View {
    var size: CGFloat = 56

    var body: some View {
        if let img = ThemeArt.logo {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text("و").font(.system(size: size * 0.8, weight: .bold)).foregroundStyle(Color.gold)
                .frame(width: size, height: size)
        }
    }
}

/// Le fond : de la calligraphie gravée, noire sur noir ou ivoire sur ivoire.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            (dark ? Color(red: 0.043, green: 0.043, blue: 0.047) : Color(red: 0.965, green: 0.957, blue: 0.94))
            if let img = dark ? ThemeArt.patternDark : ThemeArt.patternLight {
                Image(uiImage: img)
                    .resizable(resizingMode: .tile)
            }
            // Un voile pour que le texte reste lisible.
            LinearGradient(colors: [(dark ? Color.black : Color.white).opacity(dark ? 0.35 : 0.45), .clear,
                                    (dark ? Color.black : Color.white).opacity(dark ? 0.25 : 0.3)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Un anneau de progression.
struct Ring: View {
    let value: Double
    var color: Color = .gold
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
