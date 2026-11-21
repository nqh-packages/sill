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

// MARK: - 1. Form capabilities and form switching

do {
    check("form: phonePortrait uses phone dock only",
          WorkspaceForm.phonePortrait.usesPhoneDock && !WorkspaceForm.phonePortrait.usesFloatingCapsule)
    check("form: phoneLandscape uses floating capsule only",
          !WorkspaceForm.phoneLandscape.usesPhoneDock && WorkspaceForm.phoneLandscape.usesFloatingCapsule)
    check("form: padFullCanvas uses floating capsule only",
          !WorkspaceForm.padFullCanvas.usesPhoneDock && WorkspaceForm.padFullCanvas.usesFloatingCapsule)
    check("form: duoBook uses floating capsule only",
          !WorkspaceForm.duoBook.usesPhoneDock && WorkspaceForm.duoBook.usesFloatingCapsule)
    check("form: duoLaptop uses neither phone dock nor floating capsule",
          !WorkspaceForm.duoLaptop.usesPhoneDock && !WorkspaceForm.duoLaptop.usesFloatingCapsule)

    var s = StreamWorkspaceState(form: .phonePortrait)
    check("initial portrait: dock visible, deck hidden, capsule hidden, trackpad inactive",
          s.showsPhoneDock && !s.showsPhoneDeck && !s.showsFloatingCapsule && !s.pointerTrackpadActive)

    let openFX = s.send(.setPhoneDeck(open: true))
    check("open deck: pointerTrackpadActive becomes true and emits setPointerTrackpadVisible(true)",
          s.pointerTrackpadActive && s.showsPhoneDeck && !s.showsPhoneDock
            && openFX.contains(.setPointerTrackpadVisible(true)))

    let rotateFX = s.send(.setForm(.phoneLandscape))
    check("rotate portrait(deck) -> landscape: disables trackpad, resets phoneDock, shows capsule",
          s.form == .phoneLandscape && s.phoneDock == .focus && s.deckDragProgress == 0
            && !s.pointerTrackpadActive && s.showsFloatingCapsule
            && rotateFX.contains(.setPointerTrackpadVisible(false)))

    let padFX = s.send(.toggleFloatingPad)
    check("landscape floating pad toggle activates pointer trackpad",
          s.floatingPad.isVisible && s.pointerTrackpadActive
            && padFX.contains(.setPointerTrackpadVisible(true)))

    let toPortraitFX = s.send(.setForm(.phonePortrait))
    check("rotate landscape(floatingPad) -> portrait(focus): hides pointer trackpad",
          !s.pointerTrackpadActive && s.showsPhoneDock
            && toPortraitFX.contains(.setPointerTrackpadVisible(false)))

    let backToPadFX = s.send(.setForm(.padFullCanvas))
    check("switch to padFullCanvas with floatingPad still visible restores pointer trackpad",
          s.pointerTrackpadActive && s.showsFloatingCapsule
            && backToPadFX.contains(.setPointerTrackpadVisible(true)))

    let toLaptopFX = s.send(.setForm(.duoLaptop))
    check("switch to duoLaptop hides capsule and deactivates workspace floating trackpad",
          !s.showsFloatingCapsule && !s.showsPhoneDock && !s.pointerTrackpadActive
            && toLaptopFX.contains(.setPointerTrackpadVisible(false)))

    let noopFX = s.send(.setForm(.duoLaptop))
    check("setForm to same form is no-op", noopFX.isEmpty)
}

// MARK: - 2. Phone deck drag & snap thresholds

