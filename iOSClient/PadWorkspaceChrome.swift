import SwiftUI
import UIKit
import StreamProtocol

/// The iPad's floating capsule (the tactile workspace's pad chrome): a slim capsule over the stream
/// edge — Liquid Glass on iPadOS 26, `TactileStyle`'s machined capsule on iPadOS 17 through the same
/// calls — that holds what the old bars held, for a 4:3 canvas the bars crowded: the three windows
/// front-most on the Mac, Apps, the Mac's menus, Aa, Keyboard, Trackpad, Controls and the tuck key.
///
/// Tucked (`CapsuleVisibility.tucked`), the whole capsule leaves the canvas: what stays is a 16×58
/// machined pull-tab on the trailing edge, tapped or pulled inward to bring it back.
///
/// What the capsule changes goes to `StreamWorkspaceState` as an action (`dispatch`); the menus'
/// open and close are actions too, so a hardware Escape or another modal can close them, and the
/// Mac's own answers (picking a window from a pill, Aa's scale) go to `StreamClient` as the bars'
/// did.
struct PadFloatingCapsule: View {
    @ObservedObject var client: StreamClient
    let state: StreamWorkspaceState
    @Binding var textScale: Double?
    var onTextScaleCommit: () -> Void = {}
    let dispatch: (StreamWorkspaceState.Action) -> Void

    /// The Mac menu trigger's open state (`MacMenuTrigger` is UIKit: SwiftUI's `Menu` cannot fetch
    /// a Mac menu lazily, so the capsule draws the key and the trigger sits on it, as
    /// `MacMenuButton` does).
    @State private var menusOpen = false
    /// Aa's inline detent pill under the capsule.
    @State private var scaleOpen = false

    /// The window pills the capsule shows: the three front-most on the Mac.
    private var recentWindows: [WindowInfo] { Array(client.orderedWindows.prefix(3)) }

    var body: some View {
        if state.capsule.isTucked {
            pullTab
        } else {
            capsule
        }
    }

    // MARK: Expanded

