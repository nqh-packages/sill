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

public enum CapsuleEdge: Equatable, Hashable, Sendable {
    case top
    case bottom
    case leading
    case trailing

    public var isVertical: Bool {
        self == .leading || self == .trailing
    }

    public var defaultMinimizeCorner: CapsuleCorner {
        switch self {
        case .top: return .topTrailing
        case .bottom: return .bottomTrailing
        case .leading: return .bottomLeading
        case .trailing: return .bottomTrailing
        }
    }
}

public enum CapsuleCorner: Equatable, Hashable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    public var defaultExpandEdge: CapsuleEdge {
        switch self {
        case .topLeading, .topTrailing: return .top
        case .bottomLeading, .bottomTrailing: return .bottom
        }
    }

    public func isAdjacent(to edge: CapsuleEdge) -> Bool {
        switch (self, edge) {
        case (.topLeading, .top), (.topLeading, .leading),
             (.topTrailing, .top), (.topTrailing, .trailing),
             (.bottomLeading, .bottom), (.bottomLeading, .leading),
             (.bottomTrailing, .bottom), (.bottomTrailing, .trailing):
            return true
        default:
            return false
        }
    }

    public func resolvedReturnEdge(from previous: CapsuleEdge) -> CapsuleEdge {
        isAdjacent(to: previous) ? previous : defaultExpandEdge
    }
}

public enum CapsuleVisibility: Equatable, Hashable, Sendable {
    case expanded(edge: CapsuleEdge)
    case minimized(corner: CapsuleCorner, returnEdge: CapsuleEdge)

    public var isMinimized: Bool {
        if case .minimized = self { return true }
        return false
    }

    public var isTucked: Bool { isMinimized }

    public var edge: CapsuleEdge {
        switch self {
        case .expanded(let edge):
            return edge
        case .minimized(_, let returnEdge):
            return returnEdge
        }
    }

