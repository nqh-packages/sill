public struct WorkspacePoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct WorkspaceSize: Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum WorkspaceForm: Equatable, Hashable, Sendable {
    case phonePortrait
    case phoneLandscape
    case padFullCanvas
    case duoBook
    case duoLaptop

    public var usesPhoneDock: Bool {
        self == .phonePortrait
    }

    public var usesFloatingCapsule: Bool {
        switch self {
        case .phoneLandscape, .padFullCanvas, .duoBook:
            return true
        case .phonePortrait, .duoLaptop:
            return false
        }
    }
}

public enum WorkspaceSource: Equatable, Hashable, Sendable {
    case none
    case desktop
    case window(UInt32)
}

public enum WorkspaceModal: Equatable, Hashable, Sendable {
    public enum ControlCenterRoute: Equatable, Hashable, Sendable {
        case root
        case macMenus
    }

    case none
    case switcher(initialSearch: Bool = false)
    case controlCenter(ControlCenterRoute = .root)
    case menusPullDown
    case pairingOverlay
    case tour
}

public enum PhoneDockMode: Equatable, Hashable, Sendable {
    public enum ReturnTarget: Equatable, Hashable, Sendable {
        case focus
        case controlDeck
    }

    case focus
    case controlDeck
    case keyboard(returnTo: ReturnTarget)

    public var isKeyboardRequested: Bool {
        if case .keyboard = self { return true }
        return false
    }

    public var isDeckVisible: Bool {
        self == .controlDeck
    }
}

public enum CapsuleEdge: Equatable, Hashable, Sendable {
    case top
    case bottom
}

public enum CapsuleVisibility: Equatable, Hashable, Sendable {
    case expanded(edge: CapsuleEdge)
    case tucked(edge: CapsuleEdge)

    public var isTucked: Bool {
        if case .tucked = self { return true }
        return false
    }

    public var edge: CapsuleEdge {
        switch self {
        case .expanded(let edge), .tucked(let edge):
            return edge
        }
    }
}

public struct FloatingPadState: Equatable, Hashable, Sendable {
    public var isVisible: Bool
    public var anchor: WorkspacePoint

    public init(isVisible: Bool = false, anchor: WorkspacePoint = WorkspacePoint(x: 0.78, y: 0.72)) {
        self.isVisible = isVisible
        self.anchor = anchor
    }
}

public enum WorkspaceKeyboardTaker: String, Hashable, CaseIterable, Sendable {
    case settings
    case pairing
    case tour
    case drawer
    case menus
}

public enum HapticCue: Equatable, Hashable, Sendable {
    case detent
    case tick
    case keyPress
    case modifierLatch
    case modifierRelease
    case warning
}

public enum ViewportCommitReason: Equatable, Hashable, Sendable {
    case initialCanvas
    case formOrSizeChanged
    case textScaleChanged
    case chromeToggled
}

public struct StreamWorkspaceState: Equatable, Sendable {
    public static let deckOpenProgressThreshold: Double = 0.5
    public static let deckFlickVelocityThreshold: Double = 300.0
    public static let floatingPadAnchorXBounds: ClosedRange<Double> = 0.10...0.90
    public static let floatingPadAnchorYBounds: ClosedRange<Double> = 0.10...0.90

    public private(set) var form: WorkspaceForm
    public private(set) var modal: WorkspaceModal = .none
    public private(set) var phoneDock: PhoneDockMode = .focus
    public private(set) var capsule: CapsuleVisibility = .expanded(edge: .top)
    public private(set) var floatingPad: FloatingPadState = FloatingPadState()
    public private(set) var restoreKeyboardAfterModal: Bool = false
    public private(set) var personKeyboardUp: Bool = false
    public private(set) var hardwareKeyboardAttached: Bool
    public private(set) var committedCanvasSize: WorkspaceSize = WorkspaceSize(width: 0, height: 0)
    public private(set) var deckDragProgress: Double = 0
    public private(set) var fullScreenHidden: Bool = false

    private var pendingFormViewportCommit: Bool = false

    public init(form: WorkspaceForm, hardwareKeyboardAttached: Bool = false) {
        self.form = form
        self.hardwareKeyboardAttached = hardwareKeyboardAttached
    }

