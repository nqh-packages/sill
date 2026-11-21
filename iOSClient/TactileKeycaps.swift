import SwiftUI
import UIKit
import StreamProtocol

// Unified neutral-graphite keycaps, the four-way arrow joystick, and the single shared
// `TactileCommandBar` used above both the iOS keyboard and the phone Control Deck trackpad.

// MARK: - Keycap

struct TactileKeycap: View {
    enum Label {
        case text(String)
        /// Unenclosed SF Symbol name only (the keycap body is the enclosure).
        case symbol(String)
    }

    let label: Label
    let accessibilityLabel: String
    var ledColor: Color? = nil
    var isLit: Bool = false
    var minHeight: CGFloat = 36
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
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .medium))
        }
    }
}

private struct KeycapStyle: ButtonStyle {
    let ledColor: Color?
    let isLit: Bool
    let minHeight: CGFloat
    let onHoldChange: ((Bool) -> Void)?

    private let shape = RoundedRectangle(cornerRadius: TactileRadius.keycap, style: .continuous)
    private let travel: CGFloat = 1.0
    private let lip: CGFloat = 1.5

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(isLit ? (ledColor ?? TactileTokens.ledAmber) : TactileTokens.textPrimary)
            .background(
                ZStack {
                    shape
                        .fill(TactileTokens.keycapLip)
                        .offset(y: lip)
                    shape
                        .fill(LinearGradient(colors: [TactileTokens.keycapTop, TactileTokens.keycapPressed],
                                             startPoint: .top, endPoint: .bottom))
                        .tactileSpecularBorder(.rounded(TactileRadius.keycap), lineWidth: 0.6)
                        .offset(y: pressed ? travel : 0)
                }
            )
            .overlay(alignment: .topTrailing) {
                if let ledColor {
                    TactileLED(isOn: isLit, color: ledColor)
                        .padding(4)
                        .offset(y: pressed ? travel : 0)
                }
            }
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(TactileMotion.keyPress, value: pressed)
            .onChange(of: pressed) { _, down in
                if down { TactileHaptics.play(.keyPress) }
                onHoldChange?(down)
            }
    }
}

// MARK: - Compact 6-key row (iPad floating trackpad)

struct TactileKeycapRow: View {
    enum LayoutStyle { case deckSix }

    let style: LayoutStyle
    @Binding var latched: KeyModifiers
    let send: (InputEvent) -> Void
    var isHidden: Bool = false

    @State private var heldCap = HeldCap()

    var body: some View {
        HStack(spacing: 5) {
            heldKey(label: .text("esc"), usage: HIDKey.escape, name: "Escape")
            heldKey(label: .text("⇥"), usage: HIDKey.tab, name: "Tab")
            modifier(.control, symbol: "control", name: "Control")
            modifier(.option, symbol: "option", name: "Option")
            modifier(.command, symbol: "command", name: "Command")
            modifier(.shift, symbol: "shift", name: "Shift")
        }
        .onChange(of: isHidden) { _, now in if now { releaseAll() } }
        .onDisappear(perform: releaseAll)
    }

    private func heldKey(label: TactileKeycap.Label, usage: UInt16, name: String) -> some View {
        TactileKeycap(label: label, accessibilityLabel: name, minHeight: 38,
                      onHoldChange: { touch(usage, down: $0) },
                      onTap: { activate(usage) })
    }

    private func modifier(_ flag: KeyModifiers, symbol: String, name: String) -> some View {
        let on = latched.contains(flag)
        return TactileKeycap(label: .symbol(symbol),
                             accessibilityLabel: on ? "\(name), held. Tap to release."
                                                    : "\(name), hold for the next key",
                             ledColor: TactileTokens.ledAmber, isLit: on, minHeight: 38,
                             onTap: { toggle(flag) })
    }

    private func touch(_ usage: UInt16, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard down else { heldCap.touchUp(usage, at: now).forEach(send); return }
        let events = heldCap.touchDown(usage, latched: latched, at: now)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }

    private func activate(_ usage: UInt16) {
        let events = heldCap.activated(usage, latched: latched, at: ProcessInfo.processInfo.systemUptime)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }

    private func toggle(_ flag: KeyModifiers) {
        let wasOn = latched.contains(flag)
        latched.formSymmetricDifference(flag)
        TactileHaptics.play(wasOn ? .modifierRelease : .modifierLatch)
    }

    private func releaseAll() {
        heldCap.releaseAll().forEach(send)
    }
}

// MARK: - Arrow Joystick

/// Recessed neutral-graphite four-way thumbstick sitting in the command bar's arrow slot.
/// Dragging fires and auto-repeats USB HID arrows (respecting latched modifiers); tapping expands
/// the four individual sculpted arrow keys inline.
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
    private static let maxTravel: CGFloat = 7.0
    private static let shape = RoundedRectangle(cornerRadius: TactileRadius.keycap, style: .continuous)

    var body: some View {
        ZStack {
            Self.shape
                .fill(
                    LinearGradient(
                        colors: [TactileTokens.trackpadWell, TactileTokens.chassisDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .tactileSpecularBorder(.rounded(TactileRadius.keycap),
                                       lineWidth: activeDirection != nil ? 0.9 : 0.6,
                                       active: activeDirection != nil)

            chevron("chevron.up", active: activeDirection == .up)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
            chevron("chevron.down", active: activeDirection == .down)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 2)
            chevron("chevron.left", active: activeDirection == .left)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 3)
            chevron("chevron.right", active: activeDirection == .right)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 3)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            activeDirection != nil ? TactileTokens.keycapActive : TactileTokens.keycapTop,
                            TactileTokens.keycapPressed
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .tactileSpecularBorder(.circle, lineWidth: 0.65, active: activeDirection != nil)
                .frame(width: 15, height: 15)
                .shadow(color: TactileTokens.ambientShadow, radius: 2, y: 1)
                .offset(puckOffset)
                .animation(TactileMotion.joystickSnap, value: puckOffset)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
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
            .foregroundStyle(active ? TactileTokens.textPrimary : TactileTokens.textSecondary.opacity(0.6))
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

// MARK: - Shared Command Bar (Keyboard + Trackpad)

/// Single floating Liquid Glass command bar shared identically by the iOS keyboard accessory
/// and the phone Control Deck trackpad, so switching Keyboard <-> Trackpad keeps every keycap
/// at the exact same position with zero duplicated UI.
struct TactileCommandBar: View {
    enum Mode {
        case keyboard(onSwitchToTrackpad: (() -> Void)?)
        case trackpad(onSwitchToKeyboard: (() -> Void)?)
    }

    let mode: Mode
    @Binding var latched: KeyModifiers
    let send: (InputEvent) -> Void
    let onDismiss: () -> Void

    @State private var heldCap = HeldCap()
    @State private var arrowsExpanded = false

    static let barHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 4) {
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
                              accessibilityLabel: "Collapse arrow keys", minHeight: 36) {
                    heldCap.releaseAll().forEach(send)
                    TactileHaptics.play(.detent)
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                        arrowsExpanded = false
                    }
                }
            } else {
                TactileArrowJoystick(latched: $latched, send: send) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                        arrowsExpanded = true
                    }
                }
                modeSwapKey
                dismissKey
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .tactileSurface(.floatingChrome, shape: .rounded(20))
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(height: Self.barHeight)
        .background(Color.clear)
        .onDisappear { heldCap.releaseAll().forEach(send) }
    }

    @ViewBuilder private var modeSwapKey: some View {
        switch mode {
        case .keyboard(let switchToTrackpad):
            if let switchToTrackpad {
                TactileKeycap(label: .symbol("rectangle.and.hand.point.up.left"),
                              accessibilityLabel: "Switch to trackpad", minHeight: 36) {
                    heldCap.releaseAll().forEach(send)
                    switchToTrackpad()
                }
            }
        case .trackpad(let switchToKeyboard):
            if let switchToKeyboard {
                TactileKeycap(label: .symbol("keyboard"),
                              accessibilityLabel: "Switch to keyboard", minHeight: 36) {
                    heldCap.releaseAll().forEach(send)
                    switchToKeyboard()
                }
            }
        }
    }

    private var dismissKey: some View {
        let isKeyboard: Bool = {
            if case .keyboard = mode { return true }
            return false
        }()
        return TactileKeycap(
            label: .symbol(isKeyboard ? "keyboard.chevron.compact.down" : "chevron.down"),
            accessibilityLabel: isKeyboard ? "Hide keyboard" : "Stow trackpad",
            minHeight: 36
        ) {
            heldCap.releaseAll().forEach(send)
            onDismiss()
        }
    }

    private func heldKey(label: TactileKeycap.Label, usage: UInt16, name: String) -> some View {
        TactileKeycap(label: label, accessibilityLabel: name, minHeight: 36,
                      onHoldChange: { touch(usage, down: $0) },
                      onTap: { activate(usage) })
    }

    private func modifier(_ flag: KeyModifiers, symbol: String, name: String) -> some View {
        let on = latched.contains(flag)
        return TactileKeycap(label: .symbol(symbol),
                             accessibilityLabel: on ? "\(name), held. Tap to release."
                                                    : "\(name), hold for the next key",
                             ledColor: TactileTokens.ledAmber, isLit: on, minHeight: 36) {
            let wasOn = latched.contains(flag)
            latched.formSymmetricDifference(flag)
            TactileHaptics.play(wasOn ? .modifierRelease : .modifierLatch)
        }
    }

    private func touch(_ usage: UInt16, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard down else { heldCap.touchUp(usage, at: now).forEach(send); return }
        let events = heldCap.touchDown(usage, latched: latched, at: now)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }

    private func activate(_ usage: UInt16) {
        let events = heldCap.activated(usage, latched: latched,
                                     at: ProcessInfo.processInfo.systemUptime)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }
}

