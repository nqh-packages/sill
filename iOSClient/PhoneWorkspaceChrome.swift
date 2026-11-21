import SwiftUI
import UIKit
import StreamProtocol

/// The iPhone's floating dock (the tactile workspace's phone chrome): a slim bottom dock over the
/// stream that replaces the old portrait bar card. Its look is the tactile design system's
/// (`TactileStyle`): Liquid Glass on iOS 26 and later, the machined chamfered capsule the same
/// `tactileSurface`/`tactileButton` calls draw on iPadOS 17, so the one layout runs on the iPhone 17
/// and the smallest iPad alike.
///
/// What it holds, left to right: the chip of what streams (the active window's app icon and title,
/// the Desktop's label, and how many windows the Mac has), then Trackpad, Keyboard and Controls.
/// Above it the pull-up grip for the Control Deck. Everything the dock can change goes to
/// `StreamWorkspaceState` as an action (`dispatch`); only what the Mac itself answers to
/// (selecting a window, a swipe's direction computed from the live list) carries window IDs.
///
/// The chip's two gestures: a tap opens the switcher; a horizontal flick past 32 pt hands the state
/// machine the step (+1 forward in `client.orderedWindows` — a flick left, the "next" a swipe
/// brings; -1 back), the live order and the active source as a `WorkspaceSource`, and it picks the
/// window (StreamWorkspaceState.Action.swipeWindowChip).
struct PhoneFloatingDock: View {
    @ObservedObject var client: StreamClient
    let state: StreamWorkspaceState
    let dispatch: (StreamWorkspaceState.Action) -> Void

    /// Finger travel that drags the Control Deck fully open (progress 1).
    private static let deckPull: CGFloat = 120
    /// A horizontal flick past this steps to the next or the previous window.
    private static let swipeThreshold: CGFloat = 32

    var body: some View {
        TactileGlassGroup(spacing: 10) {
            VStack(spacing: 8) {
                grip
                HStack(spacing: 10) {
                    activeWindowChip
                    dockButton("rectangle.and.hand.point.up.left", label: "Trackpad",
                               lit: state.showsPhoneDeck) { dispatch(.setPhoneDeck(open: true)) }
                    dockButton("keyboard", label: "Keyboard",
                               lit: state.personKeyboardUp) { dispatch(.tapKeyboardButton) }
                    dockButton("slider.horizontal.3", label: "Controls",
                               lit: false) { dispatch(.openModal(.controlCenter(.root))) }
                }
            }
        }
    }

    // MARK: The grip

    /// The pull-up pill above the dock: a tap opens the deck outright; a pull drags it, its
    /// progress and flick velocity handed to the state machine (`deckDragChanged` /
    /// `deckDragEnded`), which decides whether it opens or folds back.
    private var grip: some View {
        Capsule()
            .fill(TactileTokens.keycapTop)
            .frame(width: 44, height: 5)
            .padding(.vertical, 8)                          // the grip's touch area, not its look
            .contentShape(Capsule())
            .highPriorityGesture(TapGesture().onEnded { dispatch(.setPhoneDeck(open: true)) })
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in dispatch(.deckDragChanged(progress: dragProgress(g.translation.height))) }
                    .onEnded { g in
                        dispatch(.deckDragEnded(progress: dragProgress(g.translation.height),
                                                velocityY: -g.velocity.height))
                    }
            )
            .accessibilityLabel("Control deck")
            .accessibilityHint("Pull up for the trackpad and keys")
    }

    /// Pulling up is negative height: progress is the pull's share of `deckPull`, clamped to 0...1.
    private func dragProgress(_ height: CGFloat) -> Double {
        min(1, max(0, Double(-height) / Double(Self.deckPull)))
    }

    // MARK: The chip

    /// What streams now: the active window's icon, title and the window count; the Desktop's label
    /// (with its stop dots on a Mac of several displays); or, nothing streaming, the way to the
    /// windows. Tap: the switcher. Flick: the neighbour in the Mac's order.
    private var activeWindowChip: some View {
        let windows = client.orderedWindows
        return HStack(spacing: 9) {
            chipIcon(windows)
            Text(chipTitle(windows))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TactileTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            if windows.count > 1 {
                Text("\(windows.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TactileTokens.canvasBlack)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(TactileTokens.ledCyan))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tactileSurface(.interactiveChrome, shape: .capsule)
        .contentShape(Capsule())
        .highPriorityGesture(TapGesture().onEnded { dispatch(.openModal(.switcher(initialSearch: false))) })
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { g in
                    guard abs(g.translation.width) >= Self.swipeThreshold,
                          abs(g.translation.width) > abs(g.translation.height) else { return }
                    // +1 steps forward in the list (a flick left); -1 back.
                    dispatch(.swipeWindowChip(direction: g.translation.width < 0 ? 1 : -1,
                                              orderedWindowIDs: windows.map(\.id),
                                              active: Self.workspaceSource(client.active)))
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chipTitle(windows))
        .accessibilityHint("Tap for windows and apps, or swipe for another window")
    }

    /// The chip's icon: the active window's app icon, a display for the Desktop, the app grid while
    /// nothing streams.
    @ViewBuilder private func chipIcon(_ windows: [WindowInfo]) -> some View {
        if case .window(let id) = client.active, let w = windows.first(where: { $0.id == id }) {
            if let icon = client.icons[w.bundleID] {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 20))
                    .foregroundStyle(TactileTokens.textSecondary)
            }
        } else if client.active == .desktop {
            Image(systemName: "display")
                .font(.system(size: 19))
                .foregroundStyle(TactileTokens.textPrimary)
        } else {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 19))
                .foregroundStyle(TactileTokens.textSecondary)
        }
    }

    /// The chip's title: the window's name or its app's, the Desktop button's label ("Desktop 2"),
    /// or where a tap goes while nothing streams.
    private func chipTitle(_ windows: [WindowInfo]) -> String {
        if case .window(let id) = client.active, let w = windows.first(where: { $0.id == id }) {
            return w.title.isEmpty ? w.appName : w.title
        }
        if client.active == .desktop { return client.desktopButton.label }
        return "Choose a window"
    }

    // MARK: The dock buttons

    /// One round dock key: an unenclosed symbol (the surface draws the enclosure) lit when its
    /// thing is on — the deck open, the person's keyboard up — else the primary text colour.
    private func dockButton(_ symbol: String, label: String, lit: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(lit ? TactileTokens.ledCyan : TactileTokens.textPrimary)
                .frame(width: 46, height: 46)
        }
        .tactileButton(.secondary, shape: .circle)
        .accessibilityLabel(label)
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
