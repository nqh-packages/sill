import SwiftUI
import UIKit
import StreamProtocol

// The tactile deck's keycaps and the keyboard's accessory bar (Slice 1, the tactile rebuild).
// The look is sculpted dark hardware — keycap gradient, top specular rim, a 2.5 pt shadow lip and
// 1.5 pt of press travel — never Liquid Glass. The engine underneath is unchanged: esc, tab and the
// arrows are held keys (HeldCap, as the old key row's), the four modifiers latch the same way, and
// every key goes out through the caller's `send` (`StreamClient.sendFromKeyRow` keeps the sprite as
// a key row's key does). Slice 0's contract (TactileTokens, TactileLED, TactileHaptics,
// TactileSurfaceShape, .tactileSurface/.tactileButton) arrives with Wave 2's merge.

// MARK: - Keycap

/// One sculpted cap of the tactile deck: a physical dark keycap with a top specular rim, a 2.5 pt
/// shadow lip under its bottom edge, 1.5 pt of press travel (the cap slides down over the lip, a
/// small scale with it), and a recessed LED in the top-right corner while `ledColor` is set — lit
/// for a latched modifier, dark otherwise.
///
/// `onHoldChange` is told as a finger's press on the cap begins and ends (esc, tab and the arrows:
/// their key is down on the Mac from the touch to the release, HeldCap); caps that act on their tap
/// alone (the modifiers, the dismiss key) leave it nil. A `.keyPress` haptic ticks on every press's
/// begin — the cap's own click — so a modifier's tap plays its `.modifierLatch`/`.modifierRelease`
/// cue on top of the mechanical click, as a real latching switch does.
struct TactileKeycap: View {
    enum Label {
        /// The cap's legend as text ("esc", "⇥").
        case text(String)
        /// An unenclosed SF Symbol name ("arrow.left", "keyboard.chevron.compact.down"): the cap's
        /// sculpted body is the enclosure, so never a .circle/.square variant.
        case symbol(String)
    }

