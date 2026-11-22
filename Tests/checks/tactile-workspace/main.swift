import Foundation

var fails = 0
var passes = 0

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        passes += 1
        print("ok  ", name)
    } else {
        fails += 1
        let d = detail()
        print("FAIL", name + (d.isEmpty ? "" : " — \(d)"))
    }
}

// MARK: - 1. Default unified workspace state

do {
    let s = StreamWorkspaceState()
    check("initial state: floating capsule visible at bottom, trackpad hidden, no modal, no takers",
          s.showsFloatingCapsule && s.capsule == .expanded(edge: .bottom)
            && !s.floatingPad.isVisible && !s.pointerTrackpadActive
            && s.modal == .none && s.keyboardTakers.isEmpty)
}

// MARK: - 2. Trackpad / docked Control Deck drag & snap thresholds

do {
    var s = StreamWorkspaceState()
    let c1 = s.send(.deckDragChanged(progress: -0.4))
    check("deckDragChanged clamps negative progress to 0 without effects",
          s.deckDragProgress == 0 && c1.isEmpty)

    _ = s.send(.deckDragChanged(progress: 1.7))
    check("deckDragChanged clamps >1 progress to 1", s.deckDragProgress == 1)

    _ = s.send(.deckDragChanged(progress: 0.35))
    check("deckDragChanged preserves closed trackpad while dragging",
          s.deckDragProgress == 0.35 && !s.floatingPad.isVisible)

    _ = s.send(.deckDragChanged(progress: .nan))
    check("deckDragChanged ignores NaN progress", s.deckDragProgress == 0.35)

    // Slow release below midpoint snaps closed
    let snapClosedFX = s.send(.deckDragEnded(progress: 0.49, velocityY: 0))
    check("deckDragEnded below 0.5 snaps closed with progress 0",
          !s.floatingPad.isVisible && s.deckDragProgress == 0 && !snapClosedFX.contains(.haptic(.detent)))

    // Slow release at midpoint snaps open
    let snapOpenFX = s.send(.deckDragEnded(progress: 0.5, velocityY: 0))
    check("deckDragEnded at 0.5 opens trackpad with detent & pointerTrackpadActive",
          s.floatingPad.isVisible && s.deckDragProgress == 1 && s.pointerTrackpadActive
            && snapOpenFX.contains(.haptic(.detent))
            && snapOpenFX.contains(.setPointerTrackpadVisible(true)))

    // Fast downward flick closes even when progress is high
    let flickDownFX = s.send(.deckDragEnded(progress: 0.85, velocityY: 450))
    check("deckDragEnded fast downward flick closes trackpad despite high progress",
          !s.floatingPad.isVisible && s.deckDragProgress == 0 && !s.pointerTrackpadActive
            && flickDownFX.contains(.haptic(.detent))
            && flickDownFX.contains(.setPointerTrackpadVisible(false)))

    // Fast upward flick opens even when progress is low
    let flickUpFX = s.send(.deckDragEnded(progress: 0.12, velocityY: -450))
    check("deckDragEnded fast upward flick opens trackpad despite low progress",
          s.floatingPad.isVisible && s.deckDragProgress == 1 && s.pointerTrackpadActive
            && flickUpFX.contains(.haptic(.detent))
            && flickUpFX.contains(.setPointerTrackpadVisible(true)))

    // Idempotent setTrackpad
    let dupOpenFX = s.send(.setTrackpad(open: true))
    check("setTrackpad(open: true) when already open is no-op", dupOpenFX.isEmpty)

    // Opening trackpad while keyboard up dismisses keyboard
    _ = s.send(.setTrackpad(open: false))
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    let deckOverKeyboardFX = s.send(.setTrackpad(open: true))
    check("setTrackpad(open: true) over keyboard dismisses keyboard and opens trackpad",
          s.floatingPad.isVisible && deckOverKeyboardFX.contains(.setKeyboard(shown: false))
            && deckOverKeyboardFX.contains(.setPointerTrackpadVisible(true)))
}

// MARK: - 3. Keyboard <-> Trackpad swap & modal keyboard restoration