    public var keyboardTakers: Set<WorkspaceKeyboardTaker> {
        switch modal {
        case .none:
            return []
        case .switcher:
            return [.drawer]
        case .controlCenter(let route):
            switch route {
            case .root:
                return [.settings]
            case .macMenus:
                return [.settings, .menus]
            }
        case .menusPullDown:
            return [.menus]
        case .pairingOverlay:
            return [.pairing]
        case .tour:
            return [.tour]
        }
    }

    public var pointerTrackpadActive: Bool {
        (form.usesPhoneDock && phoneDock == .controlDeck)
            || (form.usesFloatingCapsule && floatingPad.isVisible)
    }

    public var showsPhoneDock: Bool {
        form.usesPhoneDock && !fullScreenHidden && phoneDock == .focus
    }

    public var showsPhoneDeck: Bool {
        form.usesPhoneDock && !fullScreenHidden && phoneDock == .controlDeck
    }

    public var showsFloatingCapsule: Bool {
        form.usesFloatingCapsule && !fullScreenHidden
    }

    public var showsKeyboardAccessory: Bool {
        personKeyboardUp && !hardwareKeyboardAttached && !fullScreenHidden && modal == .none
    }

    public enum Action: Equatable, Sendable {
        case setForm(WorkspaceForm)
        case setHardwareKeyboardAttached(Bool)
        case focusCanvasMeasured(WorkspaceSize)
        case deckDragChanged(progress: Double)
        case deckDragEnded(progress: Double, velocityY: Double)
        case setPhoneDeck(open: Bool)
        case tapKeyboardButton
        case dismissKeyboardRequested
        case systemKeyboardChanged(personOwnUp: Bool)
        case swipeWindowChip(direction: Int, orderedWindowIDs: [UInt32], active: WorkspaceSource)
        case openModal(WorkspaceModal)
        case closeModal(restoreKeyboard: Bool = true)
        case setControlCenterRoute(WorkspaceModal.ControlCenterRoute)
        case toggleCapsuleTuck
        case setCapsuleEdge(CapsuleEdge)
        case toggleFloatingPad
        case moveFloatingPad(anchor: WorkspacePoint)
        case setFullScreenHidden(Bool)
        case sceneDeactivated
        case textScaleCommitted
    }

    public enum Effect: Equatable, Sendable {
        case setKeyboard(shown: Bool)
        case toggleKeyboard
        case updateTakers(Set<WorkspaceKeyboardTaker>)
        case setPointerTrackpadVisible(Bool)
        case selectSource(WorkspaceSource)
        case commitViewport(WorkspaceSize, reason: ViewportCommitReason)
        case haptic(HapticCue)
        case releaseHeldKeys
        case clearLatchedModifiers
    }

    private var hasCommittedCanvas: Bool {
        committedCanvasSize.width > 0 && committedCanvasSize.height > 0
    }