do {
    var s = StreamWorkspaceState(form: .phonePortrait)
    let c1 = s.send(.deckDragChanged(progress: -0.4))
    check("deckDragChanged clamps negative progress to 0 without effects",
          s.deckDragProgress == 0 && c1.isEmpty)

    _ = s.send(.deckDragChanged(progress: 1.7))
    check("deckDragChanged clamps >1 progress to 1", s.deckDragProgress == 1)

    _ = s.send(.deckDragChanged(progress: 0.35))
    check("deckDragChanged keeps phoneDock in focus while dragging",
          s.deckDragProgress == 0.35 && s.phoneDock == .focus)

    _ = s.send(.deckDragChanged(progress: .nan))
    check("deckDragChanged ignores NaN progress", s.deckDragProgress == 0.35)

    // Slow release below midpoint snaps closed
    let snapClosedFX = s.send(.deckDragEnded(progress: 0.49, velocityY: 0))
    check("deckDragEnded below 0.5 snaps closed to focus with progress 0",
          s.phoneDock == .focus && s.deckDragProgress == 0 && !snapClosedFX.contains(.haptic(.detent)))

    // Slow release at midpoint snaps open
    let snapOpenFX = s.send(.deckDragEnded(progress: 0.5, velocityY: 0))
    check("deckDragEnded at 0.5 snaps open to controlDeck with detent & trackpad",
          s.phoneDock == .controlDeck && s.deckDragProgress == 1
            && snapOpenFX.contains(.haptic(.detent))
            && snapOpenFX.contains(.setPointerTrackpadVisible(true)))

    // Fast downward flick closes even when progress is high
    let flickDownFX = s.send(.deckDragEnded(progress: 0.85, velocityY: 450))
    check("deckDragEnded fast downward flick closes deck despite high progress",
          s.phoneDock == .focus && s.deckDragProgress == 0
            && flickDownFX.contains(.haptic(.detent))
            && flickDownFX.contains(.setPointerTrackpadVisible(false)))

    // Fast upward flick opens even when progress is low
    let flickUpFX = s.send(.deckDragEnded(progress: 0.12, velocityY: -450))
    check("deckDragEnded fast upward flick opens deck despite low progress",
          s.phoneDock == .controlDeck && s.deckDragProgress == 1
            && flickUpFX.contains(.haptic(.detent))
            && flickUpFX.contains(.setPointerTrackpadVisible(true)))

    // Idempotent setPhoneDeck
    let dupOpenFX = s.send(.setPhoneDeck(open: true))
    check("setPhoneDeck(open: true) when already open is no-op", dupOpenFX.isEmpty)

    // Opening deck while keyboard requested dismisses keyboard
    _ = s.send(.tapKeyboardButton)
    let deckOverKeyboardFX = s.send(.setPhoneDeck(open: true))
    check("setPhoneDeck(open: true) over keyboard dismisses keyboard and opens deck",
          s.phoneDock == .controlDeck && deckOverKeyboardFX.contains(.setKeyboard(shown: false))
            && deckOverKeyboardFX.contains(.setPointerTrackpadVisible(true)))

    // Non-phone-dock ignores deck actions
    var pad = StreamWorkspaceState(form: .padFullCanvas)
    let ignoredDrag = pad.send(.deckDragChanged(progress: 0.8))
    let ignoredEnd = pad.send(.deckDragEnded(progress: 0.8, velocityY: -500))
    let ignoredSet = pad.send(.setPhoneDeck(open: true))
    check("padFullCanvas ignores deck drag/end/set actions",
          ignoredDrag.isEmpty && ignoredEnd.isEmpty && ignoredSet.isEmpty
            && pad.deckDragProgress == 0 && pad.phoneDock == .focus)
}

// MARK: - 3. Keyboard ReturnTarget restoration across Focus / Deck / Modal

