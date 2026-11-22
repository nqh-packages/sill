import SwiftUI
import UIKit

// Single source of truth (SSOT) for Sill's iOS/iPadOS design system.
// Every color, corner radius, motion curve, surface material (native iOS 26/27 Liquid Glass with
// matched iPadOS 17 anodized fallback), hardware bezel, app icon badge, LED, and haptic lives here.

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

// MARK: - Tokens

public enum TactileTokens {
    // Neutral obsidian & anodized graphite surfaces (zero blue/purple cast).
    public static let canvasBlack = Color.sillSRGB(0x000000)
    public static let trackpadWell = Color.sillSRGB(0x0D0D0E)
    public static let chassisDark = Color.sillSRGB(0x141415)
    public static let chassisRaised = Color.sillSRGB(0x1C1C1E)
    public static let controlRaised = Color.sillSRGB(0x2C2C2E)
    public static let keycapTop = Color.sillSRGB(0x3A3A3D)
    public static let keycapPressed = Color.sillSRGB(0x2B2B2E)
    public static let keycapActive = Color.sillSRGB(0x7A7A80)
    public static let keycapLip = Color.sillSRGB(0x000000, opacity: 0.45)

    // Borders, specular rims & badges.
    public static let specularRimTop = Color.sillSRGB(0xFFFFFF, opacity: 0.16)
    public static let specularRimBottom = Color.sillSRGB(0xFFFFFF, opacity: 0.03)
    public static let activeRimTop = Color.sillSRGB(0xFFFFFF, opacity: 0.45)
    public static let selectionRim = Color.sillSRGB(0xFFFFFF, opacity: 0.75)
    public static let badgeFill = Color.sillSRGB(0xFFFFFF, opacity: 0.14)
    public static let recessShadowTop = Color.sillSRGB(0x000000, opacity: 0.65)
    public static let recessShadowMid = Color.sillSRGB(0x000000, opacity: 0.20)
    public static let ambientShadow = Color.sillSRGB(0x000000, opacity: 0.42)

    // Semantic LEDs & accents.
    public static let ledAmber = Color.sillSRGB(0xFF9F0A)
    public static let ledEmerald = Color.sillSRGB(0x30D158)
    public static let ledCyan = Color.sillSRGB(0x64D2FF)
    public static let ledCrimson = Color.sillSRGB(0xFF453A)
    public static let ledBlue = Color.sillSRGB(0x0A84FF)

    // Typography inks.
    public static let textPrimary = Color.sillSRGB(0xF2F2F7)
    public static let textBarLabel = Color.sillSRGB(0xAEAEB2)
    public static let textSecondary = Color.sillSRGB(0x8E8E93)
}

public enum TactileRadius {
    public static let micro: CGFloat = 6
    public static let icon: CGFloat = 8
    public static let keycap: CGFloat = 8.5
    public static let screen: CGFloat = 9
    public static let pill: CGFloat = 10
    public static let bezel: CGFloat = 12
    public static let card: CGFloat = 14
    public static let cardLarge: CGFloat = 20
    public static let trackpad: CGFloat = 26
}

public enum TactileMotion {
    public static let keyPress = Animation.easeOut(duration: 0.08)
    public static let buttonPress = Animation.spring(response: 0.16, dampingFraction: 0.82)
    public static let joystickSnap = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.72)
    public static let barMorph = Animation.spring(response: 0.24, dampingFraction: 0.85)

    public static func deck(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.84)
    }

    public static func paletteDock(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 1.0)
    }
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

// MARK: - Core Hardware Primitives

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

/// Reusable app icon badge: renders the Mac's icon or a neutral graphite rounded tile.
struct TactileAppIcon: View {
    let image: UIImage?
    var fallbackSymbol: String? = nil
    var fallbackLetters: String? = nil
    var size: CGFloat = 24
    var cornerRadius: CGFloat = TactileRadius.micro
    var dropShadow: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let fallbackSymbol {
                ZStack {
                    shape.fill(TactileTokens.controlRaised)
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(TactileTokens.textPrimary)
                }
            } else if let fallbackLetters {
                ZStack {
                    shape.fill(TactileTokens.controlRaised)
                    Text(fallbackLetters)
                        .font(.system(size: max(9, size * 0.42), weight: .semibold))
                        .foregroundStyle(TactileTokens.textPrimary)
                }
            } else {
                shape.fill(TactileTokens.controlRaised)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .shadow(color: dropShadow ? TactileTokens.ambientShadow : .clear, radius: 3, y: 1)
    }
}