do {
    var s = StreamWorkspaceState()

    let kb1 = s.send(.tapKeyboardButton)
    check("tapKeyboardButton toggles keyboard with tick",
          kb1.contains(.toggleKeyboard) && kb1.contains(.haptic(.tick)))

    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    check("systemKeyboardChanged(true) shows keyboard accessory on software keyboard",
          s.personKeyboardUp && s.showsKeyboardAccessory)

    _ = s.send(.setHardwareKeyboardAttached(true))
    check("hardware keyboard attached hides software keyboard accessory",
          !s.showsKeyboardAccessory)
    _ = s.send(.setHardwareKeyboardAttached(false))
    check("hardware keyboard detached restores keyboard accessory", s.showsKeyboardAccessory)

    let kbOff = s.send(.tapKeyboardButton)
    check("tapKeyboardButton while keyboard up hides keyboard",
          kbOff.contains(.setKeyboard(shown: false)))
    _ = s.send(.systemKeyboardChanged(personOwnUp: false))

    // Trackpad open -> tapKeyboardButton closes trackpad and requests keyboard
    _ = s.send(.setTrackpad(open: true))
    let swapToKB = s.send(.tapKeyboardButton)
    check("tapKeyboardButton while trackpad open closes trackpad and toggles keyboard",
          !s.floatingPad.isVisible && !s.pointerTrackpadActive && s.deckDragProgress == 0
            && swapToKB.contains(.toggleKeyboard)
            && swapToKB.contains(.setPointerTrackpadVisible(false)))
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))

    // Modal while keyboard up saves restoreKeyboardAfterModal
    let openSwitcher = s.send(.openModal(.switcher(initialSearch: true)))
    check("openModal while keyboard up sets restoreKeyboardAfterModal, hides keyboard, updates takers",
          s.modal == .switcher(initialSearch: true) && s.restoreKeyboardAfterModal
            && !s.showsKeyboardAccessory
            && openSwitcher.contains(.setKeyboard(shown: false))
            && openSwitcher.contains(.releaseHeldKeys)
            && openSwitcher.contains(.updateTakers([.drawer])))

    _ = s.send(.systemKeyboardChanged(personOwnUp: false))
    check("systemKeyboardChanged(false) during modal preserves restoreKeyboardAfterModal",
          !s.personKeyboardUp && s.restoreKeyboardAfterModal)

    let closeRestore = s.send(.closeModal(restoreKeyboard: true))
    check("closeModal(restoreKeyboard: true) re-raises keyboard",
          s.modal == .none && !s.restoreKeyboardAfterModal
            && closeRestore.contains(.setKeyboard(shown: true))
            && closeRestore.contains(.updateTakers([])))

    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    let dismissFX = s.send(.dismissKeyboardRequested)
    check("dismissKeyboardRequested hides keyboard with tick",
          dismissFX == [.setKeyboard(shown: false), .haptic(.tick)])
}

// MARK: - 4. Viewport stability during deck drag & settled resize