    public var corner: CapsuleCorner? {
        if case .minimized(let corner, _) = self { return corner }
        return nil
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
    public static let capsuleCornerZoneX: Double = 0.20
    public static let capsuleCornerZoneY: Double = 0.22
    /// Width threshold below which the trackpad docks as a bottom-anchored Control Deck
    /// matching the software keyboard footprint instead of floating as a 320×260 card.
    public static let compactTrackpadMaxWidth: Double = 600.0

    public private(set) var modal: WorkspaceModal = .none
    public private(set) var capsule: CapsuleVisibility = .expanded(edge: .bottom)
    public private(set) var floatingPad: FloatingPadState = FloatingPadState()
    public private(set) var restoreKeyboardAfterModal: Bool = false
    public private(set) var personKeyboardUp: Bool = false
    public private(set) var hardwareKeyboardAttached: Bool
    public private(set) var committedCanvasSize: WorkspaceSize = WorkspaceSize(width: 0, height: 0)
    public private(set) var deckDragProgress: Double = 0
    public private(set) var fullScreenHidden: Bool = false

    public init(hardwareKeyboardAttached: Bool = false) {
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
        floatingPad.isVisible
    }

    public var showsFloatingCapsule: Bool {
        !fullScreenHidden
    }

    public var showsKeyboardAccessory: Bool {
        personKeyboardUp && !hardwareKeyboardAttached && !fullScreenHidden && modal == .none
    }

    public enum Action: Equatable, Sendable {
        case setHardwareKeyboardAttached(Bool)
        case focusCanvasMeasured(WorkspaceSize)
        case deckDragChanged(progress: Double)
        case deckDragEnded(progress: Double, velocityY: Double)
        case setTrackpad(open: Bool)
        case toggleFloatingPad
        case moveFloatingPad(anchor: WorkspacePoint)
        case tapKeyboardButton
        case dismissKeyboardRequested
        case systemKeyboardChanged(personOwnUp: Bool)
        case openModal(WorkspaceModal)
        case closeModal(restoreKeyboard: Bool = true)
        case setControlCenterRoute(WorkspaceModal.ControlCenterRoute)
        case toggleCapsuleTuck
        case setCapsuleEdge(CapsuleEdge)
        case snapCapsule(normalizedProjectedPoint: WorkspacePoint)
        case expandCapsule(edge: CapsuleEdge? = nil)
        case minimizeCapsule(corner: CapsuleCorner)
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
        case .setHardwareKeyboardAttached(let attached):
            hardwareKeyboardAttached = attached

        case .focusCanvasMeasured(let size):
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                break
            }
            if !hasCommittedCanvas {
                committedCanvasSize = size
                effects.append(.commitViewport(size, reason: .initialCanvas))
            } else if deckDragProgress > 0 && deckDragProgress < 1 {
                break
            } else if abs(size.width - committedCanvasSize.width) >= 0.5
                || abs(size.height - committedCanvasSize.height) >= 0.5
            {
                committedCanvasSize = size
                effects.append(.commitViewport(size, reason: .formOrSizeChanged))
            }

        case .deckDragChanged(let progress):
            guard !fullScreenHidden, modal == .none, progress.isFinite else {
                break
            }
            deckDragProgress = Self.clamp(progress, to: 0...1)

        case .deckDragEnded(let progress, let velocityY):
            let clamped = progress.isFinite ? Self.clamp(progress, to: 0...1) : deckDragProgress
            let open: Bool
            if velocityY.isFinite && velocityY <= -Self.deckFlickVelocityThreshold {
                open = true
            } else if velocityY.isFinite && velocityY >= Self.deckFlickVelocityThreshold {
                open = false
            } else {
                open = clamped >= Self.deckOpenProgressThreshold
            }
            applyTrackpad(open: open, effects: &effects)

        case .setTrackpad(let open):
            applyTrackpad(open: open, effects: &effects)

        case .toggleFloatingPad:
            applyTrackpad(open: !floatingPad.isVisible, effects: &effects)

        case .moveFloatingPad(let anchor):
            guard anchor.x.isFinite, anchor.y.isFinite else { break }
            floatingPad.anchor = WorkspacePoint(
                x: Self.clamp(anchor.x, to: Self.floatingPadAnchorXBounds),
                y: Self.clamp(anchor.y, to: Self.floatingPadAnchorYBounds)
            )

        case .tapKeyboardButton:
            if personKeyboardUp {
                effects.append(.setKeyboard(shown: false))
            } else {
                if floatingPad.isVisible {
                    floatingPad.isVisible = false
                    deckDragProgress = 0
                }
                effects.append(.toggleKeyboard)
            }
            effects.append(.haptic(.tick))

        case .dismissKeyboardRequested:
            if personKeyboardUp {
                effects.append(.setKeyboard(shown: false))
                effects.append(.haptic(.tick))
            }

        case .systemKeyboardChanged(let personOwnUp):
            personKeyboardUp = personOwnUp

        case .openModal(let newModal):
            if newModal == .none {
                closeCurrentModal(restoreKeyboard: true, effects: &effects)
                break
            }
            guard newModal != modal else { break }
            if modal == .none {
                restoreKeyboardAfterModal = personKeyboardUp
            } else if personKeyboardUp {
                restoreKeyboardAfterModal = true
            }
            if personKeyboardUp {
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
            switch capsule {
            case .expanded(let edge):
                capsule = .minimized(corner: edge.defaultMinimizeCorner, returnEdge: edge)
            case .minimized(_, let returnEdge):
                capsule = .expanded(edge: returnEdge)
            }
            effects.append(.haptic(.detent))

        case .setCapsuleEdge(let edge):
            guard capsule.edge != edge else { break }
            switch capsule {
            case .expanded:
                capsule = .expanded(edge: edge)
            case .minimized(let corner, _):
                capsule = .minimized(corner: corner, returnEdge: edge)
            }
            effects.append(.haptic(.detent))

        case .snapCapsule(let point):
            guard let target = Self.capsuleSnapTarget(for: point, currentEdge: capsule.edge) else { break }
            if target != capsule {
                capsule = target
                effects.append(.haptic(.detent))
            }

        case .expandCapsule(let edge):
            let target = CapsuleVisibility.expanded(edge: edge ?? capsule.edge)
            if target != capsule {
                capsule = target
                effects.append(.haptic(.detent))
            }

        case .minimizeCapsule(let corner):
            let target = CapsuleVisibility.minimized(
                corner: corner,
                returnEdge: corner.resolvedReturnEdge(from: capsule.edge)
            )
            if target != capsule {
                capsule = target
                effects.append(.haptic(.detent))
            }

        case .setFullScreenHidden(let hidden):
            guard hidden != fullScreenHidden else { break }
            fullScreenHidden = hidden
            effects.append(.haptic(.detent))
            if hasCommittedCanvas {
                effects.append(.commitViewport(committedCanvasSize, reason: .chromeToggled))
            }

        case .sceneDeactivated:
            deckDragProgress = floatingPad.isVisible ? 1 : 0
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

    private mutating func applyTrackpad(open: Bool, effects: inout [Effect]) {
        let targetProgress: Double = open ? 1 : 0
        if floatingPad.isVisible == open && deckDragProgress == targetProgress {
            return
        }
        if open && personKeyboardUp {
            effects.append(.setKeyboard(shown: false))
        }
        let changed = floatingPad.isVisible != open
        floatingPad.isVisible = open
        deckDragProgress = targetProgress
        if changed {
            effects.append(.haptic(.detent))
        }
    }

    private mutating func closeCurrentModal(restoreKeyboard: Bool, effects: inout [Effect]) {
        guard modal != .none else { return }
        modal = .none
        let shouldRestore = restoreKeyboard && restoreKeyboardAfterModal
        restoreKeyboardAfterModal = false
        if shouldRestore {
            effects.append(.setKeyboard(shown: true))
        }
    }

    public static func capsuleSnapTarget(
        for normalizedProjectedPoint: WorkspacePoint,
        currentEdge: CapsuleEdge
    ) -> CapsuleVisibility? {
        guard normalizedProjectedPoint.x.isFinite, normalizedProjectedPoint.y.isFinite else {
            return nil
        }
        let x = clamp(normalizedProjectedPoint.x, to: 0...1)
        let y = clamp(normalizedProjectedPoint.y, to: 0...1)

        let nearLeading = x <= capsuleCornerZoneX
        let nearTrailing = x >= (1.0 - capsuleCornerZoneX)
        let nearTop = y <= capsuleCornerZoneY
        let nearBottom = y >= (1.0 - capsuleCornerZoneY)

        if nearTop && nearLeading {
            return .minimized(corner: .topLeading, returnEdge: CapsuleCorner.topLeading.resolvedReturnEdge(from: currentEdge))
        }
        if nearTop && nearTrailing {
            return .minimized(corner: .topTrailing, returnEdge: CapsuleCorner.topTrailing.resolvedReturnEdge(from: currentEdge))
        }
        if nearBottom && nearLeading {
            return .minimized(corner: .bottomLeading, returnEdge: CapsuleCorner.bottomLeading.resolvedReturnEdge(from: currentEdge))
        }
        if nearBottom && nearTrailing {
            return .minimized(corner: .bottomTrailing, returnEdge: CapsuleCorner.bottomTrailing.resolvedReturnEdge(from: currentEdge))
        }

        let candidates: [(CapsuleEdge, Double)] = [
            (.bottom, 1.0 - y),
            (.top, y),
            (.trailing, 1.0 - x),
            (.leading, x),
        ]
        let minDist = candidates.map(\.1).min() ?? 0
        if let current = candidates.first(where: { $0.0 == currentEdge && abs($0.1 - minDist) < 1e-9 }) {
            return .expanded(edge: current.0)
        }
        let best = candidates.first(where: { abs($0.1 - minDist) < 1e-9 })?.0 ?? currentEdge
        return .expanded(edge: best)
    }

    private static func clamp(_ value: Double, to bounds: ClosedRange<Double>) -> Double {
        if value < bounds.lowerBound { return bounds.lowerBound }
        if value > bounds.upperBound { return bounds.upperBound }
        return value
    }
}
