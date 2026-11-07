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

struct BigButtonStyle: ButtonStyle {
    var color: Color = .brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onBrand)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(color.gradient))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Fond doux : un voile émeraude en haut, une touche dorée en bas.
struct AppBackground: View {
    var tint: Color = .brand
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
    }
}

/// Un anneau de progression.
struct Ring: View {
    let value: Double
    var color: Color = .brand
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