    private var capsule: some View {
        VStack(spacing: 8) {
            TactileGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    windowPills
                    capsuleButton("square.grid.2x2", label: "Apps", lit: false) {
                        dispatch(.openModal(.switcher(initialSearch: true)))
                    }
                    if client.menus.hasMenus { menusButton }
                    aaButton
                    capsuleButton("keyboard", label: "Keyboard", lit: state.personKeyboardUp) {
                        dispatch(.tapKeyboardButton)
                    }
                    capsuleButton("rectangle.and.hand.point.up.left", label: "Trackpad",
                                  lit: state.floatingPad.isVisible) {
                        dispatch(.toggleFloatingPad)
                    }
                    capsuleButton("slider.horizontal.3", label: "Controls", lit: false) {
                        dispatch(.openModal(.controlCenter(.root)))
                    }
                    capsuleButton("chevron.right", label: "Tuck controls", lit: false) {
                        dispatch(.toggleCapsuleTuck)
                    }
                }
            }
            if scaleOpen { scalePill }
        }
        .onChange(of: client.textScaleSelectable) { _, now in
            if !now { scaleOpen = false }
        }
        .onChange(of: state.modal) { _, now in
            if now != .menusPullDown { menusOpen = false }
        }
    }

    /// The three front-most windows as round keys, the active one's rim lit; a flick across them
    /// steps the window as the phone's chip does, and picking one asks the Mac for it.
    private var windowPills: some View {
        HStack(spacing: 6) {
            ForEach(recentWindows, id: \.id) { w in
                Button {
                    TactileHaptics.play(.tick)
                    client.select(.window(w.id))
                } label: {
                    Group {
                        if let icon = client.icons[w.bundleID] {
                            Image(uiImage: icon)
                                .resizable()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: "macwindow")
                                .font(.system(size: 17))
                                .foregroundStyle(TactileTokens.textSecondary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .overlay {
                        if client.active == .window(w.id) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                                .padding(-3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(w.title.isEmpty ? w.appName : w.title)
            }
            if recentWindows.isEmpty {
                Text("No windows")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TactileTokens.textSecondary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .tactileSurface(.floatingChrome, shape: .capsule)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { g in
                    guard abs(g.translation.width) >= 28,
                          abs(g.translation.width) > abs(g.translation.height) else { return }
                    dispatch(.swipeWindowChip(direction: g.translation.width < 0 ? 1 : -1,
                                              orderedWindowIDs: client.orderedWindows.map(\.id),
                                              active: Self.workspaceSource(client.active)))
                }
        )
        .accessibilityHint("Swipe for another window")
    }

    /// The menus key: the capsule draws it (`MacMenuButton.symbol`, unenclosed), and the existing
    /// `MacMenuTrigger` — the UIKit button whose UIMenu can offer submenus the Mac fetches only on
    /// open — covers it, so iPadOS 17 gets the same lazy menus without a popover's fight for the
    /// window.
    private var menusButton: some View {
        Image(systemName: MacMenuButton.symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(TactileTokens.textPrimary)
            .frame(width: 44, height: 44)
            .tactileSurface(.interactiveChrome, shape: .circle)
            .overlay {
                MacMenuTrigger(client: client, open: $menusOpen,
                               onOpen: { dispatch(.openModal(.menusPullDown)) },
                               onClose: { dispatch(.closeModal(restoreKeyboard: false)) })
                    .frame(width: 44, height: 44)
            }
    }

    /// Aa: the same inline detent pill the Control Center's dial has, kept to a row of detent keys
    /// under the capsule; dimmed to its hint while the Desktop streams (Aa sizes a window).
    private var aaButton: some View {
        Button {
            guard client.textScaleSelectable else { return }
            withAnimation(.easeOut(duration: 0.18)) { scaleOpen.toggle() }
        } label: {
            Text("Aa")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(scaleOpen ? TactileTokens.ledCyan : TactileTokens.textPrimary)
                .frame(width: 22, height: 22)
        }
        .tactileButton(.secondary, shape: .circle)
        .opacity(client.textScaleSelectable ? 1 : 0.45)
        .accessibilityLabel("Text size")
        .accessibilityValue(TextScale.spoken(at: TextScale.position(of: textScale, offered: client.textScaleOffersOff)))
        .accessibilityHint(client.textScaleSelectable ? "" : client.textScaleUnavailableHint)
    }

    /// The compact detent row under the capsule: every `TextScale` detent a key, the live one's
    /// title lit; a tap commits the scale at once (the binding is the commit — the stream's owner
    /// re-sends the viewport on it, as `StreamScreen`'s `onChange(of: textScale)` does).
    private var scalePill: some View {
        let offered = client.textScaleOffersOff
        let position = TextScale.position(of: textScale, offered: offered)
        return HStack(spacing: 0) {
            ForEach(TextScale.detents(offered: offered), id: \.self) { detent in
                Button {
                    textScale = TextScale.scale(at: detent)
                    onTextScaleCommit()
                } label: {
                    Text(TextScale.title(at: detent))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(detent == position ? TactileTokens.ledCyan : TactileTokens.textPrimary)
                        .frame(minWidth: 40, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TextScale.spoken(at: detent))
            }
        }
        .padding(.horizontal, 8)
        .tactileSurface(.recessedHardware, shape: .capsule)
    }

    /// One round capsule key; its symbol unenclosed (the surface draws the enclosure), lit while
    /// its thing is on.
    private func capsuleButton(_ symbol: String, label: String, lit: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(lit ? TactileTokens.ledCyan : TactileTokens.textPrimary)
                .frame(width: 22, height: 22)
        }
        .tactileButton(.secondary, shape: .circle)
        .accessibilityLabel(label)
    }

    // MARK: Tucked

    /// What a tucked capsule leaves: a 16×58 machined tab on the trailing edge, all of the 4:3
    /// canvas clear. A tap or an inward pull untucks it (`toggleCapsuleTuck` decides the rest).
    private var pullTab: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TactileTokens.chassisRaised)
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TactileTokens.textSecondary)
        }
        .frame(width: 16, height: 58)
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded { dispatch(.toggleCapsuleTuck) })
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { g in
                    if g.translation.width < -20 { dispatch(.toggleCapsuleTuck) }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Controls")
        .accessibilityHint("Show the controls")
        .accessibilityAddTraits(.isButton)
    }

    /// The workspace's own stream source (`StreamWorkspaceState.swift` is pure Swift and cannot see
    /// `StreamProtocol.StreamSource`): the same three cases carried to `swipeWindowChip`.
    private static func workspaceSource(_ source: StreamSource) -> WorkspaceSource {
        switch source {
        case .none: return .none
        case .desktop: return .desktop
        case .window(let id): return .window(id)
        }
    }
}