do {
    var s = StreamWorkspaceState()
    let focusSize = WorkspaceSize(width: 402, height: 874)

    let badSize = s.send(.focusCanvasMeasured(WorkspaceSize(width: 0, height: 874)))
    check("zero-width focusCanvasMeasured is ignored",
          badSize.isEmpty && s.committedCanvasSize == WorkspaceSize(width: 0, height: 0))

    let initFX = s.send(.focusCanvasMeasured(focusSize))
    check("first focusCanvasMeasured commits with .initialCanvas",
          s.committedCanvasSize == focusSize
            && initFX == [.commitViewport(focusSize, reason: .initialCanvas)])

    let sameFX = s.send(.focusCanvasMeasured(focusSize))
    check("identical focusCanvasMeasured is no-op", sameFX.isEmpty)

    // Mid-drag deck never commits viewport, while settled open/close refits visible canvas
    let dragFX = s.send(.deckDragChanged(progress: 0.5))
    let shrunkDuringDrag = s.send(.focusCanvasMeasured(WorkspaceSize(width: 402, height: 480)))
    check("viewport stays locked mid-drag so deck gesture never thrashes Mac",
          s.committedCanvasSize == focusSize && dragFX.isEmpty && shrunkDuringDrag.isEmpty)

    _ = s.send(.setTrackpad(open: true))
    let deckVisible = WorkspaceSize(width: 402, height: 490)
    let deckFitFX = s.send(.focusCanvasMeasured(deckVisible))
    check("settled open deck commits visible canvas size",
          s.committedCanvasSize == deckVisible
            && deckFitFX == [.commitViewport(deckVisible, reason: .formOrSizeChanged)])

    _ = s.send(.setTrackpad(open: false))
    let focusRestoreFX = s.send(.focusCanvasMeasured(focusSize))
    check("closing deck restores full-bleed canvas viewport",
          s.committedCanvasSize == focusSize
            && focusRestoreFX == [.commitViewport(focusSize, reason: .formOrSizeChanged)])

    // Real resize (e.g. rotation / iPad Split View) commits .formOrSizeChanged
    let padSize = WorkspaceSize(width: 1112, height: 834)
    let resizeFX = s.send(.focusCanvasMeasured(padSize))
    check("real resize commits .formOrSizeChanged",
          s.committedCanvasSize == padSize
            && resizeFX == [.commitViewport(padSize, reason: .formOrSizeChanged)])

    // Text scale commit
    let textFX = s.send(.textScaleCommitted)
    check("textScaleCommitted emits .textScaleChanged and detent",
          textFX.contains(.commitViewport(padSize, reason: .textScaleChanged))
            && textFX.contains(.haptic(.detent)))
}

// MARK: - 5. Universal PencilKit 4-edge docking, 4-corner minimization & velocity snap

do {
    var ws = StreamWorkspaceState()
    check("initial capsule is expanded at bottom (clears Mac toolbars like PencilKit)",
          ws.capsule == .expanded(edge: .bottom) && !ws.capsule.isMinimized && !ws.capsule.isTucked
            && ws.capsule.edge == .bottom && ws.capsule.corner == nil)

    let tuckFX = ws.send(.toggleCapsuleTuck)
    check("toggleCapsuleTuck minimizes bottom capsule to bottomTrailing orb",
          ws.capsule == .minimized(corner: .bottomTrailing, returnEdge: .bottom)
            && ws.capsule.isMinimized && ws.capsule.isTucked
            && ws.capsule.corner == .bottomTrailing && ws.capsule.edge == .bottom
            && tuckFX == [.haptic(.detent)])

    let edgeFX = ws.send(.setCapsuleEdge(.top))
    check("setCapsuleEdge(.top) while minimized preserves corner and updates returnEdge",
          ws.capsule == .minimized(corner: .bottomTrailing, returnEdge: .top)
            && ws.capsule.isMinimized && ws.capsule.edge == .top
            && edgeFX == [.haptic(.detent)])

    let edgeNoop = ws.send(.setCapsuleEdge(.top))
    check("setCapsuleEdge to same edge is no-op", edgeNoop.isEmpty)

    let untuckFX = ws.send(.toggleCapsuleTuck)
    check("toggleCapsuleTuck expands back to returnEdge (.top)",
          ws.capsule == .expanded(edge: .top) && !ws.capsule.isMinimized && untuckFX == [.haptic(.detent)])

    let snapLeading = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: 0.08, y: 0.50)))
    check("snap to mid-left docks vertical capsule at .leading",
          ws.capsule == .expanded(edge: .leading) && ws.capsule.edge.isVertical
            && snapLeading == [.haptic(.detent)])

    let snapTrailing = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: 0.92, y: 0.50)))
    check("snap to mid-right docks vertical capsule at .trailing",
          ws.capsule == .expanded(edge: .trailing) && ws.capsule.edge.isVertical
            && snapTrailing == [.haptic(.detent)])

    let snapBRFromTrailing = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: 0.92, y: 0.90)))
    check("snap from .trailing into bottomTrailing corner remembers adjacent .trailing returnEdge",
          ws.capsule == .minimized(corner: .bottomTrailing, returnEdge: .trailing)
            && snapBRFromTrailing == [.haptic(.detent)])

    let snapTL = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: 0.05, y: 0.08)))
    check("snap orb to topLeading corner sets non-adjacent returnEdge to .top",
          ws.capsule == .minimized(corner: .topLeading, returnEdge: .top)
            && snapTL == [.haptic(.detent)])

    let expandOrb = ws.send(.expandCapsule())
    check("expandCapsule() from topLeading orb expands onto .top",
          ws.capsule == .expanded(edge: .top) && expandOrb == [.haptic(.detent)])

    let snapBL = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: 0.10, y: 0.92)))
    check("snap to bottomLeading corner minimizes cleanly",
          ws.capsule == .minimized(corner: .bottomLeading, returnEdge: .bottom)
            && snapBL == [.haptic(.detent)])

    let snapBottom = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: 0.50, y: 0.92)))
    check("snap minimized orb to bottom center expands onto .bottom",
          ws.capsule == .expanded(edge: .bottom) && snapBottom == [.haptic(.detent)])

    let snapCenter = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: 0.50, y: 0.50)))
    check("snap at exact center (0.5, 0.5) keeps current edge as no-op",
          ws.capsule == .expanded(edge: .bottom) && snapCenter.isEmpty)

    let snapNaN = ws.send(.snapCapsule(normalizedProjectedPoint: WorkspacePoint(x: .nan, y: 0.5)))
    check("snapCapsule ignores NaN coordinates",
          ws.capsule == .expanded(edge: .bottom) && snapNaN.isEmpty)

    let minTR = ws.send(.minimizeCapsule(corner: .topTrailing))
    check("minimizeCapsule(.topTrailing) collapses to topTrailing orb",
          ws.capsule == .minimized(corner: .topTrailing, returnEdge: .top) && minTR == [.haptic(.detent)])
}