    @discardableResult
    public mutating func send(_ action: Action) -> [Effect] {
        let previousTakers = keyboardTakers
        let previousTrackpad = pointerTrackpadActive
        var effects: [Effect] = []

        switch action {
        case .setForm(let newForm):
            if newForm != form {
                form = newForm
                pendingFormViewportCommit = hasCommittedCanvas
                if form.usesPhoneDock {
                    if personKeyboardUp && modal == .none {
                        phoneDock = .keyboard(returnTo: .focus)
                        deckDragProgress = 0
                    } else {
                        deckDragProgress = phoneDock == .controlDeck ? 1 : 0
                    }
                } else {
                    phoneDock = .focus
                    deckDragProgress = 0
                }
            }

        case .setHardwareKeyboardAttached(let attached):
            hardwareKeyboardAttached = attached

        case .focusCanvasMeasured(let size):
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                break
            }
            if !hasCommittedCanvas {
                committedCanvasSize = size
                pendingFormViewportCommit = false
                effects.append(.commitViewport(size, reason: .initialCanvas))
            } else if form.usesPhoneDock && deckDragProgress > 0 && deckDragProgress < 1 {
                break
            } else if pendingFormViewportCommit
                || abs(size.width - committedCanvasSize.width) >= 0.5
                || abs(size.height - committedCanvasSize.height) >= 0.5
            {
                committedCanvasSize = size
                pendingFormViewportCommit = false
                effects.append(.commitViewport(size, reason: .formOrSizeChanged))
            }

        case .deckDragChanged(let progress):
            guard form.usesPhoneDock, !fullScreenHidden, modal == .none, progress.isFinite else {
                break
            }
            deckDragProgress = Self.clamp(progress, to: 0...1)

        case .deckDragEnded(let progress, let velocityY):
            guard form.usesPhoneDock else { break }
            let clamped = progress.isFinite ? Self.clamp(progress, to: 0...1) : deckDragProgress
            let open: Bool
            if velocityY.isFinite && velocityY <= -Self.deckFlickVelocityThreshold {
                open = true
            } else if velocityY.isFinite && velocityY >= Self.deckFlickVelocityThreshold {
                open = false
            } else {
                open = clamped >= Self.deckOpenProgressThreshold
            }
            applyPhoneDeck(open: open, effects: &effects)

        case .setPhoneDeck(let open):
            guard form.usesPhoneDock else { break }
            applyPhoneDeck(open: open, effects: &effects)

        case .tapKeyboardButton:
            if form.usesPhoneDock {
                switch phoneDock {
                case .focus:
                    if personKeyboardUp {
                        effects.append(.setKeyboard(shown: false))
                    } else {
                        phoneDock = .keyboard(returnTo: .focus)
                        deckDragProgress = 0
                        effects.append(.setKeyboard(shown: true))
                    }
                    effects.append(.haptic(.tick))
                case .controlDeck:
                    phoneDock = .keyboard(returnTo: .controlDeck)
                    deckDragProgress = 0
                    effects.append(.setKeyboard(shown: true))
                    effects.append(.haptic(.tick))
                case .keyboard(let returnTo):
                    restorePhoneDock(to: returnTo)
                    effects.append(.setKeyboard(shown: false))
                    effects.append(.haptic(.tick))
                }
            } else {
                effects.append(.toggleKeyboard)
                effects.append(.haptic(.tick))
            }

        case .dismissKeyboardRequested:
            if form.usesPhoneDock {
                switch phoneDock {
                case .keyboard(let returnTo):
                    restorePhoneDock(to: returnTo)
                    effects.append(.setKeyboard(shown: false))
                    effects.append(.haptic(.tick))
                case .focus, .controlDeck:
                    if personKeyboardUp {
                        effects.append(.setKeyboard(shown: false))
                        effects.append(.haptic(.tick))
                    }
                }
            } else if personKeyboardUp {
                effects.append(.setKeyboard(shown: false))
                effects.append(.haptic(.tick))
            }

        case .systemKeyboardChanged(let personOwnUp):
            let wasUp = personKeyboardUp
            personKeyboardUp = personOwnUp
            if form.usesPhoneDock && modal == .none {
                if personOwnUp {
                    if !phoneDock.isKeyboardRequested {
                        let target: PhoneDockMode.ReturnTarget = (phoneDock == .controlDeck) ? .controlDeck : .focus
                        phoneDock = .keyboard(returnTo: target)
                        deckDragProgress = 0
                    }
                } else if wasUp, case .keyboard(let returnTo) = phoneDock {
                    restorePhoneDock(to: returnTo)
                }
            }

        case .swipeWindowChip(let direction, let orderedWindowIDs, let active):
            guard direction != 0 else { break }
            guard !orderedWindowIDs.isEmpty else {
                effects.append(.haptic(.warning))
                break
            }
            let step = direction > 0 ? 1 : -1
            if case .window(let activeID) = active, let index = orderedWindowIDs.firstIndex(of: activeID) {
                guard orderedWindowIDs.count > 1 else {
                    effects.append(.haptic(.warning))
                    break
                }
                let count = orderedWindowIDs.count
                let nextIndex = ((index + step) % count + count) % count
                effects.append(.selectSource(.window(orderedWindowIDs[nextIndex])))
                effects.append(.haptic(.tick))
            } else {
                let targetID = step > 0 ? orderedWindowIDs[0] : orderedWindowIDs[orderedWindowIDs.count - 1]
                effects.append(.selectSource(.window(targetID)))
                effects.append(.haptic(.tick))
            }

        case .openModal(let newModal):
            if newModal == .none {
                closeCurrentModal(restoreKeyboard: true, effects: &effects)
                break
            }
            guard newModal != modal else { break }
            let keyboardActive = personKeyboardUp || (modal == .none && form.usesPhoneDock && phoneDock.isKeyboardRequested)
            if modal == .none {
                restoreKeyboardAfterModal = keyboardActive
            } else if keyboardActive {
                restoreKeyboardAfterModal = true
            }
            if keyboardActive {
                effects.append(.setKeyboard(shown: false))
            }
            modal = newModal
            effects.append(.releaseHeldKeys)
            effects.append(.haptic(.tick))

        case .closeModal(let restoreKeyboard):
            closeCurrentModal(restoreKeyboard: restoreKeyboard, effects: &effects)

        case .setControlCenterRoute(let route):
            guard case .controlCenter(let currentRoute) = modal, currentRoute != route else { break }
            modal = .controlCenter(route)
            effects.append(.haptic(.tick))

        case .toggleCapsuleTuck:
            guard form.usesFloatingCapsule else { break }
            switch capsule {
            case .expanded(let edge):
                capsule = .tucked(edge: edge)
            case .tucked(let edge):
                capsule = .expanded(edge: edge)
            }
            effects.append(.haptic(.detent))

        case .setCapsuleEdge(let edge):
            guard form.usesFloatingCapsule, capsule.edge != edge else { break }
            capsule = capsule.isTucked ? .tucked(edge: edge) : .expanded(edge: edge)
            effects.append(.haptic(.detent))

        case .toggleFloatingPad:
            guard form.usesFloatingCapsule else { break }
            floatingPad.isVisible.toggle()
            effects.append(.haptic(.detent))

        case .moveFloatingPad(let anchor):
            guard anchor.x.isFinite, anchor.y.isFinite else { break }
            let clamped = WorkspacePoint(
                x: Self.clamp(anchor.x, to: Self.floatingPadAnchorXBounds),
                y: Self.clamp(anchor.y, to: Self.floatingPadAnchorYBounds)
            )
            floatingPad.anchor = clamped

        case .setFullScreenHidden(let hidden):
            guard hidden != fullScreenHidden else { break }
            fullScreenHidden = hidden
            effects.append(.haptic(.detent))
            if hasCommittedCanvas {
                effects.append(.commitViewport(committedCanvasSize, reason: .chromeToggled))
            }

        case .sceneDeactivated:
            if form.usesPhoneDock {
                deckDragProgress = phoneDock == .controlDeck ? 1 : 0
            }
            effects.append(.releaseHeldKeys)
            effects.append(.clearLatchedModifiers)

        case .textScaleCommitted:
            effects.append(.haptic(.detent))
            if hasCommittedCanvas {
                effects.append(.commitViewport(committedCanvasSize, reason: .textScaleChanged))
            }
        }

