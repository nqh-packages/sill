import SwiftUI
import UIKit

private extension Color {
    static func sillSRGB(_ rgb: UInt32, opacity: Double = 1.0) -> Color {
        Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

public enum TactileTokens {
    public static let canvasBlack = Color.sillSRGB(0x000000)
    public static let chassisDark = Color.sillSRGB(0x111317)
    public static let chassisRaised = Color.sillSRGB(0x1A1D24)
    public static let keycapTop = Color.sillSRGB(0x262A33)
    public static let keycapPressed = Color.sillSRGB(0x181B21)
    public static let trackpadWell = Color.sillSRGB(0x0C0E12)
    public static let specularRimTop = Color.sillSRGB(0xFFFFFF, opacity: 0.16)
    public static let specularRimBottom = Color.sillSRGB(0xFFFFFF, opacity: 0.03)
    public static let ledAmber = Color.sillSRGB(0xFF9F0A)
    public static let ledEmerald = Color.sillSRGB(0x30D158)
    public static let ledCyan = Color.sillSRGB(0x64D2FF)
    public static let ledCrimson = Color.sillSRGB(0xFF453A)
    public static let ledBlue = Color.sillSRGB(0x9BB7FF)
    public static let textPrimary = Color.sillSRGB(0xEEF0F3)
    public static let textSecondary = Color.sillSRGB(0xA4ABB5)
}

public enum TactileSurfaceShape: Equatable, Hashable, Sendable {
    case capsule
    case circle
    case rounded(CGFloat)
}

public enum TactileSurfaceRole: Equatable, Hashable, Sendable {
    case floatingChrome
    case interactiveChrome
    case recessedHardware
}

public enum TactileButtonRole: Equatable, Hashable, Sendable {
    case secondary
    case prominent(Color)
}

struct TactileLED: View {
    let isOn: Bool
    let color: Color
    var diameter: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? color : TactileTokens.chassisDark)
            if isOn {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.55), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: diameter * 0.65
                        )
                    )
            } else {
                Circle()
                    .fill(color.opacity(0.16))
            }
            Circle()
                .strokeBorder(
                    isOn ? Color.white.opacity(0.28) : TactileTokens.specularRimTop.opacity(0.6),
                    lineWidth: 0.5
                )
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: isOn ? color.opacity(0.65) : .clear, radius: diameter * 0.65, x: 0, y: 0)
        .accessibilityHidden(true)
    }
}

@MainActor
enum TactileHaptics {
    private static let detentGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let tickGenerator = UISelectionFeedbackGenerator()
    private static let keyPressGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let latchGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let releaseGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let warningGenerator = UINotificationFeedbackGenerator()

    static func play(_ cue: HapticCue) {
        switch cue {
        case .detent:
            detentGenerator.impactOccurred(intensity: 0.85)
        case .tick:
            tickGenerator.selectionChanged()
        case .keyPress:
            keyPressGenerator.impactOccurred(intensity: 0.75)
        case .modifierLatch:
            latchGenerator.impactOccurred(intensity: 0.9)
        case .modifierRelease:
            releaseGenerator.impactOccurred(intensity: 0.65)
        case .warning:
            warningGenerator.notificationOccurred(.warning)
        }
    }
}

struct TactileGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct TactileSpecularRim: View {
    let shape: TactileSurfaceShape
    let lineWidth: CGFloat

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [TactileTokens.specularRimTop, TactileTokens.specularRimBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous)
                .strokeBorder(gradient, lineWidth: lineWidth)
        case .circle:
            Circle()
                .strokeBorder(gradient, lineWidth: lineWidth)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(gradient, lineWidth: lineWidth)
        }
    }
}

private struct TactileShapeFill: View {
    let shape: TactileSurfaceShape
    let color: Color

    var body: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous).fill(color)
        case .circle:
            Circle().fill(color)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
        }
    }
}

private struct TactileMaterialFill: View {
    let shape: TactileSurfaceShape

    var body: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous).fill(.ultraThinMaterial)
        case .circle:
            Circle().fill(.ultraThinMaterial)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
        }
    }
}

private struct TactileSurfaceModifier: ViewModifier {
    let role: TactileSurfaceRole
    let shape: TactileSurfaceShape

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .recessedHardware:
            content
                .background {
                    TactileShapeFill(shape: shape, color: TactileTokens.chassisRaised)
                }
                .overlay {
                    TactileSpecularRim(shape: shape, lineWidth: 0.75)
                        .allowsHitTesting(false)
                }