do {
    var s = StreamWorkspaceState(form: .phonePortrait)

    // Focus -> Keyboard -> tap again -> Focus
    let kb1 = s.send(.tapKeyboardButton)
    check("focus -> tapKeyboardButton enters .keyboard(returnTo: .focus) and shows keyboard",
          s.phoneDock == .keyboard(returnTo: .focus) && s.phoneDock.isKeyboardRequested
            && !s.phoneDock.isDeckVisible && kb1.contains(.setKeyboard(shown: true)))

    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    check("systemKeyboardChanged(true) shows keyboard accessory on software keyboard",
          s.personKeyboardUp && s.showsKeyboardAccessory)

    _ = s.send(.setHardwareKeyboardAttached(true))
    check("hardware keyboard attached hides software keyboard accessory",
          !s.showsKeyboardAccessory)
    _ = s.send(.setHardwareKeyboardAttached(false))
    check("hardware keyboard detached restores keyboard accessory", s.showsKeyboardAccessory)

    let kbOff = s.send(.tapKeyboardButton)
    check("tapKeyboardButton while keyboard up returns to .focus",
          s.phoneDock == .focus && kbOff.contains(.setKeyboard(shown: false)))
    _ = s.send(.systemKeyboardChanged(personOwnUp: false))

    // ControlDeck -> Keyboard -> Modal -> Close(restore: true) -> Dismiss -> ControlDeck
    _ = s.send(.setPhoneDeck(open: true))
    check("in controlDeck before keyboard", s.phoneDock == .controlDeck && s.pointerTrackpadActive)

    let fromDeckKB = s.send(.tapKeyboardButton)
    check("controlDeck -> tapKeyboardButton remembers returnTo: .controlDeck and hides trackpad",
          s.phoneDock == .keyboard(returnTo: .controlDeck) && !s.pointerTrackpadActive
            && fromDeckKB.contains(.setKeyboard(shown: true))
            && fromDeckKB.contains(.setPointerTrackpadVisible(false)))
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))

    let openSwitcher = s.send(.openModal(.switcher(initialSearch: true)))
    check("openModal while keyboard up sets restoreKeyboardAfterModal, hides keyboard, updates takers",
          s.modal == .switcher(initialSearch: true) && s.restoreKeyboardAfterModal
            && !s.showsKeyboardAccessory
            && openSwitcher.contains(.setKeyboard(shown: false))
            && openSwitcher.contains(.releaseHeldKeys)
            && openSwitcher.contains(.updateTakers([.drawer])))

    // System notifies keyboard went down while modal is open — must NOT wipe returnTo or restore flag
    _ = s.send(.systemKeyboardChanged(personOwnUp: false))
    check("systemKeyboardChanged(false) during modal preserves returnTo and restoreKeyboardAfterModal",
          !s.personKeyboardUp && s.restoreKeyboardAfterModal
            && s.phoneDock == .keyboard(returnTo: .controlDeck))

    let closeRestore = s.send(.closeModal(restoreKeyboard: true))
    check("closeModal(restoreKeyboard: true) re-raises keyboard and keeps returnTo: .controlDeck",
          s.modal == .none && !s.restoreKeyboardAfterModal
            && s.phoneDock == .keyboard(returnTo: .controlDeck)
            && closeRestore.contains(.setKeyboard(shown: true))
            && closeRestore.contains(.updateTakers([])))

    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    let sysDown = s.send(.systemKeyboardChanged(personOwnUp: false))
    check("systemKeyboardChanged(false) after modal restores controlDeck and trackpad",
          s.phoneDock == .controlDeck && s.deckDragProgress == 1 && s.pointerTrackpadActive
            && sysDown.contains(.setPointerTrackpadVisible(true)))

    // ControlDeck -> Keyboard -> Modal -> Close(restore: false) -> immediately back to ControlDeck
    _ = s.send(.tapKeyboardButton)
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    _ = s.send(.openModal(.controlCenter(.root)))
    _ = s.send(.systemKeyboardChanged(personOwnUp: false))
    let closeNoRestore = s.send(.closeModal(restoreKeyboard: false))
    check("closeModal(restoreKeyboard: false) does not raise keyboard and restores controlDeck",
          s.modal == .none && !s.restoreKeyboardAfterModal
            && s.phoneDock == .controlDeck && s.deckDragProgress == 1
            && !closeNoRestore.contains(.setKeyboard(shown: true))
            && closeNoRestore.contains(.setPointerTrackpadVisible(true)))

    // Dismiss keyboard via accessory button restores controlDeck
    _ = s.send(.tapKeyboardButton)
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))
    let dismissFX = s.send(.dismissKeyboardRequested)
    check("dismissKeyboardRequested returns from keyboard to controlDeck",
          s.phoneDock == .controlDeck && s.deckDragProgress == 1
            && dismissFX.contains(.setKeyboard(shown: false))
            && dismissFX.contains(.setPointerTrackpadVisible(true)))

    // Pad form uses .toggleKeyboard on tapKeyboardButton
    var pad = StreamWorkspaceState(form: .padFullCanvas)
    let padToggle = pad.send(.tapKeyboardButton)
    check("padFullCanvas tapKeyboardButton emits .toggleKeyboard",
          padToggle.contains(.toggleKeyboard) && padToggle.contains(.haptic(.tick)))
}

