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

/// Le gros bouton : plein, noir en thème clair, blanc en sombre.
struct BigButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onBrand)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Color.primary))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Le logo de Wird : un carnet noir (blanc en sombre) avec un « و », et un marque-page rouge.
struct WirdLogo: View {
    var size: CGFloat = 56

    var body: some View {
        let w = size * 0.62, h = size * 0.80
        ZStack(alignment: .top) {
            // Marque-page qui dépasse en bas.
            Bookmark()
                .fill(Color(red: 0.84, green: 0.16, blue: 0.16))
                .frame(width: size * 0.09, height: h * 0.55)
                .offset(x: w * 0.20, y: h * 0.62)
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(Color.primary)
                .frame(width: w, height: h)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.onBrand.opacity(0.25))
                        .frame(width: max(1, size * 0.012))
                        .padding(.leading, w * 0.11)
                }
                .overlay {
                    Text("و")
                        .font(.system(size: size * 0.36, weight: .bold))
                        .foregroundStyle(Color.onBrand)
                        .offset(x: w * 0.05, y: -h * 0.03)
                }
        }
        .frame(width: size, height: size, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// Un ruban de marque-page avec une encoche en V.
struct Bookmark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.width * 0.6))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Fond simple, sans motif.
struct AppBackground: View {
    var body: some View {
        Color(.systemGroupedBackground).ignoresSafeArea()
    }
}

/// Un anneau de progression.
struct Ring: View {
    let value: Double
    var color: Color = .primary
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
