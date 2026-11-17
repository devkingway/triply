import SwiftUI
import UIKit

/// Triply's design system: brand colours, shapes and shared styling.
enum Theme {
    /// Brand teal for text, icons and tints. Brighter in dark mode so it stays readable on black.
    static let teal = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.22, green: 0.80, blue: 0.78, alpha: 1)
            : UIColor(red: 0.0, green: 0.62, blue: 0.60, alpha: 1)
    })
    static let blue = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.62, blue: 1.0, alpha: 1)
            : UIColor(red: 0.13, green: 0.42, blue: 0.86, alpha: 1)
    })

    /// Fixed brand colours for filled backgrounds (white text sits on these in both modes).
    private static let gradientTeal = Color(red: 0.0, green: 0.62, blue: 0.60)
    private static let gradientBlue = Color(red: 0.13, green: 0.42, blue: 0.86)

    static let brandGradient = LinearGradient(colors: [gradientTeal, gradientBlue], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardRadius: CGFloat = 22
}

extension View {
    /// Standard rounded card on the grouped background.
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    /// See-through frosted glass card with a faint tint and thin border (trip cards, budget card).
    /// Without a tint it uses the trip's colour (teal to blue).
    func glassCard(tint: Color? = nil, secondTint: Color? = nil) -> some View {
        modifier(GlassCard(customTint: tint, customSecondTint: secondTint))
    }

    /// Frosted strip behind a button pinned to the bottom of the screen: content scrolling
    /// underneath is blurred, fading in at the top edge.
    func bottomBarBlur() -> some View {
        self
            .padding(.top, 20)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.35)],
                                         startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .bottom)
            }
    }

    /// Colours a trip's pages: teal to blue, drafts included (same as its card).
    func tripAccent(_ trip: Trip) -> some View {
        self
            .environment(\.tripAccent, trip.accent)
            .environment(\.tripAccent2, trip.accent2)
            .tint(trip.accent)
    }
}

extension EnvironmentValues {
    @Entry var tripAccent: Color = Theme.teal
    @Entry var tripAccent2: Color = Theme.blue
}

extension Trip {
    /// The trip card's colours: teal to blue, the same for drafts and planned trips.
    var accent: Color { Theme.teal }
    var accent2: Color { Theme.blue }
}

/// Light mode gets stronger tints so cards stay colourful on the pale background.
private struct GlassCard: ViewModifier {
    let customTint: Color?
    let customSecondTint: Color?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.tripAccent) private var accent
    @Environment(\.tripAccent2) private var accent2

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        let light = scheme == .light
        let tint = customTint ?? accent
        let secondTint = customSecondTint ?? accent2
        return content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: [tint.opacity(light ? 0.38 : 0.16),
                                                       secondTint.opacity(light ? 0.24 : 0.08)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay(shape.stroke(tint.opacity(light ? 0.6 : 0.35), lineWidth: 1))
    }
}

/// A small coloured label, e.g. "In 23 days" or "Day 2 of 4".
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .white
    var background: AnyShapeStyle = AnyShapeStyle(Color.black.opacity(0.45))

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.app(.caption, .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Toasts

struct Toast: Equatable, Identifiable {
    enum Style { case success, info, warning }
    let id = UUID()
    let message: String
    var systemImage: String = "checkmark.circle.fill"
    var style: Style = .success

    var color: Color {
        switch style {
        case .success: Theme.teal
        case .info: Theme.blue
        case .warning: .orange
        }
    }
}

/// Shows short confirmation messages ("Saved to Day 2") above everything, including sheets.
@Observable
final class Toaster {
    static let shared = Toaster()
    var current: Toast?

    func show(_ message: String, systemImage: String = "checkmark.circle.fill", style: Toast.Style = .success) {
        current = Toast(message: message, systemImage: systemImage, style: style)
        switch style {
        case .warning: Haptics.warning()
        default: Haptics.success()
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.app(.title3))
                .foregroundStyle(toast.color)
            Text(toast.message)
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(toast.color.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

// MARK: - Ticket shape (boarding pass)

/// A rounded rectangle with two half-circle notches, like a torn boarding pass.
struct TicketShape: Shape {
    /// Where the notches sit, measured from the top.
    var notchY: CGFloat
    var notchRadius: CGFloat = 12
    var cornerRadius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let y = min(max(notchY, notchRadius), rect.height - notchRadius)
        path.addEllipse(in: CGRect(x: rect.minX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        path.addEllipse(in: CGRect(x: rect.maxX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        return path
    }
}

/// Dashed line drawn across the ticket between the notches.
struct DashedDivider: View {
    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.quaternary)
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}