// MARK: - 4. Swipe-on-chip window cycling & wraparound

do {
    var s = StreamWorkspaceState(form: .phonePortrait)
    let ids: [UInt32] = [101, 202, 303]

    let next1 = s.send(.swipeWindowChip(direction: 1, orderedWindowIDs: ids, active: .window(101)))
    check("swipe +1 from first selects second",
          next1 == [.selectSource(.window(202)), .haptic(.tick)])

    let wrapForward = s.send(.swipeWindowChip(direction: 1, orderedWindowIDs: ids, active: .window(303)))
    check("swipe +1 from last wraps to first",
          wrapForward == [.selectSource(.window(101)), .haptic(.tick)])

    let wrapBackward = s.send(.swipeWindowChip(direction: -1, orderedWindowIDs: ids, active: .window(101)))
    check("swipe -1 from first wraps to last",
          wrapBackward == [.selectSource(.window(303)), .haptic(.tick)])

    let fromDesktopFwd = s.send(.swipeWindowChip(direction: 1, orderedWindowIDs: ids, active: .desktop))
    check("swipe +1 from desktop selects first window",
          fromDesktopFwd == [.selectSource(.window(101)), .haptic(.tick)])

    let fromDesktopBack = s.send(.swipeWindowChip(direction: -1, orderedWindowIDs: ids, active: .desktop))
    check("swipe -1 from desktop selects last window",
          fromDesktopBack == [.selectSource(.window(303)), .haptic(.tick)])

    let fromMissing = s.send(.swipeWindowChip(direction: 1, orderedWindowIDs: ids, active: .window(999)))
    check("swipe +1 from unknown window ID selects first window",
          fromMissing == [.selectSource(.window(101)), .haptic(.tick)])

    let singleSame = s.send(.swipeWindowChip(direction: 1, orderedWindowIDs: [101], active: .window(101)))
    check("swipe on single already-active window warns without selecting",
          singleSame == [.haptic(.warning)])

    let singleFromNone = s.send(.swipeWindowChip(direction: 1, orderedWindowIDs: [101], active: .none))
    check("swipe on single window from .none selects it",
          singleFromNone == [.selectSource(.window(101)), .haptic(.tick)])

    let emptyList = s.send(.swipeWindowChip(direction: 1, orderedWindowIDs: [], active: .none))
    check("swipe on empty window list warns", emptyList == [.haptic(.warning)])

    let zeroDir = s.send(.swipeWindowChip(direction: 0, orderedWindowIDs: ids, active: .window(101)))
    check("swipe with direction 0 is no-op", zeroDir.isEmpty)
}

// MARK: - 5. Viewport stability when deck opens/closes

