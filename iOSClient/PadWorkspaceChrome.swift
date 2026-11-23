import SwiftUI
import UIKit
import QuartzCore
import StreamProtocol

/// PencilKit-style floating palette chrome for iPhone, iPad, and Duo:
/// - Single explicitly-framed, capsule-clipped shell across all 4 edges (`.top`, `.bottom`,
///   `.leading`, `.trailing`) and all 4 corner minimized orbs (`48×48`).
/// - Grabbing and dragging the expanded palette immediately collapses it into the 48×48 circular
///   orb centered directly under the fingertip; releasing glides the orb straight to the target
///   edge (expanding symmetrically from center with masked icons and sequenced fade) or corner.
/// - Adapts horizontal density to container width (`< 500 pt` compact pill on iPhone portrait,
///   full multi-window + Aa + Menus palette on wide widths and vertical rails).
/// - Clears iPadOS top multitasking controls (`...`) and bottom home indicator.
struct PadFloatingCapsule: View {
    @ObservedObject var client: StreamClient
    let state: StreamWorkspaceState
    let containerSize: CGSize
    let insets: FullScreenPolicy.Insets
    var keyboardOcclusion: CGFloat = 0
    @Binding var textScale: Double?
    var onTextScaleCommit: () -> Void = {}
    let dispatch: (StreamWorkspaceState.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var menusOpen = false
    @State private var scaleOpen = false
    @State private var isDragging = false
    @State private var dragLocation: CGPoint? = nil
    @State private var previewTarget: CapsuleVisibility? = nil
    @State private var lastDragEndTime: CFTimeInterval = 0
    @State private var measuredHorizontalSize: CGSize? = nil
    @State private var measuredVerticalSize: CGSize? = nil

    private static let coordSpace = "PadPaletteDockSpace"
    private static let orbDiameter: CGFloat = 48

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
        state.capsule.edge.isVertical && containerSize.height > 0
            && containerSize.height - max(0, keyboardOcclusion) < 460
    }

    /// Narrow portrait widths (iPhone portrait, < 500 pt) show a compact horizontal palette
    /// (active app switcher tile + Keyboard, Trackpad, Controls, Minimize) so it never overflows.
    private var isCompactHorizontal: Bool {
        !state.capsule.edge.isVertical && containerSize.width > 0 && containerSize.width < 500
    }

    private var keySize: CGFloat { isCompactVertical ? 30 : 36 }
    private var iconSize: CGFloat { isCompactVertical ? 24 : 28 }
    private var shellPadding: CGFloat { isCompactVertical ? 5 : 6 }

    /// Clears both top safe-area insets and iPadOS's top-center `...` multitasking control
    /// (whose hit band extends to ~34 pt even when the status bar is hidden).
    private var topMargin: CGFloat {
        let multitaskingClearance: CGFloat = containerSize.width >= 600 ? 36 : 12
        return max(multitaskingClearance, insets.top + 10)
    }
    private var bottomMargin: CGFloat {
        CGFloat(StreamWorkspaceState.chromeBottomClearance(
            containerWidth: Double(containerSize.width),
            safeBottom: Double(insets.bottom),
            keyboardOcclusion: Double(keyboardOcclusion)
        ))
    }
    private var sideMargin: CGFloat { max(12, max(insets.left, insets.right)) }

    private var canFireTap: Bool {
        !isDragging && (CACurrentMediaTime() - lastDragEndTime) > 0.16
    }

    /// PencilKit behavior: dragging immediately collapses the bar into the 48×48 circular orb under
    /// the finger; at rest it follows `state.capsule.isMinimized`.
    private var showsOrbShape: Bool {
        isDragging || state.capsule.isMinimized
    }

    /// Estimated or measured size for an expanded capsule along a given orientation.
    private func targetExpandedSize(vertical: Bool) -> CGSize {
        if vertical {
            if let v = measuredVerticalSize { return v }
            if let h = measuredHorizontalSize, !isCompactHorizontal {
                return CGSize(width: h.height, height: h.width)
            }
            return CGSize(width: Self.orbDiameter, height: isCompactVertical ? 330 : 416)
        } else {
            if let h = measuredHorizontalSize { return h }
            if let v = measuredVerticalSize, !(containerSize.width > 0 && containerSize.width < 500) {
                return CGSize(width: v.height, height: v.width)
            }
            let defaultWidth: CGFloat = (containerSize.width > 0 && containerSize.width < 500) ? 240 : 416
            return CGSize(width: defaultWidth, height: Self.orbDiameter)
        }
    }

