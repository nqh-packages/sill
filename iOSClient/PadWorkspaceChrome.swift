import SwiftUI
import UIKit
import QuartzCore
import StreamProtocol

/// PencilKit-style floating palette chrome for iPad, phone landscape, and Duo book mode:
/// - Docks freely along all 4 edges (`.top`, `.bottom`, `.leading`, `.trailing`), morphing cleanly
///   between horizontal and vertical layouts inside one unified tactile capsule.
/// - Drags from anywhere on the chrome with velocity-projected snapping and a live magnetic dock
///   silhouette preview.
/// - Dragging toward any of the 4 corners (or tapping Minimize) collapses the palette into a 48×48
///   circular corner orb displaying the active Mac app icon; tapping expands back onto its adjacent
///   edge, and dragging the orb relocates or expands it onto any edge.
struct PadFloatingCapsule: View {
    @ObservedObject var client: StreamClient
    let state: StreamWorkspaceState
    let containerSize: CGSize
    let insets: FullScreenPolicy.Insets
    @Binding var textScale: Double?
    var onTextScaleCommit: () -> Void = {}
    let dispatch: (StreamWorkspaceState.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var menusOpen = false
    @State private var scaleOpen = false
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var previewTarget: CapsuleVisibility? = nil
    @State private var lastDragEndTime: CFTimeInterval = 0

    private static let coordSpace = "PadPaletteDockSpace"

    private var paletteMotion: Animation {
        TactileMotion.paletteDock(reduceMotion: reduceMotion)
    }

    private var recentWindows: [WindowInfo] {
        Array(client.orderedWindows.prefix(3))
    }

    private var activeWindowIcon: UIImage? {
        guard case .window(let id) = client.active,
              let win = client.orderedWindows.first(where: { $0.id == id }) else {
            return nil
        }
        return client.icons[win.bundleID]
    }

    private var activeFallbackSymbol: String {
        switch client.active {
        case .desktop: return "display"
        case .window: return "macwindow"
        case .none: return "slider.horizontal.3"
        }
    }

    private var isCompactVertical: Bool {
        state.capsule.edge.isVertical && containerSize.height > 0 && containerSize.height < 460
    }

    private var keySize: CGFloat { isCompactVertical ? 30 : 36 }
    private var iconSize: CGFloat { isCompactVertical ? 24 : 28 }
    private var shellPadding: CGFloat { isCompactVertical ? 5 : 6 }

    private var topMargin: CGFloat { 10 }
    private var bottomMargin: CGFloat { max(12, insets.bottom) }
    private var sideMargin: CGFloat { max(12, max(insets.left, insets.right)) }

    private var canFireTap: Bool {
        !isDragging && (CACurrentMediaTime() - lastDragEndTime) > 0.16
    }

    var body: some View {
        ZStack {
            if isDragging, let target = previewTarget {
                dockPreviewGhost(for: target)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            dockedPaletteWithPopover
                .padding(.top, topMargin)
                .padding(.bottom, bottomMargin)
                .padding(.leading, sideMargin)
                .padding(.trailing, sideMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: state.capsule))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.coordSpace)
        .onChange(of: client.textScaleSelectable) { _, now in
            if !now { scaleOpen = false }
        }
        .onChange(of: state.modal) { _, now in
            if now != .menusPullDown { menusOpen = false }
        }
        .onChange(of: state.capsule) { _, now in
            if now.isMinimized { scaleOpen = false }
        }
    }

    // MARK: - Docked Palette + Edge-Aware Popover

    @ViewBuilder
    private var dockedPaletteWithPopover: some View {
        switch state.capsule {
        case .minimized:
            minimizedOrb
                .offset(dragOffset)
                .scaleEffect(isDragging ? 1.08 : 1.0)
                .animation(TactileMotion.buttonPress, value: isDragging)
                .simultaneousGesture(paletteDragGesture)

        case .expanded(let edge):
            paletteWithPopover(for: edge)
                .offset(dragOffset)
                .scaleEffect(isDragging ? 1.03 : 1.0)
                .animation(TactileMotion.buttonPress, value: isDragging)
        }
    }

    @ViewBuilder
    private func paletteWithPopover(for edge: CapsuleEdge) -> some View {
        switch edge {
        case .top:
            VStack(spacing: 8) {
                expandedCapsule(vertical: false)
                if scaleOpen { scalePill(vertical: false) }
            }
        case .bottom:
            VStack(spacing: 8) {
                if scaleOpen { scalePill(vertical: false) }
                expandedCapsule(vertical: false)
            }
        case .leading:
            HStack(spacing: 8) {
                expandedCapsule(vertical: true)
                if scaleOpen { scalePill(vertical: true) }
            }
        case .trailing:
            HStack(spacing: 8) {
                if scaleOpen { scalePill(vertical: true) }
                expandedCapsule(vertical: true)
            }
        }
    }

    // MARK: - Unified Expanded Capsule

    private func expandedCapsule(vertical: Bool) -> some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: isCompactVertical ? 4 : 6))
            : AnyLayout(HStackLayout(spacing: 6))

        return layout {
            dragHandle(vertical: vertical)
            windowIcons(vertical: vertical)
            paletteDivider(vertical: vertical)
            toolButtons(vertical: vertical)
        }
        .padding(.horizontal, vertical ? shellPadding : shellPadding + 4)
        .padding(.vertical, vertical ? shellPadding + 4 : shellPadding)
        .tactileSurface(.floatingChrome, shape: .capsule)
        .contentShape(Capsule(style: .continuous))
        .simultaneousGesture(paletteDragGesture)
    }

    private func dragHandle(vertical: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(TactileTokens.specularRimTop)
            .frame(width: vertical ? 16 : 3.5, height: vertical ? 3.5 : 16)
            .padding(vertical ? .vertical : .horizontal, 2)
            .accessibilityHidden(true)
    }

    private func paletteDivider(vertical: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(TactileTokens.specularRimTop)
            .frame(width: vertical ? 20 : 1, height: vertical ? 1 : 20)
            .accessibilityHidden(true)
    }

    private func windowIcons(vertical: Bool) -> some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: isCompactVertical ? 4 : 5))
            : AnyLayout(HStackLayout(spacing: 5))

        return layout {
            ForEach(recentWindows, id: \.id) { w in
                Button {
                    guard canFireTap else { return }
                    TactileHaptics.play(.tick)
                    client.select(.window(w.id))
                } label: {
                    TactileAppIcon(
                        image: client.icons[w.bundleID],
                        fallbackSymbol: "macwindow",
                        size: iconSize,
                        cornerRadius: TactileRadius.icon
                    )
                    .tactileSelectionRim(
                        client.active == .window(w.id),
                        shape: .rounded(TactileRadius.pill),
                        lineWidth: 1.5,
                        inset: -2.5
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(w.title.isEmpty ? w.appName : w.title)
            }
            if recentWindows.isEmpty {
                Image(systemName: "macwindow")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TactileTokens.textSecondary)
                    .frame(width: iconSize, height: iconSize)
            }
        }
    }

    private func toolButtons(vertical: Bool) -> some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: isCompactVertical ? 2 : 4))
            : AnyLayout(HStackLayout(spacing: 4))

        return layout {
            paletteKey("square.grid.2x2", label: "Apps", lit: false) {
                dispatch(.openModal(.switcher(initialSearch: true)))
            }
            if client.menus.hasMenus { menusKey }
            aaKey
            paletteKey("keyboard", label: "Keyboard", lit: state.personKeyboardUp) {
                dispatch(.tapKeyboardButton)
            }
            paletteKey("rectangle.and.hand.point.up.left", label: "Trackpad", lit: state.floatingPad.isVisible) {
                dispatch(.toggleFloatingPad)
            }
            paletteKey("slider.horizontal.3", label: "Controls", lit: false) {
                dispatch(.openModal(.controlCenter(.root)))
            }
            paletteKey("arrow.down.right.and.arrow.up.left", label: "Minimize controls", lit: false) {
                dispatch(.toggleCapsuleTuck)
            }
        }
    }

    private func paletteKey(
        _ symbol: String,
        label: String,
        lit: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard canFireTap else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: isCompactVertical ? 14 : 16, weight: .medium))
                .foregroundStyle(lit ? TactileTokens.ledCyan : TactileTokens.textPrimary)
                .frame(width: keySize, height: keySize)
                .background {
                    if lit {
                        Circle().fill(TactileTokens.badgeFill)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var menusKey: some View {
        Image(systemName: MacMenuButton.symbol)
            .font(.system(size: isCompactVertical ? 15 : 17, weight: .medium))
            .foregroundStyle(menusOpen ? TactileTokens.ledCyan : TactileTokens.textPrimary)
            .frame(width: keySize, height: keySize)
            .background {
                if menusOpen {
                    Circle().fill(TactileTokens.badgeFill)
                }
            }
            .overlay {
                MacMenuTrigger(
                    client: client,
                    open: $menusOpen,
                    onOpen: { dispatch(.openModal(.menusPullDown)) },
                    onClose: { dispatch(.closeModal(restoreKeyboard: false)) }
                )
                .frame(width: keySize, height: keySize)
            }
    }

    private var aaKey: some View {
        Button {
            guard canFireTap, client.textScaleSelectable else { return }
            withAnimation(TactileMotion.barMorph) { scaleOpen.toggle() }
        } label: {
            Text("Aa")
                .font(.system(size: isCompactVertical ? 13 : 14.5, weight: .semibold))
                .foregroundStyle(scaleOpen ? TactileTokens.ledCyan : TactileTokens.textPrimary)
                .frame(width: keySize, height: keySize)
                .background {
                    if scaleOpen {
                        Circle().fill(TactileTokens.badgeFill)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(client.textScaleSelectable ? 1 : 0.42)
        .accessibilityLabel("Text size")
        .accessibilityValue(
            TextScale.spoken(at: TextScale.position(of: textScale, offered: client.textScaleOffersOff))
        )
        .accessibilityHint(client.textScaleSelectable ? "" : client.textScaleUnavailableHint)
    }

    private func scalePill(vertical: Bool) -> some View {
        let offered = client.textScaleOffersOff
        let position = TextScale.position(of: textScale, offered: offered)
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 0))

        return layout {
            ForEach(TextScale.detents(offered: offered), id: \.self) { detent in
                Button {
                    textScale = TextScale.scale(at: detent)
                    onTextScaleCommit()
                } label: {
                    Text(TextScale.title(at: detent))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(detent == position ? TactileTokens.ledCyan : TactileTokens.textPrimary)
                        .frame(minWidth: 40, minHeight: 32)
                        .background {
                            if detent == position {
                                Capsule(style: .continuous).fill(TactileTokens.badgeFill)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TextScale.spoken(at: detent))
            }
        }
        .padding(.horizontal, vertical ? 4 : 8)
        .padding(.vertical, vertical ? 6 : 4)
        .tactileSurface(.floatingChrome, shape: .capsule)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    // MARK: - Minimized Corner Orb

    private var minimizedOrb: some View {
        let hasActiveTool = state.floatingPad.isVisible || state.personKeyboardUp
        return Button {
            guard canFireTap else { return }
            dispatch(.expandCapsule(edge: nil))
        } label: {
            ZStack {
                TactileAppIcon(
                    image: activeWindowIcon,
                    fallbackSymbol: activeFallbackSymbol,
                    size: 28,
                    cornerRadius: TactileRadius.icon
                )
            }
            .frame(width: 48, height: 48)
            .overlay(alignment: .bottomTrailing) {
                if hasActiveTool {
                    TactileLED(isOn: true, color: TactileTokens.ledCyan, diameter: 6)
                        .padding(7)
                }
            }
            .tactileSurface(.interactiveChrome, shape: .circle)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Controls")
        .accessibilityHint("Tap to expand controls, or drag to any edge or corner")
    }

    // MARK: - Magnetic Snap Preview Silhouette

    private func dockPreviewGhost(for target: CapsuleVisibility) -> some View {
        Group {
            if target.isMinimized {
                Circle()
                    .fill(TactileTokens.badgeFill)
                    .overlay {
                        Circle()
                            .strokeBorder(TactileTokens.selectionRim.opacity(0.7), lineWidth: 1.5)
                    }
                    .frame(width: 48, height: 48)
            } else {
                let vertical = target.edge.isVertical
                Capsule(style: .continuous)
                    .fill(TactileTokens.badgeFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(TactileTokens.selectionRim.opacity(0.7), lineWidth: 1.5)
                    }
                    .frame(width: vertical ? 48 : 260, height: vertical ? 260 : 48)
            }
        }
        .padding(.top, topMargin)
        .padding(.bottom, bottomMargin)
        .padding(.leading, sideMargin)
        .padding(.trailing, sideMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: target))
        .animation(TactileMotion.barMorph, value: target)
    }

    // MARK: - Drag Gesture & Snap Geometry

    private var paletteDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named(Self.coordSpace))
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    if scaleOpen { scaleOpen = false }
                    TactileHaptics.play(.tick)
                }
                dragOffset = value.translation
                let norm = normalizedPoint(value.location)
                let candidate = StreamWorkspaceState.capsuleSnapTarget(
                    for: norm,
                    currentEdge: state.capsule.edge
                )
                if candidate != previewTarget {
                    previewTarget = candidate
                    TactileHaptics.play(.tick)
                }
            }
            .onEnded { value in
                lastDragEndTime = CACurrentMediaTime()
                let norm = normalizedPoint(value.predictedEndLocation)
                withAnimation(paletteMotion) {
                    isDragging = false
                    dragOffset = .zero
                    previewTarget = nil
                    dispatch(.snapCapsule(normalizedProjectedPoint: norm))
                }
            }
    }

    private func normalizedPoint(_ point: CGPoint) -> WorkspacePoint {
        WorkspacePoint(
            x: Double(point.x / max(containerSize.width, 1)),
            y: Double(point.y / max(containerSize.height, 1))
        )
    }

    private func alignment(for visibility: CapsuleVisibility) -> Alignment {
        switch visibility {
        case .expanded(.top): return .top
        case .expanded(.bottom): return .bottom
        case .expanded(.leading): return .leading
        case .expanded(.trailing): return .trailing
        case .minimized(.topLeading, _): return .topLeading
        case .minimized(.topTrailing, _): return .topTrailing
        case .minimized(.bottomLeading, _): return .bottomLeading
        case .minimized(.bottomTrailing, _): return .bottomTrailing
        }
    }
}