do {
    var s = StreamWorkspaceState(form: .phonePortrait)
    let focusSize = WorkspaceSize(width: 402, height: 730)

    let badSize = s.send(.focusCanvasMeasured(WorkspaceSize(width: 0, height: 730)))
    check("zero-width focusCanvasMeasured is ignored",
          badSize.isEmpty && s.committedCanvasSize == WorkspaceSize(width: 0, height: 0))

    let initFX = s.send(.focusCanvasMeasured(focusSize))
    check("first focusCanvasMeasured commits with .initialCanvas",
          s.committedCanvasSize == focusSize
            && initFX == [.commitViewport(focusSize, reason: .initialCanvas)])

    let sameFX = s.send(.focusCanvasMeasured(focusSize))
    check("identical focusCanvasMeasured is no-op", sameFX.isEmpty)

    // Dragging deck & opening deck never commit viewport, and ignore shrunk canvas measurements
    let dragFX = s.send(.deckDragChanged(progress: 0.5))
    let shrunkDuringDrag = s.send(.focusCanvasMeasured(WorkspaceSize(width: 402, height: 420)))
    let openDeckFX = s.send(.setPhoneDeck(open: true))
    let shrunkWhileOpen = s.send(.focusCanvasMeasured(WorkspaceSize(width: 402, height: 300)))
    let closeDeckFX = s.send(.setPhoneDeck(open: false))
    let noViewportEffects = (dragFX + shrunkDuringDrag + openDeckFX + shrunkWhileOpen + closeDeckFX)
        .filter { if case .commitViewport = $0 { return true }; return false }
    check("viewport stays locked to focusSize while deck drags, opens, and closes",
          s.committedCanvasSize == focusSize && noViewportEffects.isEmpty)

    // Keyboard up also preserves committed focusSize
    _ = s.send(.tapKeyboardButton)
    let shrunkWhileKB = s.send(.focusCanvasMeasured(WorkspaceSize(width: 402, height: 390)))
    check("viewport stays locked while phone keyboard is up",
          s.committedCanvasSize == focusSize && shrunkWhileKB.isEmpty)
    _ = s.send(.tapKeyboardButton)

    // Real resize in Focus commits .formOrSizeChanged
    let resized = WorkspaceSize(width: 440, height: 810)
    let resizeFX = s.send(.focusCanvasMeasured(resized))
    check("real resize in focus commits .formOrSizeChanged",
          s.committedCanvasSize == resized
            && resizeFX == [.commitViewport(resized, reason: .formOrSizeChanged)])

    // Form switch + same-size measure still commits .formOrSizeChanged
    _ = s.send(.setForm(.padFullCanvas))
    let padSize = WorkspaceSize(width: 1112, height: 834)
    let padMeasureFX = s.send(.focusCanvasMeasured(padSize))
    check("focusCanvasMeasured after setForm commits .formOrSizeChanged",
          s.committedCanvasSize == padSize
            && padMeasureFX == [.commitViewport(padSize, reason: .formOrSizeChanged)])

    // Text scale commit
    let textFX = s.send(.textScaleCommitted)
    check("textScaleCommitted emits .textScaleChanged and detent",
          textFX.contains(.commitViewport(padSize, reason: .textScaleChanged))
            && textFX.contains(.haptic(.detent)))
}

// MARK: - 6. Capsule tuck/untuck & edge switching

do {
    var pad = StreamWorkspaceState(form: .padFullCanvas)
    check("initial capsule is expanded at top",
          pad.capsule == .expanded(edge: .top) && !pad.capsule.isTucked && pad.capsule.edge == .top)

    let tuckFX = pad.send(.toggleCapsuleTuck)
    check("toggleCapsuleTuck tucks at top with detent",
          pad.capsule == .tucked(edge: .top) && pad.capsule.isTucked && tuckFX == [.haptic(.detent)])

    let edgeFX = pad.send(.setCapsuleEdge(.bottom))
    check("setCapsuleEdge(.bottom) preserves tucked state",
          pad.capsule == .tucked(edge: .bottom) && pad.capsule.isTucked && pad.capsule.edge == .bottom
            && edgeFX == [.haptic(.detent)])

    let edgeNoop = pad.send(.setCapsuleEdge(.bottom))
    check("setCapsuleEdge to same edge is no-op", edgeNoop.isEmpty)

    let untuckFX = pad.send(.toggleCapsuleTuck)
    check("toggleCapsuleTuck untucks at bottom",
          pad.capsule == .expanded(edge: .bottom) && !pad.capsule.isTucked && untuckFX == [.haptic(.detent)])

    var phone = StreamWorkspaceState(form: .phonePortrait)
    check("phonePortrait ignores capsule tuck and edge actions",
          phone.send(.toggleCapsuleTuck).isEmpty && phone.send(.setCapsuleEdge(.bottom)).isEmpty)
}

// MARK: - 7. Floating pad visibility & anchor clamping