// MARK: - 6. Floating trackpad visibility & anchor clamping

do {
    var ws = StreamWorkspaceState()
    check("floatingPad defaults hidden at (0.78, 0.72)",
          !ws.floatingPad.isVisible && ws.floatingPad.anchor == WorkspacePoint(x: 0.78, y: 0.72))

    let showFX = ws.send(.toggleFloatingPad)
    check("toggleFloatingPad shows pad and emits pointer trackpad visible",
          ws.floatingPad.isVisible && ws.pointerTrackpadActive
            && showFX.contains(.setPointerTrackpadVisible(true))
            && showFX.contains(.haptic(.detent)))

    _ = ws.send(.moveFloatingPad(anchor: WorkspacePoint(x: -1.0, y: 2.5)))
    check("moveFloatingPad clamps out-of-bounds coordinates inside safe normalized bounds",
          ws.floatingPad.anchor.x == StreamWorkspaceState.floatingPadAnchorXBounds.lowerBound
            && ws.floatingPad.anchor.y == StreamWorkspaceState.floatingPadAnchorYBounds.upperBound)

    _ = ws.send(.moveFloatingPad(anchor: WorkspacePoint(x: 0.35, y: 0.45)))
    check("moveFloatingPad accepts valid in-bounds coordinates",
          ws.floatingPad.anchor == WorkspacePoint(x: 0.35, y: 0.45))

    _ = ws.send(.moveFloatingPad(anchor: WorkspacePoint(x: .nan, y: 0.5)))
    check("moveFloatingPad ignores NaN coordinates",
          ws.floatingPad.anchor == WorkspacePoint(x: 0.35, y: 0.45))

    let hideFX = ws.send(.toggleFloatingPad)
    check("toggleFloatingPad hides pad and disables pointer trackpad",
          !ws.floatingPad.isVisible && !ws.pointerTrackpadActive
            && hideFX.contains(.setPointerTrackpadVisible(false)))
}

// MARK: - 7. Full-screen hide/show