/// Unified machined display bezel used by Connect Mac cards, Switcher Desktop cards, and Switcher
/// window thumbnail cards. Hosts scaledToFill artwork inside a fixed-bound overlay before clipping
/// so tall portrait frames can never bleed outside the bezel.
struct TactileDisplayBezel: View {
    let image: UIImage?
    var placeholderSymbol: String = "display"
    var placeholderSize: CGFloat = 28
    var aspectRatio: CGFloat? = nil
    var height: CGFloat? = nil
    var outerRadius: CGFloat = TactileRadius.bezel
    var innerRadius: CGFloat = TactileRadius.screen
    var bezelPadding: CGFloat = 0
    var cornerIcon: UIImage? = nil
    var led: (isOn: Bool, color: Color)? = nil

    var body: some View {
        let screenShape = RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
        let screen = screenShape
            .fill(TactileTokens.trackpadWell)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                } else {
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: placeholderSize, weight: .thin))
                        .foregroundStyle(TactileTokens.textSecondary.opacity(0.6))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let cornerIcon {
                    TactileAppIcon(image: cornerIcon, size: 24, cornerRadius: TactileRadius.micro, dropShadow: true)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let led {
                    TactileLED(isOn: led.isOn, color: led.color)
                        .padding(7)
                }
            }
            .clipShape(screenShape)
            .tactileSpecularBorder(.rounded(innerRadius), lineWidth: 0.5)

        if bezelPadding > 0 {
            let outerShape = RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
            outerShape
                .fill(TactileTokens.chassisDark)
                .modifier(BezelFrameModifier(aspectRatio: aspectRatio, height: height))
                .overlay {
                    screen.padding(bezelPadding)
                }
                .tactileSpecularBorder(.rounded(outerRadius), lineWidth: 0.75)
        } else {
            screen
                .modifier(BezelFrameModifier(aspectRatio: aspectRatio, height: height))
        }
    }
}

private struct BezelFrameModifier: ViewModifier {
    let aspectRatio: CGFloat?
    let height: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let aspectRatio {
            content.aspectRatio(aspectRatio, contentMode: .fit)
        } else if let height {
            content.frame(maxWidth: .infinity).frame(height: height)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Consistent section heading across Switcher and Connect grids.
struct TactileSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TactileTokens.textSecondary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Surfaces & Buttons (iOS 26+ Liquid Glass / iPadOS 17 Fallback Seam)

private struct TactileSpecularRim: View {
    let shape: TactileSurfaceShape
    let lineWidth: CGFloat
    var active: Bool = false

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [active ? TactileTokens.activeRimTop : TactileTokens.specularRimTop,
                     TactileTokens.specularRimBottom],
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

private struct TactileSelectionOutline: View {
    let shape: TactileSurfaceShape
    let lineWidth: CGFloat

    var body: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous)
                .strokeBorder(TactileTokens.selectionRim, lineWidth: lineWidth)
        case .circle:
            Circle()
                .strokeBorder(TactileTokens.selectionRim, lineWidth: lineWidth)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(TactileTokens.selectionRim, lineWidth: lineWidth)
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
                    TactileShapeFill(shape: shape, color: TactileTokens.chassisDark.opacity(0.72))
                }
            }
            .overlay {
                TactileSpecularRim(shape: shape, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: TactileTokens.ambientShadow, radius: 10, x: 0, y: 4)
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
            color: TactileTokens.ambientShadow.opacity(pressed ? 0.3 : 0.8),
            radius: pressed ? 1.5 : 4,
            x: 0,
            y: pressed ? 0.5 : 2
        )
        .scaleEffect(pressed ? 0.965 : 1.0)
        .offset(y: pressed ? 0.75 : 0)
        .animation(TactileMotion.buttonPress, value: pressed)
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
            return TactileTokens.textPrimary
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

/// Subtle physical press feedback for hardware cards (Mac cards, Desktop card, Window cards).
struct TactileCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(TactileMotion.buttonPress, value: configuration.isPressed)
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

    func tactileSpecularBorder(_ shape: TactileSurfaceShape, lineWidth: CGFloat = 0.75, active: Bool = false) -> some View {
        overlay {
            TactileSpecularRim(shape: shape, lineWidth: lineWidth, active: active)
                .allowsHitTesting(false)
        }
    }

    func tactileSelectionRim(_ isSelected: Bool, shape: TactileSurfaceShape, lineWidth: CGFloat = 1.5, inset: CGFloat = 0) -> some View {
        overlay {
            if isSelected {
                TactileSelectionOutline(shape: shape, lineWidth: lineWidth)
                    .padding(inset)
                    .allowsHitTesting(false)
            }
        }
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