do {
    var pad = StreamWorkspaceState(form: .padFullCanvas)
    check("floatingPad defaults hidden at (0.78, 0.72)",
          !pad.floatingPad.isVisible && pad.floatingPad.anchor == WorkspacePoint(x: 0.78, y: 0.72))

    let showFX = pad.send(.toggleFloatingPad)
    check("toggleFloatingPad shows pad and emits pointer trackpad visible",
          pad.floatingPad.isVisible && pad.pointerTrackpadActive
            && showFX.contains(.setPointerTrackpadVisible(true))
            && showFX.contains(.haptic(.detent)))

    _ = pad.send(.moveFloatingPad(anchor: WorkspacePoint(x: -1.0, y: 2.5)))
    check("moveFloatingPad clamps out-of-bounds coordinates inside safe normalized bounds",
          pad.floatingPad.anchor.x == StreamWorkspaceState.floatingPadAnchorXBounds.lowerBound
            && pad.floatingPad.anchor.y == StreamWorkspaceState.floatingPadAnchorYBounds.upperBound)

    _ = pad.send(.moveFloatingPad(anchor: WorkspacePoint(x: 0.35, y: 0.45)))
    check("moveFloatingPad accepts valid in-bounds coordinates",
          pad.floatingPad.anchor == WorkspacePoint(x: 0.35, y: 0.45))

    _ = pad.send(.moveFloatingPad(anchor: WorkspacePoint(x: .nan, y: 0.5)))
    check("moveFloatingPad ignores NaN coordinates",
          pad.floatingPad.anchor == WorkspacePoint(x: 0.35, y: 0.45))

    let hideFX = pad.send(.toggleFloatingPad)
    check("toggleFloatingPad hides pad and disables pointer trackpad",
          !pad.floatingPad.isVisible && !pad.pointerTrackpadActive
            && hideFX.contains(.setPointerTrackpadVisible(false)))
}

// MARK: - 8. Full-screen hide/show

do {
    var s = StreamWorkspaceState(form: .phonePortrait)
    let size = WorkspaceSize(width: 402, height: 730)
    _ = s.send(.focusCanvasMeasured(size))
    _ = s.send(.systemKeyboardChanged(personOwnUp: true))

    let hideFX = s.send(.setFullScreenHidden(true))
    check("setFullScreenHidden(true) hides dock, deck, accessory and commits .chromeToggled",
          s.fullScreenHidden && !s.showsPhoneDock && !s.showsPhoneDeck && !s.showsKeyboardAccessory
            && hideFX.contains(.commitViewport(size, reason: .chromeToggled))
            && hideFX.contains(.haptic(.detent)))

    let dupHide = s.send(.setFullScreenHidden(true))
    check("setFullScreenHidden(true) again is no-op", dupHide.isEmpty)

    let showFX = s.send(.setFullScreenHidden(false))
    check("setFullScreenHidden(false) restores visibility and commits .chromeToggled",
          !s.fullScreenHidden && s.showsKeyboardAccessory
            && showFX.contains(.commitViewport(size, reason: .chromeToggled)))

    var pad = StreamWorkspaceState(form: .padFullCanvas)
    _ = pad.send(.setFullScreenHidden(true))
    check("padFullCanvas hides floating capsule when fullScreenHidden", !pad.showsFloatingCapsule)
    _ = pad.send(.setFullScreenHidden(false))
    check("padFullCanvas restores floating capsule when unhidden", pad.showsFloatingCapsule)
}

// MARK: - 9. Keyboard takers derivation & Control Center routes

do {
    var s = StreamWorkspaceState(form: .padFullCanvas)
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

// MARK: - 10. Scene deactivation

do {
    var s = StreamWorkspaceState(form: .phonePortrait)
    _ = s.send(.deckDragChanged(progress: 0.42))
    let fx = s.send(.sceneDeactivated)
    check("sceneDeactivated releases held keys, clears latched modifiers, and settles drag progress",
          fx == [.releaseHeldKeys, .clearLatchedModifiers] && s.deckDragProgress == 0)
}

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