// MARK: - Keyboard accessory host

private final class TactileAccessoryModel: ObservableObject {
    @Published var latched: KeyModifiers
    let apply: (KeyModifiers) -> Void
    let send: (InputEvent) -> Void
    let onSwitchToTrackpad: (() -> Void)?
    let onDismiss: () -> Void

    init(latched: KeyModifiers, apply: @escaping (KeyModifiers) -> Void,
         send: @escaping (InputEvent) -> Void,
         onSwitchToTrackpad: (() -> Void)? = nil,
         onDismiss: @escaping () -> Void) {
        self.latched = latched
        self.apply = apply
        self.send = send
        self.onSwitchToTrackpad = onSwitchToTrackpad
        self.onDismiss = onDismiss
    }
}

private struct TactileAccessoryHostView: View {
    @ObservedObject var model: TactileAccessoryModel

    private var latched: Binding<KeyModifiers> {
        Binding(get: { model.latched },
                set: { model.latched = $0; model.apply($0) })
    }

    var body: some View {
        TactileCommandBar(
            mode: .keyboard(onSwitchToTrackpad: model.onSwitchToTrackpad),
            latched: latched,
            send: model.send,
            onDismiss: model.onDismiss
        )
    }
}

/// Hosts `TactileCommandBar` inside a transparent self-sizing `UIInputView` for `inputAccessoryView`.
/// `update(latched:)` mutates observed state in place so `reloadInputViews` is never needed.
@MainActor
final class TactileKeyboardAccessoryHost {
    let view: UIView

    private let model: TactileAccessoryModel
    private let hostingController: UIHostingController<TactileAccessoryHostView>

    init(latched: Binding<KeyModifiers>, send: @escaping (InputEvent) -> Void,
         onSwitchToTrackpad: (() -> Void)? = nil,
         onDismiss: @escaping () -> Void) {
        let model = TactileAccessoryModel(latched: latched.wrappedValue,
                                          apply: { latched.wrappedValue = $0 },
                                          send: send,
                                          onSwitchToTrackpad: onSwitchToTrackpad,
                                          onDismiss: onDismiss)
        self.model = model

        let hosting = UIHostingController(rootView: TactileAccessoryHostView(model: model))
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = .intrinsicContentSize
        hostingController = hosting

        let input = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: TactileCommandBar.barHeight),
                                inputViewStyle: .default)
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

    func update(latched: KeyModifiers) {
        model.latched = latched
    }
}