    private var currentShellSize: CGSize {
        if showsOrbShape {
            return CGSize(width: Self.orbDiameter, height: Self.orbDiameter)
        }
        return targetExpandedSize(vertical: state.capsule.edge.isVertical)
    }

    private var capsuleThickness: CGFloat {
        let s = targetExpandedSize(vertical: state.capsule.edge.isVertical)
        let t = min(s.width, s.height)
        return t > 0 ? max(42, min(t, 54)) : Self.orbDiameter
    }

    private var activeCenter: CGPoint {
        if let dragLocation {
            return dragLocation
        }
        return restingCenter(for: state.capsule)
    }

    private var sequencedContentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.10).delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.05))
        )
    }

    var body: some View {
        ZStack {
            // Isolated magnetic snap ghost layer: scales strictly around each ghost's own center
            // so fading in/out never drifts inward toward screen center.
            ZStack {
                if isDragging, let target = previewTarget, containerSize.width > 0, containerSize.height > 0 {
                    let center = restingCenter(for: target)
                    let anchor = UnitPoint(
                        x: center.x / max(containerSize.width, 1),
                        y: center.y / max(containerSize.height, 1)
                    )
                    dockPreviewGhost(for: target)
                        .id(target)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: anchor)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .animation(TactileMotion.barMorph, value: previewTarget)

            // Independent Aa text-scale popover positioned relative to the resting dock edge so
            // starting a drag dismisses it cleanly in place rather than riding the orb.
            if !showsOrbShape, scaleOpen, containerSize.width > 0, containerSize.height > 0 {
                let edge = state.capsule.edge
                let rest = restingCenter(for: state.capsule)
                let delta = popoverOffset(for: edge)
                let popX = rest.x + delta.width
                let popY = rest.y + delta.height
                let popAnchor = UnitPoint(
                    x: popX / max(containerSize.width, 1),
                    y: popY / max(containerSize.height, 1)
                )
                scalePill(vertical: edge.isVertical)
                    .fixedSize()
                    .position(x: popX, y: popY)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: popAnchor)))
            }

            if containerSize.width > 0, containerSize.height > 0 {
                // Constant-size 48×48 anchor prevents `.position(activeCenter)` from shifting its
                // top-leading origin by (expandedLength - 48)/2 when dragLocation tracks the finger.
                Color.clear
                    .frame(width: Self.orbDiameter, height: Self.orbDiameter)
                    .overlay(alignment: .center) {
                        unifiedPaletteShell
                            .scaleEffect(isDragging ? 1.08 : 1.0)
                    }
                    .position(activeCenter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.coordSpace)
        .defersSystemGestures(on: state.capsule.edge == .top ? .top : [])
        .onChange(of: client.textScaleSelectable) { _, now in
            if !now {
                withAnimation(.easeOut(duration: 0.08)) { scaleOpen = false }
            }
        }
        .onChange(of: state.modal) { _, now in
            if now != .menusPullDown { menusOpen = false }
        }
        .onChange(of: state.capsule) { _, now in
            if now.isMinimized {
                withAnimation(.easeOut(duration: 0.08)) { scaleOpen = false }
            }
        }
    }

    // MARK: - Single Explicitly-Framed, Clipped Palette Shell

    /// Explicitly framed capsule shell whose bounds interpolate symmetrically around `activeCenter`
    /// between `48×48` (orb) and the measured expanded bar size, clipping internal icons cleanly
    /// inside the capsule before applying the tactile glass surface & drop shadow.
    private var unifiedPaletteShell: some View {
        let orb = showsOrbShape
        let vertical = state.capsule.edge.isVertical
        let shell = currentShellSize

        return Color.clear
            .modifier(AnimatableShellSize(width: shell.width, height: shell.height))
            .overlay(alignment: .center) {
                if !orb {
                    expandedControls(vertical: vertical)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
                            guard newSize.width > 0, newSize.height > 0 else { return }
                            if vertical {
                                measuredVerticalSize = newSize
                            } else {
                                measuredHorizontalSize = newSize
                            }
                        }
                        .transition(sequencedContentTransition)
                }
            }
            .overlay(alignment: .center) {
                minimizedOrbVisual
                    .opacity(orb ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .animation(
                        orb ? .easeIn(duration: 0.10).delay(0.06) : .easeOut(duration: 0.05),
                        value: orb
                    )
            }
            .overlay(alignment: .center) {
                if orb {
                    Button {
                        guard canFireTap else { return }
                        dispatch(.expandCapsule(edge: nil))
                    } label: {
                        Color.clear
                            .frame(width: Self.orbDiameter, height: Self.orbDiameter)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Controls")
                    .accessibilityHint("Tap to expand controls, or drag to any edge or corner")
                }
            }
            .clipShape(Capsule(style: .continuous))
            .tactileSurface(.interactiveChrome, shape: .capsule)
            .contentShape(Capsule(style: .continuous))
            .simultaneousGesture(paletteDragGesture)
    }

    private func expandedControls(vertical: Bool) -> some View {
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: isCompactVertical ? 4 : 6))
            : AnyLayout(HStackLayout(spacing: 6))

        return layout {
            dragHandle(vertical: vertical)
            if !vertical && isCompactHorizontal {
                compactActiveAppKey
                paletteDivider(vertical: false)
                compactToolButtons
            } else {
                windowIcons(vertical: vertical)
                paletteDivider(vertical: vertical)
                toolButtons(vertical: vertical)
            }
        }
        .padding(.horizontal, vertical ? shellPadding : shellPadding + 4)
        .padding(.vertical, vertical ? shellPadding + 4 : shellPadding)
    }

    private func popoverOffset(for edge: CapsuleEdge) -> CGSize {
        let halfShell = capsuleThickness / 2
        switch edge {
        case .top: return CGSize(width: 0, height: halfShell + 28)
        case .bottom: return CGSize(width: 0, height: -(halfShell + 28))
        case .leading: return CGSize(width: halfShell + 32, height: 0)
        case .trailing: return CGSize(width: -(halfShell + 32), height: 0)
        }
    }

    // MARK: - Expanded Controls

    /// Compact horizontal switcher button for narrow phone portrait widths: shows the active
    /// Mac app icon (or Desktop / Apps glyph) and opens the Unified Switcher on tap.
    private var compactActiveAppKey: some View {
        Button {
            guard canFireTap else { return }
            dispatch(.openModal(.switcher(initialSearch: false)))
        } label: {
            TactileAppIcon(
                image: activeWindowIcon,
                fallbackSymbol: activeFallbackSymbol,
                size: iconSize,
                cornerRadius: TactileRadius.icon
            )
            .tactileSelectionRim(
                activeWindowIcon != nil,
                shape: .rounded(TactileRadius.pill),
                lineWidth: 1.5,
                inset: -2.5
            )
            .frame(width: keySize, height: keySize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apps")
        .accessibilityHint("Switch Mac windows and apps")
    }

    private var compactToolButtons: some View {
        HStack(spacing: 4) {
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
    }

    // MARK: - Minimized Corner & Drag Orb

    private var minimizedOrbVisual: some View {
        let hasActiveTool = state.floatingPad.isVisible || state.personKeyboardUp
        return ZStack {
            TactileAppIcon(
                image: activeWindowIcon,
                fallbackSymbol: activeFallbackSymbol,
                size: 28,
                cornerRadius: TactileRadius.icon
            )
        }
        .frame(width: Self.orbDiameter, height: Self.orbDiameter)
        .overlay(alignment: .bottomTrailing) {
            if hasActiveTool {
                TactileLED(isOn: true, color: TactileTokens.ledCyan, diameter: 6)
                    .padding(7)
            }
        }
    }

    // MARK: - Magnetic Snap Preview Silhouette

    private func dockPreviewGhost(for target: CapsuleVisibility) -> some View {
        let vertical = target.edge.isVertical
        let targetSize = targetExpandedSize(vertical: vertical)
        let ghostW = vertical ? targetSize.width : min(targetSize.width, max(200, containerSize.width - sideMargin * 2 - 16))
        let ghostH = vertical ? min(targetSize.height, max(200, containerSize.height - topMargin - bottomMargin - 16)) : targetSize.height

        return Group {
            if target.isMinimized {
                Circle()
                    .fill(TactileTokens.badgeFill)
                    .overlay {
                        Circle()
                            .strokeBorder(TactileTokens.selectionRim.opacity(0.7), lineWidth: 1.5)
                    }
                    .frame(width: Self.orbDiameter, height: Self.orbDiameter)
            } else {
                Capsule(style: .continuous)
                    .fill(TactileTokens.badgeFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(TactileTokens.selectionRim.opacity(0.7), lineWidth: 1.5)
                    }
                    .frame(width: ghostW, height: ghostH)
            }
        }
        .position(restingCenter(for: target))
    }

    // MARK: - Drag Gesture & Snap Geometry

    private var paletteDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.coordSpace))
            .onChanged { value in
                let finger = clampedOrbCenter(value.location)
                if !isDragging {
                    if scaleOpen {
                        withAnimation(.easeOut(duration: 0.08)) {
                            scaleOpen = false
                        }
                    }
                    withAnimation(TactileMotion.buttonPress) {
                        isDragging = true
                        dragLocation = finger
                    }
                    TactileHaptics.play(.tick)
                } else {
                    dragLocation = finger
                }

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
                    dragLocation = nil
                    previewTarget = nil
                    dispatch(.snapCapsule(normalizedProjectedPoint: norm))
                }
            }
    }

    private func clampedOrbCenter(_ point: CGPoint) -> CGPoint {
        let half = Self.orbDiameter / 2
        let minX = sideMargin + half
        let maxX = max(minX, containerSize.width - sideMargin - half)
        let minY = topMargin + half
        let maxY = max(minY, containerSize.height - bottomMargin - half)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    /// Exact resting center for every edge and corner. Uses only the constant ~48 pt shell thickness
    /// (never the expanded bar length), so frame-0 drop targets are exact with zero re-settle jump.
    private func restingCenter(for visibility: CapsuleVisibility) -> CGPoint {
        let thickness = visibility.isMinimized ? Self.orbDiameter : capsuleThickness
        let half = thickness / 2
        let leftX = sideMargin + half
        let rightX = max(leftX, containerSize.width - sideMargin - half)
        let midX = containerSize.width / 2
        let topY = topMargin + half
        let bottomY = max(topY, containerSize.height - bottomMargin - half)
        let midY = topMargin + max(0, containerSize.height - topMargin - bottomMargin) / 2

        switch visibility {
        case .expanded(.top): return CGPoint(x: midX, y: topY)
        case .expanded(.bottom): return CGPoint(x: midX, y: bottomY)
        case .expanded(.leading): return CGPoint(x: leftX, y: midY)
        case .expanded(.trailing): return CGPoint(x: rightX, y: midY)
        case .minimized(.topLeading, _): return CGPoint(x: leftX, y: topY)
        case .minimized(.topTrailing, _): return CGPoint(x: rightX, y: topY)
        case .minimized(.bottomLeading, _): return CGPoint(x: leftX, y: bottomY)
        case .minimized(.bottomTrailing, _): return CGPoint(x: rightX, y: bottomY)
        }
    }

    private func normalizedPoint(_ point: CGPoint) -> WorkspacePoint {
        WorkspacePoint(
            x: Double(point.x / max(containerSize.width, 1)),
            y: Double(point.y / max(containerSize.height, 1))
        )
    }
}

/// Animates shell width and height per display frame so `.overlay(alignment: .center)` and
/// `.clipShape(Capsule())` stay strictly symmetric around the capsule center throughout morphs.
private struct AnimatableShellSize: ViewModifier, Animatable {
    var width: CGFloat
    var height: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set {
            width = newValue.first
            height = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.frame(width: max(1, width), height: max(1, height))
    }
}