        if keyboardTakers != previousTakers {
            effects.append(.updateTakers(keyboardTakers))
        }
        if pointerTrackpadActive != previousTrackpad {
            effects.append(.setPointerTrackpadVisible(pointerTrackpadActive))
        }
        return effects
    }

    private mutating func applyPhoneDeck(open: Bool, effects: inout [Effect]) {
        let targetMode: PhoneDockMode = open ? .controlDeck : .focus
        let targetProgress: Double = open ? 1 : 0
        if phoneDock == targetMode && deckDragProgress == targetProgress {
            return
        }
        if open && (phoneDock.isKeyboardRequested || personKeyboardUp) {
            effects.append(.setKeyboard(shown: false))
        }
        let modeChanged = phoneDock != targetMode
        phoneDock = targetMode
        deckDragProgress = targetProgress
        if modeChanged {
            effects.append(.haptic(.detent))
        }
    }

    private mutating func restorePhoneDock(to target: PhoneDockMode.ReturnTarget) {
        switch target {
        case .focus:
            phoneDock = .focus
            deckDragProgress = 0
        case .controlDeck:
            phoneDock = .controlDeck
            deckDragProgress = 1
        }
    }

    private mutating func closeCurrentModal(restoreKeyboard: Bool, effects: inout [Effect]) {
        guard modal != .none else { return }
        modal = .none
        let shouldRestore = restoreKeyboard && restoreKeyboardAfterModal
        restoreKeyboardAfterModal = false
        if shouldRestore {
            effects.append(.setKeyboard(shown: true))
        } else if form.usesPhoneDock, case .keyboard(let returnTo) = phoneDock {
            restorePhoneDock(to: returnTo)
        }
    }

    private static func clamp(_ value: Double, to bounds: ClosedRange<Double>) -> Double {
        if value < bounds.lowerBound { return bounds.lowerBound }
        if value > bounds.upperBound { return bounds.upperBound }
        return value
    }
}
