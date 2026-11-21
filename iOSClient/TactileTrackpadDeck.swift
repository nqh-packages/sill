import SwiftUI
import StreamProtocol

// The tactile decks' trackpad well and the two decks built around it (Slice 1, the tactile
// rebuild): the phone's pull-up Control Deck and the iPad's floating trackpad pad. The well is
// recessed anodized hardware — TactileTokens.trackpadWell, an inner-shadow rim, an etched
// micro-dot grid, a specular bottom lip — wrapped straight around the engine's own TrackpadView,
// so the pad's gesture math, cursor and pointer feed are untouched (the wiring below is the old
// laptop layout's, verbatim). Slice 0's contract (TactileTokens, TactileSurfaceRole,
// .tactileSurface/.tactileButton, WorkspacePoint) arrives with Wave 2's merge.

// MARK: - Trackpad well

/// The recessed hardware well the tactile decks put the trackpad in: anodized dark, an inner-shadow
/// rim so the surface reads as sunk into the chassis, a delicate etched dot grid (the "drag here"
/// texture), and a specular lip catching light along the bottom edge. The live surface inside is the
/// engine's own TrackpadView with the laptop layout's exact wiring — sendInput for events,
/// setOwnPointer(.trackpad) for the cursor sprite, pointerFeedState for the anchor and re-seeds,
/// trackpadFingers for Q1's flip, `latched` for modified clicks (consumed by a click as before) and
/// sendGesture for the Mac's three- and four-finger gestures.
struct TactileTrackpadWell: View {
    @ObservedObject var client: StreamClient
    @Binding var latched: KeyModifiers
    /// What the pad's vertical motion is measured against (nil: its own height), as the laptop
    /// layout passed it — a stroke then moves the pointer as far down as across on a 16:10 picture.
    var verticalSpan: CGFloat? = nil
    var cornerRadius: CGFloat = 22
    var showsHint: Bool = true

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            TactileTokens.trackpadWell
            EtchedDotGrid()
            TrackpadView(send: { client.sendInput($0) },
                         setPointer: { client.setOwnPointer($0, from: .trackpad) },
                         feed: { let f = client.pointerFeedState; return (f.anchor, f.reseeds) },
                         onFingers: { client.trackpadFingers($0) },
                         latched: latched,
                         onModifiersConsumed: { latched = [] },
                         verticalSpan: verticalSpan,
                         sendGesture: { client.sendGesture($0, fingers: $1) })
            if showsHint {
                VStack {
                    Spacer(minLength: 0)
                    Text("Drag to move the pointer. Tap to click, two fingers to scroll.")
                        .font(.system(size: 13))
                        .foregroundStyle(TactileTokens.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        // The recessed rim: a dark inner shadow at the top falling off to the bottom edge's
        // specular line, so the well reads as sunk into the chassis rather than laid on it.
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [Color.black.opacity(0.65), Color.black.opacity(0.2),
                                    TactileTokens.specularRimBottom],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 1.5))
        // The specular lip: a hair of light just inside the bottom edge, kept to the flat run so it
        // never pokes past the corner's curve (the overlay draws outside the clip).
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TactileTokens.specularRimTop.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, cornerRadius)
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
    }
}

/// 1 pt dots on an 18 pt grid, etched into the anodized well: the board texture that says "this
/// surface is the one you drag on", a touch dimmer than the old well's for the machined look.
private struct EtchedDotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18
            let radius: CGFloat = 1
            let shading = GraphicsContext.Shading.color(.white.opacity(0.05))
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: shading)
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Phone Control Deck

/// The phone's pull-up Control Deck: a physical hardware chassis (chassisDark, recessedHardware,
/// a chamfered top rim) with a draggable grab handle, a compact header naming what streams and a
/// stow key, the six-key tactile key row and the trackpad well.
///
/// The handle's drag is reported, not acted on: `onDragChanged(progress)` gives the drag as a
/// fraction of the deck's own height, positive while the deck is pulled up (open) and negative while
/// dragged down toward the stow; `onDragEnded(progress, velocityY)` ends a drag with the same
/// progress and the gesture's projected vertical velocity in pt/s (positive upward). The parent
/// decides where the deck settles.
struct PhoneControlDeckView: View {
    @ObservedObject var client: StreamClient
    @Binding var latched: KeyModifiers
    var bottomInset: CGFloat = 0
    let onDragChanged: (_ progress: Double) -> Void
    let onDragEnded: (_ progress: Double, _ velocityY: Double) -> Void
    var onSwitchToKeyboard: (() -> Void)? = nil
    let onClose: () -> Void