do {
    var s = StreamWorkspaceState()
    let size = WorkspaceSize(width: 402, height: 874)
    _ = s.send(.focusCanvasMeasured(size))
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))

    let hideFX = s.send(.setFullScreenHidden(true))
    check("setFullScreenHidden(true) hides capsule and accessory and commits .chromeToggled",
          s.fullScreenHidden && !s.showsFloatingCapsule && !s.showsKeyboardAccessory
            && hideFX.contains(.commitViewport(size, reason: .chromeToggled))
            && hideFX.contains(.haptic(.detent)))

    let dupHide = s.send(.setFullScreenHidden(true))
    check("setFullScreenHidden(true) again is no-op", dupHide.isEmpty)

    let showFX = s.send(.setFullScreenHidden(false))
    check("setFullScreenHidden(false) restores capsule and accessory and commits .chromeToggled",
          !s.fullScreenHidden && s.showsFloatingCapsule && s.showsKeyboardAccessory
            && showFX.contains(.commitViewport(size, reason: .chromeToggled)))
}

// MARK: - 8. Keyboard takers derivation & Control Center routes

do {
    var s = StreamWorkspaceState()
    check("takers empty for .none", s.keyboardTakers == [])

    let fx1 = s.send(.openModal(.switcher()))
    check("takers [.drawer] for .switcher", s.keyboardTakers == [.drawer] && fx1.contains(.updateTakers([.drawer])))

    let fx2 = s.send(.openModal(.controlCenter(.root)))
    check("takers [.settings] for .controlCenter(.root)",
          s.keyboardTakers == [.settings] && fx2.contains(.updateTakers([.settings])))

    let fx3 = s.send(.setControlCenterRoute(.macMenus))
    check("setControlCenterRoute(.macMenus) updates takers to [.settings, .menus]",
          s.modal == .controlCenter(.macMenus)
            && s.keyboardTakers == [.settings, .menus]
            && fx3.contains(.updateTakers([.settings, .menus])))

    let fx3Dup = s.send(.setControlCenterRoute(.macMenus))
    check("setControlCenterRoute to same route is no-op", fx3Dup.isEmpty)

    let fx4 = s.send(.setControlCenterRoute(.root))
    check("setControlCenterRoute(.root) drops .menus taker",
          s.keyboardTakers == [.settings] && fx4.contains(.updateTakers([.settings])))

    let fx5 = s.send(.openModal(.menusPullDown))
    check("takers [.menus] for .menusPullDown",
          s.keyboardTakers == [.menus] && fx5.contains(.updateTakers([.menus])))

    let fx6 = s.send(.openModal(.pairingOverlay))
    check("takers [.pairing] for .pairingOverlay",
          s.keyboardTakers == [.pairing] && fx6.contains(.updateTakers([.pairing])))

    let fx7 = s.send(.openModal(.tour))
    check("takers [.tour] for .tour",
          s.keyboardTakers == [.tour] && fx7.contains(.updateTakers([.tour])))

    let fxClose = s.send(.openModal(.none))
    check("openModal(.none) closes modal and clears takers",
          s.modal == .none && s.keyboardTakers == [] && fxClose.contains(.updateTakers([])))

    // Switching modals while keyboard was captured preserves restoreKeyboardAfterModal
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    _ = s.send(.openModal(.controlCenter(.root)))
    _ = s.send(.systemKeyboardChanged(personOwnUp: false))
    _ = s.send(.openModal(.pairingOverlay))
    check("modal-to-modal switch preserves restoreKeyboardAfterModal", s.restoreKeyboardAfterModal)
    let finalClose = s.send(.closeModal(restoreKeyboard: true))
    check("closing second modal still restores keyboard",
          finalClose.contains(.setKeyboard(shown: true)) && !s.restoreKeyboardAfterModal)
}

// MARK: - 9. Scene deactivation

do {
    var s = StreamWorkspaceState()
    _ = s.send(.deckDragChanged(progress: 0.42))
    let fx = s.send(.sceneDeactivated)
    check("sceneDeactivated releases held keys, clears latched modifiers, and settles drag progress",
          fx == [.releaseHeldKeys, .clearLatchedModifiers] && s.deckDragProgress == 0)
}

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