        case .floatingChrome:
            if #available(iOS 26, *) {
                applyGlass(to: content, interactive: false)
            } else {
                applyLegacyChrome(to: content)
            }

        case .interactiveChrome:
            if #available(iOS 26, *) {
                applyGlass(to: content, interactive: true)
            } else {
                applyLegacyChrome(to: content)
            }
        }
    }

    @available(iOS 26, *)
    @ViewBuilder
    private func applyGlass(to content: Content, interactive: Bool) -> some View {
        let glass: Glass = interactive ? .regular.interactive() : .regular
        switch shape {
        case .capsule:
            content.glassEffect(glass, in: .capsule)
        case .circle:
            content.glassEffect(glass, in: .circle)
        case .rounded(let radius):
            content.glassEffect(glass, in: .rect(cornerRadius: radius))
        }
    }

    private func applyLegacyChrome(to content: Content) -> some View {
        content
            .background {
                ZStack {
                    TactileMaterialFill(shape: shape)
                    TactileShapeFill(shape: shape, color: TactileTokens.chassisDark.opacity(0.68))
                }
            }
            .overlay {
                TactileSpecularRim(shape: shape, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.38), radius: 10, x: 0, y: 4)
    }
}

struct MachinedTactileButtonStyle: ButtonStyle {
    let role: TactileButtonRole
    let shape: TactileSurfaceShape

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        applyContentShape(
            to: configuration.label
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .foregroundStyle(foregroundColor)
                .background {
                    TactileShapeFill(shape: shape, color: backgroundColor(pressed: pressed))
                }
                .overlay {
                    TactileSpecularRim(shape: shape, lineWidth: 0.75)
                        .opacity(pressed ? 0.45 : 1.0)
                        .allowsHitTesting(false)
                }
        )
        .shadow(
            color: Color.black.opacity(pressed ? 0.12 : 0.34),
            radius: pressed ? 1.5 : 4,
            x: 0,
            y: pressed ? 0.5 : 2
        )
        .scaleEffect(pressed ? 0.965 : 1.0)
        .offset(y: pressed ? 0.75 : 0)
        .animation(.spring(response: 0.16, dampingFraction: 0.82), value: pressed)
    }

    private var horizontalPadding: CGFloat {
        switch shape {
        case .circle: return 10
        case .capsule, .rounded: return 12
        }
    }

    private var verticalPadding: CGFloat {
        switch shape {
        case .circle: return 10
        case .capsule, .rounded: return 8
        }
    }

    @ViewBuilder
    private func applyContentShape<V: View>(to view: V) -> some View {
        switch shape {
        case .capsule:
            view.contentShape(Capsule(style: .continuous))
        case .circle:
            view.contentShape(Circle())
        case .rounded(let radius):
            view.contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .secondary:
            return TactileTokens.textPrimary
        case .prominent:
            return Color.white
        }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        switch role {
        case .secondary:
            return pressed ? TactileTokens.keycapPressed : TactileTokens.keycapTop
        case .prominent(let color):
            return pressed ? color.opacity(0.82) : color
        }
    }
}

private struct TactileButtonModifier: ViewModifier {
    let role: TactileButtonRole
    let shape: TactileSurfaceShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            applyGlassButton(to: content)
        } else {
            content.buttonStyle(MachinedTactileButtonStyle(role: role, shape: shape))
        }
    }

    @available(iOS 26, *)
    @ViewBuilder
    private func applyGlassButton(to content: Content) -> some View {
        switch role {
        case .secondary:
            applyBorderShape(to: content.buttonStyle(.glass))
        case .prominent(let color):
            applyBorderShape(to: content.buttonStyle(.glassProminent).tint(color))
        }
    }

    @available(iOS 26, *)
    @ViewBuilder
    private func applyBorderShape<V: View>(to view: V) -> some View {
        switch shape {
        case .capsule:
            view.buttonBorderShape(.capsule)
        case .circle:
            view.buttonBorderShape(.circle)
        case .rounded(let radius):
            view.buttonBorderShape(.roundedRectangle(radius: radius))
        }
    }
}

extension View {
    func tactileSurface(_ role: TactileSurfaceRole, shape: TactileSurfaceShape) -> some View {
        modifier(TactileSurfaceModifier(role: role, shape: shape))
    }

    func tactileButton(_ role: TactileButtonRole, shape: TactileSurfaceShape) -> some View {
        modifier(TactileButtonModifier(role: role, shape: shape))
    }

    func tactileRecessedButton(_ role: TactileButtonRole, shape: TactileSurfaceShape) -> some View {
        buttonStyle(MachinedTactileButtonStyle(role: role, shape: shape))
    }

    @ViewBuilder
    func tactileBottomBar<BarContent: View>(
        isVisible: Bool,
        @ViewBuilder content: @escaping () -> BarContent
    ) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: .bottom) {
                if isVisible {
                    content()
                }
            }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                if isVisible {
                    content()
                }
            }
        }
    }
}