    @State private var deckHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            TactileCommandBar(
                mode: .trackpad(onSwitchToKeyboard: onSwitchToKeyboard),
                latched: $latched,
                send: { client.sendFromKeyRow($0) },
                onDismiss: onClose
            )
            .simultaneousGesture(deckDrag)

            TactileTrackpadWell(client: client, latched: $latched, cornerRadius: 26)
                .padding(.horizontal, 6)
                .padding(.bottom, max(6, bottomInset))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            deckHeight = max(1, $0)
        }
    }

    private var deckDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                onDragChanged(progress(for: value.translation.height))
            }
            .onEnded { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                onDragEnded(progress(for: value.translation.height),
                            Double(value.velocity.height))
            }
    }

    private func progress(for translationY: CGFloat) -> Double {
        max(0, min(1, 1.0 - Double(translationY) / Double(deckHeight)))
    }
}

// MARK: - iPad floating trackpad

/// A compact tactile hardware pad that floats over the stream on an iPad: a draggable anodized
/// title/grip strip (with the close key), the six-key row and a small trackpad well, ~320×260 pt —
/// enough pad to aim and click while the picture keeps most of the screen on a handheld 10.5" iPad.
///
/// `anchor` is the pad's centre in the container's points, `containerSize` the space it floats in;
/// dragging the grip reports the would-be centre through `onMoveAnchor`, clamped so the pad can
/// never be pushed off screen.
struct PadFloatingTrackpadView: View {
    @ObservedObject var client: StreamClient
    @Binding var latched: KeyModifiers
    let containerSize: CGSize
    let anchor: WorkspacePoint
    let onMoveAnchor: (WorkspacePoint) -> Void
    let onClose: () -> Void

    @State private var dragStart: WorkspacePoint? = nil

    /// The pad's footprint: compact, so the stream stays the screen on a handheld iPad.
    static let padSize = CGSize(width: 320, height: 260)

    var body: some View {
        VStack(spacing: 8) {
            gripStrip
            TactileKeycapRow(style: .deckSix, latched: $latched,
                             send: { client.sendFromKeyRow($0) })
            TactileTrackpadWell(client: client, latched: $latched,
                                cornerRadius: 14, showsHint: false)
        }
        .padding(10)
        .frame(width: Self.padSize.width, height: Self.padSize.height)
        .tactileSurface(.floatingChrome, shape: .rounded(20))
        .position(x: anchor.x, y: anchor.y)
    }

    /// The anodized title strip and grip: its drag moves the pad (the would-be centre, clamped to
    /// the container, through `onMoveAnchor`); the close key sits beside it, outside the drag.
    private var gripStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .bold))
                Text("Trackpad")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(TactileTokens.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 30)
            .tactileSurface(.interactiveChrome, shape: .rounded(10))
            .contentShape(Rectangle())
            .gesture(moveDrag)
            .accessibilityLabel("Move the trackpad")
            .accessibilityHint("Drag to move the pad around the screen")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .tactileButton(.secondary, shape: .circle)
            .accessibilityLabel("Close the trackpad")
        }
    }

    /// The grip's drag: the anchor plus the translation, clamped so the whole pad stays on screen.
    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? anchor
                if dragStart == nil { dragStart = start }
                onMoveAnchor(clamped(WorkspacePoint(x: start.x + Double(value.translation.width),
                                                    y: start.y + Double(value.translation.height))))
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    /// The pad's centre, clamped so its frame stays inside the container (a container smaller than
    /// the pad parks it centred rather than pushing it out).
    private func clamped(_ point: WorkspacePoint) -> WorkspacePoint {
        var p = point
        let halfW = Double(Self.padSize.width) / 2
        let halfH = Double(Self.padSize.height) / 2
        p.x = min(max(p.x, halfW), max(halfW, Double(containerSize.width) - halfW))
        p.y = min(max(p.y, halfH), max(halfH, Double(containerSize.height) - halfH))
        return p
    }
}