    let label: Label
    let accessibilityLabel: String
    var ledColor: Color? = nil
    var isLit: Bool = false
    var minHeight: CGFloat = 42
    var onHoldChange: ((Bool) -> Void)? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            legend
        }
        .buttonStyle(KeycapStyle(ledColor: ledColor, isLit: isLit, minHeight: minHeight,
                                 onHoldChange: onHoldChange))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    @ViewBuilder private var legend: some View {
        switch label {
        case .text(let title):
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

/// The cap's sculpted face and press physics: gradient face over a stationary shadow lip, the whole
/// cap (legend, rims, LED) travelling 1.5 pt down and 0.97 in on press, `.keyPress` on the touch.
private struct KeycapStyle: ButtonStyle {
    let ledColor: Color?
    let isLit: Bool
    let minHeight: CGFloat
    let onHoldChange: ((Bool) -> Void)?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }
    /// Downward travel while pressed: the cap slides over its own shadow lip.
    private let travel: CGFloat = 1.5
    /// The shadow lip showing under the cap's bottom edge at rest.
    private let lip: CGFloat = 2.5

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(isLit ? (ledColor ?? TactileTokens.ledAmber) : TactileTokens.textPrimary)
            .background(
                ZStack {
                    // The shadow lip stays put; the face slides down over it on press.
                    shape
                        .fill(TactileTokens.specularRimBottom.opacity(0.7))
                        .offset(y: lip)
                    shape
                        .fill(LinearGradient(colors: [TactileTokens.keycapTop, TactileTokens.keycapPressed],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            shape.strokeBorder(
                                LinearGradient(colors: [TactileTokens.specularRimTop,
                                                        TactileTokens.specularRimBottom.opacity(0.4)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1))
                        .offset(y: pressed ? travel : 0)
                }
            )
            .overlay(alignment: .topTrailing) {
                if let ledColor {
                    TactileLED(isOn: isLit, color: ledColor)
                        .padding(4)
                }
            }
            .contentShape(shape)
            .offset(y: pressed ? travel : 0)
            .scaleEffect(pressed ? 0.97 : 1, anchor: .center)
            .animation(.snappy(duration: 0.12), value: pressed)
            .onChange(of: pressed) { _, now in
                if now { TactileHaptics.play(.keyPress) }
                onHoldChange?(now)
            }
    }
}

// MARK: - Key rows

/// A sculpted row of the deck's caps. `.deckSix` is the six keys a Mac needs that a software
/// keyboard does not offer — [esc] [⇥] [⌃] [⌥] [⌘] [⇧] — flexible width, sharing the row evenly.
/// `.compactWithArrows` is the four latching modifiers plus the four arrows at a fixed compact
/// size, for the keyboard's accessory bar; a horizontal or vertical swipe across the arrow cluster
/// is the matching arrow's tap. Esc, tab and the arrows are held keys (HeldCap): down on the touch,
/// up on the lift, so the Mac repeats them; the modifiers latch for the next key or click and show
/// it on their LED. `isHidden` flipping true (under another row, the deck stowed) or the row leaving
/// the screen releases a held key at once, as the old key row's did.
struct TactileKeycapRow: View {
    enum LayoutStyle { case deckSix, compactWithArrows }

    let style: LayoutStyle
    @Binding var latched: KeyModifiers
    let send: (InputEvent) -> Void
    var isHidden: Bool = false

    /// Escape, tab or an arrow held down (HeldCap): its key is down on the Mac until the finger leaves.
    @State private var heldCap = HeldCap()

    var body: some View {
        Group {
            switch style {
            case .deckSix: deckSix
            case .compactWithArrows: compactWithArrows
            }
        }
        .onChange(of: isHidden) { _, now in if now { releaseAll() } }
        .onDisappear(perform: releaseAll)
    }

    /// The cap height and (compact only) fixed cap width for this layout.
    private var capHeight: CGFloat { style == .deckSix ? 42 : 38 }
    private var capWidth: CGFloat? { style == .deckSix ? nil : 44 }

    private var deckSix: some View {
        HStack(spacing: 6) {
            heldKey(label: .text("esc"), usage: HIDKey.escape, name: "Escape")
            heldKey(label: .text("⇥"), usage: HIDKey.tab, name: "Tab")
            modifier(.control, symbol: "control", name: "Control")
            modifier(.option, symbol: "option", name: "Option")
            modifier(.command, symbol: "command", name: "Command")
            modifier(.shift, symbol: "shift", name: "Shift")
        }
    }

    private var compactWithArrows: some View {
        HStack(spacing: 6) {
            modifier(.control, symbol: "control", name: "Control")
            modifier(.option, symbol: "option", name: "Option")
            modifier(.command, symbol: "command", name: "Command")
            modifier(.shift, symbol: "shift", name: "Shift")
            arrows
        }
    }

    /// The four arrows, each its own held cap and together a swipe pad: a flick across the cluster
    /// is the flicked direction's whole press, so an arrow can be stroked without aiming.
    private var arrows: some View {
        HStack(spacing: 4) {
            heldKey(label: .symbol("arrow.left"), usage: HIDKey.leftArrow, name: "Left arrow")
            heldKey(label: .symbol("arrow.down"), usage: HIDKey.downArrow, name: "Down arrow")
            heldKey(label: .symbol("arrow.up"), usage: HIDKey.upArrow, name: "Up arrow")
            heldKey(label: .symbol("arrow.right"), usage: HIDKey.rightArrow, name: "Right arrow")
        }
        .highPriorityGesture(arrowSwipe)
    }

    /// A flick across the arrow cluster: the dominant direction's arrow pressed once, carrying the
    /// latch and spending it. Past its distance the swipe owns the touches, so no cap also taps.
    private var arrowSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let t = value.translation
                let usage: UInt16 = abs(t.width) >= abs(t.height)
                    ? (t.width < 0 ? HIDKey.leftArrow : HIDKey.rightArrow)
                    : (t.height < 0 ? HIDKey.upArrow : HIDKey.downArrow)
                press(usage)
                TactileHaptics.play(.tick)
            }
    }

    private func heldKey(label: TactileKeycap.Label, usage: UInt16, name: String) -> some View {
        TactileKeycap(label: label, accessibilityLabel: name, minHeight: capHeight,
                      onHoldChange: { touch(usage, down: $0) },
                      onTap: { activate(usage) })
            .frame(width: capWidth)
    }

    /// A latching modifier: lit on its LED until something uses it or it is tapped again.
    private func modifier(_ flag: KeyModifiers, symbol: String, name: String) -> some View {
        let on = latched.contains(flag)
        return TactileKeycap(label: .symbol(symbol),
                             accessibilityLabel: on ? "\(name), held. Tap to release."
                                                    : "\(name), hold for the next key",
                             ledColor: TactileTokens.ledAmber, isLit: on, minHeight: capHeight,
                             onTap: { toggle(flag) })
            .frame(width: capWidth)
    }

    // MARK: Keys, as the old key row sent them

    /// A finger landed on escape, tab or an arrow, or left it (HeldCap): its key down with what is
    /// latched, which is spent, or its key up.
    private func touch(_ usage: UInt16, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard down else { heldCap.touchUp(usage, at: now).forEach(send); return }
        let events = heldCap.touchDown(usage, latched: latched, at: now)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }

    /// A held cap's action: nothing after a finger's touch (its key went down and up with it), the up
    /// of a press whose end was not told yet, or — activated with no touch (VoiceOver, Switch Control,
    /// Voice Control, a keyboard) — the whole press at once.
    private func activate(_ usage: UInt16) {
        let events = heldCap.activated(usage, latched: latched, at: ProcessInfo.processInfo.systemUptime)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }

    /// A tap on esc, tab, an arrow or a swipe's arrow: down and up, carrying whatever is latched, and
    /// the latch is spent — ⌥→ is one tap on opt then a flick right.
    private func press(_ usage: UInt16) {
        KeyChord.press(usage, with: latched).forEach(send)
        latched = []
    }

    /// A modifier tapped: it latches for the next key or click, or unlatches if it was held.
    private func toggle(_ flag: KeyModifiers) {
        let wasOn = latched.contains(flag)
        latched.formSymmetricDifference(flag)
        TactileHaptics.play(wasOn ? .modifierRelease : .modifierLatch)
    }

    /// The cap down comes up: the row hidden or gone from the screen, after which no release comes.
    private func releaseAll() {
        heldCap.releaseAll().forEach(send)
    }
}

// MARK: - Keyboard accessory host

/// The keyboard accessory bar's state, observed in place: `update(latched:)` writes here and the
/// hosted bar re-renders, so the input view is built once and never rebuilt — no reloadInputViews
/// churn, and no detached-from-the-window hosting controller.
private final class TactileAccessoryModel: ObservableObject {
    @Published var latched: KeyModifiers
    /// A modifier the bar toggled, written back to the caller's own binding.
    let apply: (KeyModifiers) -> Void
    let send: (InputEvent) -> Void
    let onDismiss: () -> Void

    init(latched: KeyModifiers, apply: @escaping (KeyModifiers) -> Void,
         send: @escaping (InputEvent) -> Void, onDismiss: @escaping () -> Void) {
        self.latched = latched
        self.apply = apply
        self.send = send
        self.onDismiss = onDismiss
    }
}

// MARK: - Tactile Arrow Joystick

/// A physical thumbstick keycap sitting in the accessory bar's arrow slot:
/// - Drag left/right/up/down directly on the cap to fire USB HID arrows (respecting latched
///   modifiers) with visual puck deflection, directional LED glow, and hold-to-repeat.
/// - Tap the cap to expand into the full four-arrow sculpted keycap cluster inline.
private struct TactileArrowJoystick: View {
    @Binding var latched: KeyModifiers
    let send: (InputEvent) -> Void
    let onExpand: () -> Void

    private enum Direction: Equatable {
        case left, right, up, down

        var usage: UInt16 {
            switch self {
            case .left: return HIDKey.leftArrow
            case .right: return HIDKey.rightArrow
            case .up: return HIDKey.upArrow
            case .down: return HIDKey.downArrow
            }
        }
    }

    @State private var puckOffset: CGSize = .zero
    @State private var activeDirection: Direction? = nil
    @State private var dragged = false
    @State private var repeatTask: Task<Void, Never>? = nil

    private static let activationDistance: CGFloat = 10
    private static let maxTravel: CGFloat = 7.5
    private static let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        ZStack {
            // Recessed anodized joystick well
            Self.shape
                .fill(
                    LinearGradient(
                        colors: [TactileTokens.trackpadWell, TactileTokens.chassisDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Self.shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            activeDirection != nil ? TactileTokens.ledBlue.opacity(0.65) : TactileTokens.specularRimTop,
                            TactileTokens.specularRimBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: activeDirection != nil ? 1.0 : 0.75
                )

            // Four cardinal micro-indicators
            chevron("chevron.up", active: activeDirection == .up)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 2.5)
            chevron("chevron.down", active: activeDirection == .down)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 2.5)
            chevron("chevron.left", active: activeDirection == .left)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 3.5)
            chevron("chevron.right", active: activeDirection == .right)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 3.5)

            // Machined thumbstick puck
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            activeDirection != nil ? TactileTokens.ledBlue.opacity(0.45) : TactileTokens.keycapTop,
                            TactileTokens.keycapPressed
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            activeDirection != nil ? TactileTokens.ledBlue.opacity(0.85) : TactileTokens.specularRimTop,
                            lineWidth: 0.75
                        )
                }
                .frame(width: 16, height: 16)
                .shadow(color: activeDirection != nil ? TactileTokens.ledBlue.opacity(0.45) : .black.opacity(0.55),
                        radius: activeDirection != nil ? 4 : 2, y: 1)
                .offset(puckOffset)
                .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.72), value: puckOffset)
        }
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
        .contentShape(Self.shape)
        .gesture(joystickGesture)
        .onDisappear { stopRepeating() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arrow joystick")
        .accessibilityHint("Drag in any direction for arrow keys, or tap to expand individual arrow keys")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onExpand() }
    }

    private func chevron(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 6.5, weight: .bold))
            .foregroundStyle(active ? TactileTokens.ledBlue : TactileTokens.textSecondary.opacity(0.55))
    }

    private var joystickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let dist = hypot(dx, dy)

                if dist > 0 {
                    let scale = min(dist, Self.maxTravel) / dist
                    puckOffset = CGSize(width: dx * scale, height: dy * scale)
                } else {
                    puckOffset = .zero
                }

                guard dist >= Self.activationDistance else { return }
                dragged = true
                let dir: Direction = abs(dx) >= abs(dy)
                    ? (dx < 0 ? .left : .right)
                    : (dy < 0 ? .up : .down)
                if dir != activeDirection {
                    activeDirection = dir
                    fire(dir)
                    startRepeating(dir)
                }
            }
            .onEnded { _ in
                let wasDrag = dragged
                stopRepeating()
                activeDirection = nil
                puckOffset = .zero
                dragged = false
                if !wasDrag {
                    TactileHaptics.play(.detent)
                    onExpand()
                }
            }
    }

    private func fire(_ dir: Direction) {
        KeyChord.press(dir.usage, with: latched).forEach(send)
        if !latched.isEmpty { latched = [] }
        TactileHaptics.play(.tick)
    }

    private func startRepeating(_ dir: Direction) {
        stopRepeating()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            while !Task.isCancelled {
                fire(dir)
                try? await Task.sleep(for: .milliseconds(85))
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// The bar itself: fits cleanly across the full width with zero horizontal scroll so joystick
/// swipes never conflict with scrolling. Default: [esc] [⇥] [⌃] [⌥] [⌘] [⇧] [joystick] [dismiss].
/// Tapping the joystick expands inline into [⌃] [⌥] [⌘] [⇧] [←] [↓] [↑] [→] [collapse].
private struct TactileAccessoryBar: View {
    @ObservedObject var model: TactileAccessoryModel
    /// Escape, tab, and expanded arrow keys held down (HeldCap).
    @State private var heldCap = HeldCap()
    @State private var arrowsExpanded = false

    /// The row's latch binding: bar writes go to the model (so `update` and the bar agree) and
    /// through `apply` to the caller's binding.
    private var latched: Binding<KeyModifiers> {
        Binding(get: { model.latched },
                set: { model.latched = $0; model.apply($0) })
    }

    var body: some View {
        HStack(spacing: 5) {
            if !arrowsExpanded {
                heldKey(label: .text("esc"), usage: HIDKey.escape, name: "Escape")
                heldKey(label: .text("⇥"), usage: HIDKey.tab, name: "Tab")
            }
            modifier(.control, symbol: "control", name: "Control")
            modifier(.option, symbol: "option", name: "Option")
            modifier(.command, symbol: "command", name: "Command")
            modifier(.shift, symbol: "shift", name: "Shift")
            if arrowsExpanded {
                heldKey(label: .symbol("arrow.left"), usage: HIDKey.leftArrow, name: "Left arrow")
                heldKey(label: .symbol("arrow.down"), usage: HIDKey.downArrow, name: "Down arrow")
                heldKey(label: .symbol("arrow.up"), usage: HIDKey.upArrow, name: "Up arrow")
                heldKey(label: .symbol("arrow.right"), usage: HIDKey.rightArrow, name: "Right arrow")
                TactileKeycap(label: .symbol("xmark"),
                              accessibilityLabel: "Collapse arrow keys", minHeight: 38) {
                    heldCap.releaseAll().forEach(model.send)
                    TactileHaptics.play(.detent)
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                        arrowsExpanded = false
                    }
                }
            } else {
                TactileArrowJoystick(latched: latched, send: model.send) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                        arrowsExpanded = true
                    }
                }
                TactileKeycap(label: .symbol("keyboard.chevron.compact.down"),
                              accessibilityLabel: "Hide keyboard", minHeight: 38,
                              onTap: model.onDismiss)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(TactileTokens.chassisDark)
        .onDisappear { heldCap.releaseAll().forEach(model.send) }
    }

    private func heldKey(label: TactileKeycap.Label, usage: UInt16, name: String) -> some View {
        TactileKeycap(label: label, accessibilityLabel: name, minHeight: 38,
                      onHoldChange: { touch(usage, down: $0) },
                      onTap: { activate(usage) })
    }

    private func modifier(_ flag: KeyModifiers, symbol: String, name: String) -> some View {
        let on = model.latched.contains(flag)
        return TactileKeycap(label: .symbol(symbol),
                             accessibilityLabel: on ? "\(name), held. Tap to release."
                                                    : "\(name), hold for the next key",
                             ledColor: TactileTokens.ledAmber, isLit: on, minHeight: 38) {
            let wasOn = model.latched.contains(flag)
            var next = model.latched
            next.formSymmetricDifference(flag)
            latched.wrappedValue = next
            TactileHaptics.play(wasOn ? .modifierRelease : .modifierLatch)
        }
    }

    private func touch(_ usage: UInt16, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard down else { heldCap.touchUp(usage, at: now).forEach(model.send); return }
        let events = heldCap.touchDown(usage, latched: model.latched, at: now)
        events.forEach(model.send)
        if HeldCap.spendsLatch(events) { latched.wrappedValue = [] }
    }

    private func activate(_ usage: UInt16) {
        let events = heldCap.activated(usage, latched: model.latched,
                                     at: ProcessInfo.processInfo.systemUptime)
        events.forEach(model.send)
        if HeldCap.spendsLatch(events) { latched.wrappedValue = [] }
    }
}

/// The software keyboard's tactile accessory bar, as a UIInputView to hand a text view's
/// `inputAccessoryView`: a keyboard-style input view that self-sizes to its 52 pt bar and hosts it
/// through a UIHostingController kept for the view's life. `update(latched:)` pushes the latest
/// modifier latch into the bar in place, so the accessory never goes through a reloadInputViews
/// rebuild — the view handed out is always the same one.
@MainActor
final class TactileKeyboardAccessoryHost {
    /// The input view to attach as `inputAccessoryView`.
    let view: UIView

    private let model: TactileAccessoryModel
    private let hostingController: UIHostingController<TactileAccessoryBar>

    init(latched: Binding<KeyModifiers>, send: @escaping (InputEvent) -> Void,
         onDismiss: @escaping () -> Void) {
        let model = TactileAccessoryModel(latched: latched.wrappedValue,
                                          apply: { latched.wrappedValue = $0 },
                                          send: send, onDismiss: onDismiss)
        self.model = model

        let hosting = UIHostingController(rootView: TactileAccessoryBar(model: model))
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = .intrinsicContentSize
        hostingController = hosting

        let input = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 52),
                                inputViewStyle: .keyboard)
        input.allowsSelfSizing = true
        input.backgroundColor = .clear
        input.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: input.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: input.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: input.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: input.bottomAnchor),
        ])
        view = input
    }

    /// The latest modifier latch, pushed into the hosted bar in place (no rebuild).
    func update(latched: KeyModifiers) {
        model.latched = latched
    }
}
