import SwiftUI
import Combine
import StreamProtocol

// MARK: - Palette

extension Color {
    /// 0xRRGGBB, the way the design boards write colours.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Legacy palette alias backed strictly by `TactileTokens` (single source of truth).
enum Palette {
    static let bar = TactileTokens.chassisDark
    static let control = TactileTokens.chassisRaised
    static let controlOpen = TactileTokens.controlRaised
    static let accent = TactileTokens.ledBlue
    static let text = TactileTokens.textPrimary
    static let barLabel = TactileTokens.textBarLabel
    static let muted = TactileTokens.textSecondary
    static let panel = TactileTokens.chassisDark
    static let trackpad = TactileTokens.trackpadWell
    static let thumbBody = TactileTokens.chassisRaised
    static let thumbTitleBar = TactileTokens.controlRaised
    static let iconFallback = TactileTokens.keycapTop
}

// MARK: - Layout selection

/// Which layout a screen gets, decided from its size in points alone: no device check, no idiom,
/// so an iPad at an odd split size and an iPhone each get the layout their dimensions deserve (only
/// the arrangement `.outerPortrait` draws depends on the device; below). The numbers are written
/// for the iPhone Duo (first guessed at 1000×710 and 500×710; the real sizes, from the iOS 27.1
/// simulator, are these, the stream screen's: docs/iphone-duo-plan.md):
///
/// * inner display sideways, open flat or half-folded (the book pose) — 951×669 → `.innerLandscape`
///   (top bar over the stream)
/// * inner display upright, open flat or half-folded (the laptop pose) — 669×951 → `.innerPortrait`
///   (stream over controls)
/// * the cover on its side — 594×466 (678×466 less the camera's strip) → `.outerLandscape`
/// * the cover upright — 382×678 (466×678 less that strip) → `.outerPortrait`
///
/// The outer display is not a different app: it is the same two layouts at compact sizes, because
/// the posture only changed how much room there is, not what the screen is for. The thresholds sit
/// between those sizes with room to spare — 600 separates the cover's 382 pt width from the inner
/// 669, and 560 the cover's 466 pt height from the inner 669. Where the fold runs across the inner
/// display, and whether it is in the way, is the device's word (iOS 27.1, DuoPosture), not the size's.
///
/// The same sizes catch the phones: every iPhone held upright (375–440 pt wide, 320 with Display
/// Zoom) is `.outerPortrait` and on its side `.outerLandscape`, and so is an iPad window narrower
/// than 600 pt held upright (Slide Over, a narrow Split View). On an iPhone `.outerPortrait` draws
/// the phone's arrangement (Noah, 2026-09-27: the picture in a fixed 16:10 pane on top, then the
/// Keyboard button's row, the thumbnails, six keys and the trackpad; `PhonePortraitLayout`), the
/// Duo's outer display included: it has a phone's shape and the same keyboard over its key row. An
/// iPad keeps the compact halves in such a window, as before: the approval covered iPhones and left
/// the iPad as it was (`phoneArrangement`, the one place the layout reads the idiom). To give the
/// Duo's outer display back the halves, draw `.compact` from 480 pt wide (phones are at most 440;
/// docs/iphone-portrait-plan.md, Detection).
enum DuoLayout {
    case innerLandscape, innerPortrait, outerPortrait, outerLandscape

    /// Narrower than this and taller than wide: the outer display held upright.
    static let outerMaxWidth: CGFloat = 600
    /// Shorter than this and wider than tall: the outer display on its side.
    static let outerMaxHeight: CGFloat = 560

    static func of(_ size: CGSize) -> DuoLayout {
        if size.height > size.width, size.width < outerMaxWidth { return .outerPortrait }
        if size.width > size.height, size.height < outerMaxHeight { return .outerLandscape }
        return size.width > size.height ? .innerLandscape : .innerPortrait
    }

    /// The laptop layout, inner or outer: stream on top, the key row and the trackpad below. Only
    /// there does the device draw its own pointer, for the trackpad (PointerPresence).
    var isPortrait: Bool { self == .innerPortrait || self == .outerPortrait }

    /// Whether `.outerPortrait` draws the phone's arrangement: on an iPhone, yes; on an iPad (a
    /// window narrower than 600 pt held upright), no: the compact halves, as before. DEBUG:
    /// `-SillIdiom pad` (or `phone`) draws the other device's, so the harness can photograph an
    /// iPad window's on an iPhone simulator (ContentView's contract).
    static var phoneArrangement: Bool {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "SillIdiom") {
        case "pad"?: return false
        case "phone"?: return true
        default: break
        }
        #endif
        return UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Whether a screen of this size draws the phone's arrangement.
    static func drawsPhone(_ size: CGSize) -> Bool { of(size) == .outerPortrait && phoneArrangement }
}

// MARK: - Screen

/// Sill's hold on the device's own auto-lock (UIApplication.isIdleTimerDisabled) across its windows
/// (DeviceIdlePolicy, PR #230). Each window's WindowSessionObserver says which session it shows and
/// in which UIWindow, both weak as MacMenuHub's are, so a window that closed leaves nothing, whether
/// or not its stream screen ran its onDisappear; every look lists them afresh: whether a window's
/// scene is foreground active now, whether its session is connected and streaming, and when the
/// person last used it (DeviceIdlePolicy.lastUse: input the person sent the Mac, one of the stream
/// screen's controls, the start of a session the person started, the moment the window came to the
/// front; nothing the device did by itself). It looks again when a scene comes, goes or changes its
/// activation, when a session connects, disconnects or changes its source, when the person uses a
/// session while nothing holds, and when the hold would end. Main thread.
final class DeviceIdleTimer {
    static let shared = DeviceIdleTimer()

    private struct Entry {
        weak var client: StreamClient?
        weak var window: UIWindow?
        /// When its window's scene last came to the front (systemUptime); nil while it is not there.
        var frontSince: Double?
    }
    private var entries: [Entry] = []
    private var observers: [NSObjectProtocol] = []
    private var recheck: Timer?
    /// Whether auto-lock is held off now.
    private(set) var holding = false

    private init() {
        for name in [UIScene.willConnectNotification, UIScene.didDisconnectNotification, UIScene.didActivateNotification,
                     UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // A scene's activation state reads its new value once its notification has gone out.
                DispatchQueue.main.async { self?.update() }
            })
        }
    }

    /// A session's screen moved into `window` (nil: out of every window).
    func session(_ client: StreamClient, window: UIWindow?) {
        let kept = entries.first { $0.client === client }
        entries.removeAll { $0.client == nil || $0.client === client }
        if let window {
            entries.append(Entry(client: client, window: window, frontSince: kept?.window === window ? kept?.frontSince : nil))
        }
        update()
    }

    /// The person used a session (input to the Mac, one of the stream screen's controls). While
    /// auto-lock is held off its timer looks again when the hold would end; while it is not, now.
    func used() { if !holding { update() } }

    /// Lists the windows afresh and applies DeviceIdlePolicy.
    func update() {
        let now = ProcessInfo.processInfo.systemUptime
        entries.removeAll { $0.client == nil || $0.window == nil }
        var windows: [DeviceIdlePolicy.Window] = []
        for i in entries.indices {
            guard let client = entries[i].client, let window = entries[i].window else { continue }
            let streaming = client.connected && client.active != .none
            let front = window.windowScene?.activationState == .foregroundActive
            if !front { entries[i].frontSince = nil } else if entries[i].frontSince == nil { entries[i].frontSince = now }
            let used = DeviceIdlePolicy.lastUse(.init(input: client.lastPersonInputAt, control: client.lastActionAt,
                                                      session: client.personSessionAt, front: entries[i].frontSince))
            windows.append(DeviceIdlePolicy.Window(foregroundActive: front, streaming: streaming, lastUsedAt: used))
        }
        let ends = DeviceIdlePolicy.holdEnds(windows, now: now, limit: Self.limit)
        recheck?.invalidate()
        recheck = nil
        if let ends {
            let timer = Timer(timeInterval: max(ends - now, 0.5), repeats: false) { [weak self] _ in self?.update() }
            RunLoop.main.add(timer, forMode: .common)
            recheck = timer
        }
        let hold = ends != nil
        guard hold != holding || UIApplication.shared.isIdleTimerDisabled != hold else { return }
        holding = hold
        UIApplication.shared.isIdleTimerDisabled = hold
        #if DEBUG
        if let ends {
            print("idle: auto-lock held off while a window streams, \(Int((ends - now).rounded())) s more without use")
        } else {
            print("idle: auto-lock is the device's own again")
        }
        #endif
    }

    /// DEBUG `-SillIdleLimit <s>`: the hold's limit for one run, to see it end without waiting ten
    /// minutes; DeviceIdlePolicy.idleLimit otherwise, and always in a Release build.
    #if DEBUG
    private static let limit: Double = {
        let s = UserDefaults.standard.double(forKey: "SillIdleLimit")
        return s > 0 ? s : DeviceIdlePolicy.idleLimit
    }()
    #else
    private static let limit = DeviceIdlePolicy.idleLimit
    #endif
}

struct StreamScreen: View {
    @ObservedObject var client: StreamClient
    @State private var workspace = StreamWorkspaceState(
        form: DuoLayout.phoneArrangement ? .phonePortrait : .padFullCanvas,
        hardwareKeyboardAttached: HardwareKeyboardMonitor.shared.attached
    )
    @State private var keyboardShown = false
    @State private var latched: KeyModifiers = []
    @State private var overlay = InputOverlayProxy()
    @State private var accessoryHost: TactileKeyboardAccessoryHost? = nil
    // Phone portrait is ~402 pt wide, narrower than most Mac apps' minimum window width, so 1x clamps
    // windows into landscape; 0.5x requests ~804 pt wide while keeping the phone's portrait aspect ratio.
    @State private var textScale: Double? = DuoLayout.phoneArrangement ? 0.5 : nil
    private var scannerOverride: CodeScanner.Mode? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panelSize: CGSize = .zero
    @State private var zoom = StreamZoomModel()
    @State private var pendingViewport: Task<Void, Never>? = nil
    @State private var linkLine = LinkLine()
    @State private var linkLineCheck: Task<Void, Never>? = nil

    @State private var tour: TourRun? = nil
    @State private var tourTargets: [TourTarget: CGRect] = [:]
    @State private var keyboardToggleFrame: CGRect? = nil
    @State private var pictureAt: Double? = nil
    @State private var tourLayout: TourLayout? = nil
    @State private var layoutAt: Double = ProcessInfo.processInfo.systemUptime
    @State private var tourWait: Task<Void, Never>? = nil
    @State private var touches = TouchWatch()
    @State private var tourStore = TourStore()
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.duoEnvironment) private var duoEnvironment

    @State private var chrome: ChromeLevel = .shown
    @State private var reveal: CGFloat? = nil
    @State private var chromeSlides = true
    @State private var coversScreen = true
    @State private var shownInsets: FullScreenPolicy.Insets? = nil
    @State private var windowInsets: FullScreenPolicy.Insets? = nil
    @Environment(\.harnessSafeArea) private var harnessSafeArea
    @State private var keyboardBeforeHide = false
    @State private var hintShown = false
    @State private var hintFade: Task<Void, Never>? = nil
    @AppStorage(StreamScreen.fullScreenHintsKey) private var hintsShown = 0
    @AppStorage(FullScreenPolicy.shakeKey) private var shakeShowsControls = true
    @State private var shakeToUndoTurnedOff = false
    static let fullScreenHintsKey = "Sill.fullScreenHints"
    #if DEBUG
    @State private var tourWaitLogged: Double? = nil
    @State private var tourSkipPressed = false
    #endif

    private enum WorkspaceSheet: Identifiable {
        case switcher(initialSearch: Bool)
        case controlCenter

        var id: String {
            switch self {
            case .switcher: return "switcher"
            case .controlCenter: return "controlCenter"
            }
        }
    }

    #if DEBUG
    init(client: StreamClient, drawerOpen: Bool = false, keyboardShown: Bool = false,
         scaleOpen: Bool = false, textScale: Double? = nil, settingsOpen: Bool = false,
         pairingOverlay: Bool = false, scannerOverride: CodeScanner.Mode? = nil) {
        self.client = client
        _keyboardShown = State(initialValue: keyboardShown)
        _textScale = State(initialValue: textScale ?? (DuoLayout.phoneArrangement ? 0.5 : nil))
        self.scannerOverride = scannerOverride

        var initial = StreamWorkspaceState(
            form: DuoLayout.phoneArrangement ? .phonePortrait : .padFullCanvas,
            hardwareKeyboardAttached: HardwareKeyboardMonitor.shared.attached
        )
        let debug = FullScreenDebug.current
        if debug.startHidden {
            _ = initial.send(.setFullScreenHidden(true))
        }
        if pairingOverlay {
            _ = initial.send(.openModal(.pairingOverlay))
        } else if settingsOpen {
            _ = initial.send(.openModal(.controlCenter(.root)))
        } else if drawerOpen {
            _ = initial.send(.openModal(.switcher(initialSearch: false)))
        }
        if UserDefaults.standard.bool(forKey: "SillDeckOpen") {
            _ = initial.send(.setPhoneDeck(open: true))
        }
        if UserDefaults.standard.bool(forKey: "SillPadTrackpad") {
            _ = initial.send(.toggleFloatingPad)
        }
        _workspace = State(initialValue: initial)
        _chrome = State(initialValue: debug.startHidden ? .hidden : .shown)
        _reveal = State(initialValue: debug.startHidden ? debug.reveal : nil)
        _hintShown = State(initialValue: debug.startHidden && debug.hint != .off)
    }
    #else
    init(client: StreamClient) {
        self.client = client
    }
    #endif

    var body: some View {
        GeometryReader { geo in
            let duo = DuoLayout.of(geo.size)
            let layout: TourLayout = duo == .innerLandscape || duo == .outerLandscape ? .landscape
                : (DuoLayout.drawsPhone(geo.size) ? .phone : .portrait)
            let posture = DuoPosture.read(geo, duoEnvironment)
            let form = Self.workspaceForm(for: geo.size, posture: posture)
            let hidden = chromeHidden
            let insets = deviceInsets(geo)
            let room = FullScreenPolicy.room(size: geo.size, insets: insets, choice: Self.roomChoice,
                                             topIsStatusBar: !DuoLayout.phoneArrangement,
                                             foldTop: posture.info(in: geo.size).horizontalBand?.minY)

            ZStack {
                // Single unconditional canvas node so HEVCDisplayView and InputOverlay never re-parent.
                streamCanvas(size: geo.size, hidden: hidden, room: room, insets: insets)
                    .allowsHitTesting(!overlayShown && tour == nil)
                    .ignoresSafeArea(.keyboard)

                if !hidden {
                    workspaceChrome(size: geo.size, insets: insets)
                        .allowsHitTesting(!overlayShown && tour == nil)
                        .transition(chromeTransition)
                }

                if hidden, let progress = reveal {
                    revealPreview(progress, size: geo.size, insets: insets)
                }

                if hidden, hintShown {
                    FullScreenHint()
                        .padding(.leading, room.minX + 18)
                        .padding(.trailing, 18)
                        .frame(width: geo.size.width, alignment: .leading)
                        .position(x: geo.size.width / 2, y: room.midY)
                        .transition(.opacity)
                }

                if clipboardChipAllowed, client.clipboardChip || client.clipboardNote != nil, let panel = tourTargets[.stream] {
                    let corner = ClipboardPolicy.chipCorner(landscape: layout == .landscape, linkLineShown: streamLine != nil)
                    let widest = corner == .bottomTrailing ? DuoPosture.clipboardChipMaxWidth(panel: panel, toggle: keyboardToggleFrame)
                                                           : max(0, panel.width - 16)
                    ClipboardChip(client: client)
                        .frame(maxWidth: widest, alignment: .trailing)
                        .padding(8)
                        .frame(width: panel.width, height: panel.height,
                               alignment: corner == .topTrailing ? .topTrailing : .bottomTrailing)
                        .position(x: panel.midX, y: panel.midY)
                        .transition(.opacity)
                }

                if let run = tour, !overlayShown {
                    let features = tourFeatures(offersLarger: false)
                    let copy = tourCopy(run, layout, keysOnItsSide: posture.onInnerDisplay,
                                        thumbnails: true, features: features)
                    TourOverlay(run: run, copy: copy,
                                layout: layout, targets: tourTargets,
                                thumbnails: true,
                                room: nil,
                                screen: geo.size, bottomInset: geo.safeAreaInsets.bottom,
                                next: tourNext, skip: tourSkip)
                        .transition(.opacity)
                        #if DEBUG
                        .onChange(of: Self.tourRowsLine(run, copy, features), initial: true) { _, line in print(line) }
                        #endif
                }

                if overlayShown {
                    PairingOverlay(client: client, scannerMode: scannerOverride ?? CodeScanner.currentMode,
                                   close: {
                                       withAnimation(.easeOut(duration: 0.2)) {
                                           if workspace.modal == .pairingOverlay {
                                               dispatch(.closeModal(restoreKeyboard: false))
                                           }
                                       }
                                   })
                }
            }
            .coordinateSpace(.named(TourSpace.name))
            .onPreferenceChange(TourTargetsKey.self) { tourTargets = $0 }
            .onPreferenceChange(KeyboardToggleFrameKey.self) { keyboardToggleFrame = $0 }
            .onChange(of: form, initial: true) { _, newForm in
                dispatch(.setForm(newForm))
            }
            .onChange(of: layout, initial: true) { _, now in layoutChanged(to: now) }
            .onChange(of: clipboardChipOnScreen, initial: true) { _, onScreen in
                client.clipboardChipShown(onScreen)
            }
            .background(TouchWatcher(watch: touches))
            .background(fullScreenEdges)
            .duoFold(posture, size: geo.size, screen: "stream screen")
            .duoStatusBar(posture, size: geo.size)
            .modifier(FullScreenSystem(hidden: hidden))
        }
        .background(TactileTokens.canvasBlack)
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .switcher(let initialSearch):
                UnifiedSwitcherSheet(
                    client: client,
                    initialSearch: initialSearch,
                    dismiss: { dispatch(.closeModal(restoreKeyboard: true)) }
                )
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .controlCenter:
                ControlCenterSheet(
                    client: client,
                    textScale: $textScale,
                    route: controlCenterRoute,
                    fullScreenRow: fullScreenRow,
                    onTextScaleCommit: { dispatch(.textScaleCommitted) },
                    onPairThisDevice: openPairingOverlay,
                    onTakeTour: takeTour,
                    dismiss: { dispatch(.closeModal(restoreKeyboard: true)) }
                )
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: client.pendingLink) { _, link in
            if link != nil { openLinkOverlay() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                dispatch(.sceneDeactivated)
            }
        }
        .ignoresSafeArea(edges: chromeHidden ? .all : .bottom)
        .onAppear {
            _ = KeyboardFrameMonitor.shared
            if accessoryHost == nil {
                accessoryHost = TactileKeyboardAccessoryHost(
                    latched: $latched,
                    send: { client.sendFromKeyRow($0) },
                    onSwitchToTrackpad: DuoLayout.phoneArrangement ? {
                        animatedDispatch(.setPhoneDeck(open: true))
                    } : nil,
                    onDismiss: {
                        // Explicit hide returns to Focus canvas when a dedicated Trackpad switch sits beside it.
                        if workspace.form.usesPhoneDock {
                            animatedDispatch(.setPhoneDeck(open: false))
                        }
                        dispatch(.dismissKeyboardRequested)
                    }
                )
            }
            let proxy = overlay
            client.onCaretMayMove = { [weak proxy] in proxy?.caretMayHaveMoved() }
            overlay.update(takers: Self.hardwareTakers(from: workspace.keyboardTakers))
            client.setPointerLayout(portrait: workspace.pointerTrackpadActive)
            if client.pendingLink != nil { openLinkOverlay() }
            #if DEBUG
            runLaunchArguments()
            #endif
        }
        .onChange(of: latched) { _, now in
            accessoryHost?.update(latched: now)
        }
        .onChange(of: client.active) { _, source in
            zoom.reset()
            if source != .none, case .switcher = workspace.modal {
                dispatch(.closeModal(restoreKeyboard: true))
            }
            overlay.caretMayHaveMoved()
            sendViewport()
        }
        .onChange(of: client.connected) { _, up in
            if up { sendViewport() }
        }
        .onReceive(HardwareKeyboardMonitor.shared.$attached) { attached in
            overlay.update(attached: attached)
            dispatch(.setHardwareKeyboardAttached(attached))
        }
        .onChange(of: keyboardShown) { _, up in
            client.noteAction()
            dispatch(.systemKeyboardChanged(personOwnUp: up))
        }
        .onChange(of: workspace.modal) { _, _ in client.noteAction() }
        .onChange(of: workspace.phoneDock) { _, _ in client.noteAction() }
        .onChange(of: workspace.capsule) { _, _ in client.noteAction() }
        .onChange(of: workspace.floatingPad.isVisible) { _, _ in client.noteAction() }
        .onChange(of: textScale) { _, _ in client.noteAction() }
        .onChange(of: shakeShowsControls) { _, _ in applyShakeToUndo() }
        .onChange(of: FullScreenPolicy.mustShow(fullScreenSituation)) { _, reason in
            if let reason, chrome != .shown { showChrome(by: reason.rawValue, person: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            sendViewport(after: 0.25)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.modeDidChangeNotification).receive(on: RunLoop.main)) { _ in
            sendViewport(after: 0.25)
        }
        .onChange(of: client.remoteRoute) { _, _ in sendViewport() }
        .onChange(of: linkReportLine, initial: true) { _, _ in updateLinkLine() }
        .onChange(of: linkLineAllowed) { _, _ in updateLinkLine() }
        .onChange(of: client.lockView) { _, on in if on { AccessibilityNotification.Announcement(LockedMac.viewLine).post() } }
        .onChange(of: pictureReady, initial: true) { _, ready in if ready { pictureCame() } }
        .onChange(of: tourCard, initial: true) { _, card in tourCardChanged(card) }
        .onChange(of: tourVoiceOver) { _, _ in carryTour(reason: "VoiceOver") }
        .onDisappear {
            tourWait?.cancel()
            tourWait = nil
            pendingViewport?.cancel()
            pendingViewport = nil
            if shakeToUndoTurnedOff {
                UIApplication.shared.applicationSupportsShakeToEdit = true
                shakeToUndoTurnedOff = false
            }
        }
    }

    // MARK: Workspace state machine

    private static func workspaceForm(for size: CGSize, posture: DuoPosture) -> WorkspaceForm {
        if posture.onInnerDisplay {
            return size.width >= size.height ? .duoBook : .duoLaptop
        }
        if DuoLayout.phoneArrangement {
            return size.height >= size.width ? .phonePortrait : .phoneLandscape
        }
        return .padFullCanvas
    }

    private static func hardwareTakers(from takers: Set<WorkspaceKeyboardTaker>) -> Set<HardwareKeyboardPolicy.Taker> {
        var mapped: Set<HardwareKeyboardPolicy.Taker> = []
        for taker in takers {
            switch taker {
            case .settings: mapped.insert(.settings)
            case .pairing: mapped.insert(.pairing)
            case .tour: mapped.insert(.tour)
            case .drawer: mapped.insert(.drawer)
            case .menus: mapped.insert(.menus)
            }
        }
        return mapped
    }

    private var deckMotion: Animation {
        TactileMotion.deck(reduceMotion: reduceMotion)
    }

    private func dispatch(_ action: StreamWorkspaceState.Action) {
        let effects = workspace.send(action)
        for effect in effects {
            apply(effect)
        }
    }

    private func animatedDispatch(_ action: StreamWorkspaceState.Action) {
        switch action {
        case .deckDragChanged, .moveFloatingPad:
            dispatch(action)
        case .snapCapsule, .toggleCapsuleTuck, .setCapsuleEdge, .expandCapsule, .minimizeCapsule:
            withAnimation(TactileMotion.paletteDock(reduceMotion: reduceMotion)) {
                dispatch(action)
            }
        default:
            withAnimation(deckMotion) {
                dispatch(action)
            }
        }
    }

    private func apply(_ effect: StreamWorkspaceState.Effect) {
        switch effect {
        case .setKeyboard(let shown):
            overlay.setKeyboard(shown: shown)
        case .toggleKeyboard:
            overlay.toggleKeyboard()
        case .updateTakers(let takers):
            overlay.update(takers: Self.hardwareTakers(from: takers))
        case .setPointerTrackpadVisible(let visible):
            client.setPointerLayout(portrait: visible)
        case .selectSource(let source):
            switch source {
            case .none: client.select(.none)
            case .desktop: client.select(.desktop)
            case .window(let id): client.select(.window(id))
            }
        case .commitViewport(let size, let reason):
            panelSize = CGSize(width: size.width, height: size.height)
            sendViewport(after: reason == .initialCanvas ? 0 : 0.25)
        case .haptic(let cue):
            TactileHaptics.play(cue)
        case .releaseHeldKeys:
            break
        case .clearLatchedModifiers:
            latched = []
        }
    }

    private var activeSheet: Binding<WorkspaceSheet?> {
        Binding(
            get: {
                switch workspace.modal {
                case .switcher(let initialSearch):
                    return .switcher(initialSearch: initialSearch)
                case .controlCenter:
                    return .controlCenter
                case .none, .menusPullDown, .pairingOverlay, .tour:
                    return nil
                }
            },
            set: { newValue in
                guard newValue == nil else { return }
                switch workspace.modal {
                case .switcher, .controlCenter:
                    dispatch(.closeModal(restoreKeyboard: true))
                case .none, .menusPullDown, .pairingOverlay, .tour:
                    break
                }
            }
        )
    }

    private var controlCenterRoute: Binding<WorkspaceModal.ControlCenterRoute> {
        Binding(
            get: {
                if case .controlCenter(let route) = workspace.modal { return route }
                return .root
            },
            set: { newRoute in
                dispatch(.setControlCenterRoute(newRoute))
            }
        )
    }

    // MARK: Canvas and workspace chrome

    /// Shared bottom footprint for both the iOS keyboard + 56 pt floating bar and the pull-up
    /// Control Deck, so swapping Keyboard <-> Trackpad keeps the Mac window and top bar locked in place.
    private func phoneInputFootprint(for size: CGSize) -> CGFloat {
        min(max(size.height * 0.43, 296), 372)
    }

    private func streamCanvasInsets(size: CGSize, hidden: Bool, room: CGRect, insets: FullScreenPolicy.Insets) -> EdgeInsets {
        if hidden {
            return EdgeInsets(top: room.minY, leading: room.minX,
                              bottom: max(0, size.height - room.maxY),
                              trailing: max(0, size.width - room.maxX))
        }
        guard workspace.form.usesPhoneDock else { return EdgeInsets() }
        let bottomClearance = max(10, insets.bottom)
        let dockReserve = bottomClearance + 76
        let sharedReserve = phoneInputFootprint(for: size) + 6
        let progress = CGFloat(max(0, min(1, workspace.deckDragProgress)))
        let deckBottom = dockReserve + progress * (sharedReserve - dockReserve)
        let keyboardBottom: CGFloat = keyboardShown ? sharedReserve : 0
        return EdgeInsets(top: 6, leading: 0, bottom: max(deckBottom, keyboardBottom), trailing: 0)
    }

    private func streamCanvas(size: CGSize, hidden: Bool, room: CGRect, insets: FullScreenPolicy.Insets) -> some View {
        let canvasInsets = streamCanvasInsets(size: size, hidden: hidden, room: room, insets: insets)
        return ZStack {
            ZoomedStreamView(client: client, zoom: zoom)
            InputOverlay(videoSize: client.videoSize,
                         send: { client.sendInput($0) },
                         setOwnPointer: { client.setOwnPointer($0, from: $1) },
                         proxy: overlay,
                         isKeyboardShown: $keyboardShown,
                         latchedModifiers: latched,
                         onModifiersConsumed: { latched = [] },
                         sendGesture: { client.sendGesture($0, fingers: $1) },
                         macRepeatsKeys: { KeyTyping.macRepeats(keyRepeat: client.hostKeyRepeat) },
                         readZoom: { [zoom] in zoom.zoom },
                         writeZoom: { [zoom] in zoom.set($0) },
                         customInputAccessoryView: accessoryHost?.view)
        }
        .background(TactileTokens.canvasBlack)
        .overlay { LockedMacShade(client: client) }
        .overlay(alignment: .top) { LinkLineView(text: streamLine, lines: streamLineLines) }
        .overlay {
            HiddenPictureElement(hidden: hidden, mac: client.macName.isEmpty ? "The Mac" : client.macName,
                                 show: { showChrome(by: "an assistive technology") })
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { measured in
            // Commit settled visible canvas dimensions (Focus, Deck open, or Keyboard up) so the Mac window
            // always fits edge-to-edge without pillarboxing, while suppressing mid-drag deck frames.
            let isDraggingDeck = workspace.form.usesPhoneDock
                && workspace.deckDragProgress > 0 && workspace.deckDragProgress < 1
            if !isDraggingDeck {
                dispatch(.focusCanvasMeasured(WorkspaceSize(width: Double(measured.width),
                                                            height: Double(measured.height))))
            }
        }
        .tourTarget(.stream)
        .padding(canvasInsets)
        .animation(.easeOut(duration: 0.22), value: keyboardShown)
    }

    @ViewBuilder
    private func workspaceChrome(size: CGSize, insets: FullScreenPolicy.Insets, preview: Bool = false) -> some View {
        let bottomClearance = max(10, insets.bottom)

        if workspace.form.usesPhoneDock {
            let deckHeight = phoneInputFootprint(for: size)
            let progress = workspace.deckDragProgress

            ZStack(alignment: .bottom) {
                if workspace.showsPhoneDock {
                    PhoneFloatingDock(client: client, state: workspace, dispatch: animatedDispatch)
                        .padding(.horizontal, 12)
                        .padding(.bottom, bottomClearance)
                        .opacity(max(0, 1 - progress * 1.4))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !preview, progress > 0.001 || workspace.showsPhoneDeck {
                    PhoneControlDeckView(
                        client: client,
                        latched: $latched,
                        bottomInset: insets.bottom,
                        onDragChanged: { dispatch(.deckDragChanged(progress: $0)) },
                        onDragEnded: { p, v in
                            withAnimation(deckMotion) {
                                dispatch(.deckDragEnded(progress: p, velocityY: v))
                            }
                        },
                        onSwitchToKeyboard: {
                            animatedDispatch(.tapKeyboardButton)
                        },
                        onClose: {
                            withAnimation(deckMotion) {
                                dispatch(.setPhoneDeck(open: false))
                            }
                        }
                    )
                    .frame(height: deckHeight)
                    .offset(y: (1 - progress) * (deckHeight + 16))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else if workspace.showsFloatingCapsule || workspace.form == .duoLaptop {
            ZStack {
                if !preview, workspace.floatingPad.isVisible, size.width > 0, size.height > 0 {
                    let padPoint = WorkspacePoint(
                        x: workspace.floatingPad.anchor.x * Double(size.width),
                        y: workspace.floatingPad.anchor.y * Double(size.height)
                    )
                    PadFloatingTrackpadView(
                        client: client,
                        latched: $latched,
                        containerSize: size,
                        anchor: padPoint,
                        onMoveAnchor: { pt in
                            dispatch(.moveFloatingPad(anchor: WorkspacePoint(
                                x: pt.x / Double(size.width),
                                y: pt.y / Double(size.height)
                            )))
                        },
                        onClose: {
                            withAnimation(deckMotion) {
                                dispatch(.toggleFloatingPad)
                            }
                        }
                    )
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }

                if workspace.showsFloatingCapsule {
                    PadFloatingCapsule(
                        client: client,
                        state: workspace,
                        containerSize: size,
                        insets: insets,
                        textScale: $textScale,
                        onTextScaleCommit: { dispatch(.textScaleCommitted) },
                        dispatch: animatedDispatch
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: The link's line

    private var linkReportLine: String? {
        let host = client.settings.host
        return AwayCopy.streamLine(link: host?.link, away: host?.away, mac: client.macName.isEmpty ? "the Mac" : client.macName)
    }

    private var linkLineAllowed: Bool { workspace.modal == .none && !overlayShown && !tourOnScreen }

    private var clipboardChipAllowed: Bool { linkLineAllowed && !chromeHidden }

    private var clipboardChipOnScreen: Bool {
        clipboardChipAllowed && client.clipboardChip && client.clipboardNote == nil && tourTargets[.stream] != nil
    }

    private func updateLinkLine() {
        if let words = linkLine.update(report: linkReportLine, allowed: linkLineAllowed, now: ProcessInfo.processInfo.systemUptime) {
            AccessibilityNotification.Announcement(words).post()
            #if DEBUG
            print("link: the stream's line “\(words)” (announced)")
            #endif
        }
        linkLineCheck?.cancel()
        linkLineCheck = nil
        guard let at = linkLine.recheckAt else { return }
        linkLineCheck = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0.01, at - ProcessInfo.processInfo.systemUptime)))
            if !Task.isCancelled { updateLinkLine() }
        }
    }

    private var shownLinkLine: String? { linkLine.visible ? linkLine.text : nil }

    private var streamLine: String? {
        if client.lockView { return linkLineAllowed ? LockedMac.viewLine : nil }
        return shownLinkLine
    }
    private var streamLineLines: Int { client.lockView ? 3 : 2 }

    // MARK: Viewport

    private func sendViewport(after delay: Double = 0) {
        pendingViewport?.cancel()
        pendingViewport = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            guard client.connected, panelSize.width > 0, panelSize.height > 0 else { return }
            let fps = StreamClient.wantedFPS(remote: client.awayCapsFrameRate)
            #if DEBUG
            print("viewport: \(Self.points(panelSize.width))×\(Self.points(panelSize.height)) pt, scale "
                  + (textScale.map { TextScaleControl.label($0) } ?? "off") + ", \(fps) fps")
            #endif
            client.sendViewport(Viewport(width: Double(panelSize.width),
                                         height: Double(panelSize.height),
                                         scale: textScale,
                                         fps: fps))
        }
    }

    #if DEBUG
    private static func points(_ value: CGFloat) -> String {
        abs(value - value.rounded()) < 0.01 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }

    private func runLaunchArguments() {
        guard !Self.launchArgumentsRan else { return }
        Self.launchArgumentsRan = true
        let defaults = UserDefaults.standard
        let live = !client.mockDiscovery
        func after(_ seconds: Double, _ step: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: step)
        }
        if defaults.bool(forKey: "SillKeyboard"), live {
            after(0.5) {
                print("keyboard: -SillKeyboard 1, the input view takes first responder")
                overlay.setKeyboard(shown: true)
            }
        }
        let times = (defaults.string(forKey: "SillKeyboardToggle") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        for time in times {
            after(time) {
                print("keyboard: toggled at \(Self.points(CGFloat(time))) s, as the Keyboard button does (it was "
                      + (keyboardShown ? "up" : "down") + ")")
                dispatch(.closeModal(restoreKeyboard: false))
                dispatch(.tapKeyboardButton)
            }
        }
        let turns = (defaults.string(forKey: "SillTurnAt") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        for time in turns {
            after(time) {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    let bounds = scene.keyWindow?.bounds ?? .zero
                    let mask: UIInterfaceOrientationMask = bounds.width > bounds.height ? .portrait : .landscapeRight
                    print("turn: at \(Self.points(CGFloat(time))) s, asking for " + (mask == .portrait ? "portrait" : "landscape"))
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                        print("turn: refused: \(error.localizedDescription)")
                    }
                }
            }
        }
        let dump = defaults.double(forKey: "SillAXDump")
        if dump > 0 { after(dump) { Self.accessibilityDump() } }
        if dump > 0, let spec = defaults.string(forKey: "SillAXAction") { after(dump + 0.5) { Self.accessibilityPerform(spec) } }
        for (time, factor, point) in Self.zoomSteps(defaults.string(forKey: "SillZoom") ?? "") {
            after(time) {
                var z = zoom.zoom
                let size = z.pane
                guard size.width > 0, size.height > 0 else { print("harness: -SillZoom: no picture pane yet"); return }
                let at = CGPoint(x: point.x * size.width, y: point.y * size.height)
                z.pinch(factor: factor, from: at, to: at, in: size)
                z.settle()
                zoom.set(z)
                print("harness: -SillZoom \(factor)@\(point.x),\(point.y): " + Self.zoomLine(z))
            }
        }
        let probe = (defaults.string(forKey: "SillHitTest") ?? "").split(separator: ";").map { $0.split(separator: " ").map(String.init) }
        if let first = probe.first, first.count == 2, let time = Double(first[0]) {
            let points = ([first[1]] + probe.dropFirst().compactMap { $0.first }).compactMap { item -> CGPoint? in
                let xy = item.split(separator: ",").compactMap { Double($0) }
                return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            }
            after(time) {
                guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
                for point in points {
                    let hit = window.hitTest(point, with: nil)
                    print("harness: hit test at (\(Self.points(point.x)), \(Self.points(point.y))): "
                          + (hit.map { String(describing: type(of: $0)) } ?? "nothing") + ", the zoom " + Self.zoomLine(zoom.zoom))
                }
            }
        }
        let fullScreen = FullScreenDebug.current
        for time in fullScreen.toggles {
            after(time) {
                print("harness: full screen toggled at " + Self.points(CGFloat(time)) + " s (the controls were " + (chrome == .shown ? "shown" : "hidden") + ")")
                if chrome == .shown { hideChrome(by: "the harness") } else { showChrome(by: "the harness") }
            }
        }
        for time in fullScreen.swipes {
            for step in 1...5 {
                after(time + Double(step) * 0.03) {
                    let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                    revealMoved(step == 1 ? .began : .changed, travel: width * 0.1 * CGFloat(step), speed: 0, width: width)
                }
            }
            after(time + 0.2) {
                let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                print("harness: a swipe in from the left edge played at " + Self.points(CGFloat(time)) + " s")
                revealMoved(.ended, travel: width * 0.5, speed: 600, width: width)
            }
        }
        for time in fullScreen.takeBacks {
            for step in 1...6 {
                after(time + Double(step) * 0.03) {
                    let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                    revealMoved(step == 1 ? .began : .changed, travel: width * 0.1 * CGFloat(step), speed: 0, width: width)
                }
            }
            after(time + 0.25) {
                let width = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }.first ?? 1000
                print("harness: a swipe in taken back at " + Self.points(CGFloat(time)) + " s")
                revealMoved(.ended, travel: width * 0.6, speed: -1500, width: width)
            }
        }
        for time in fullScreen.shakes {
            after(time) {
                print("harness: a shake at " + Self.points(CGFloat(time)) + " s")
                let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
                NotificationCenter.default.post(name: .sillDeviceShaken, object: window)
            }
        }
        if fullScreen.startHidden, fullScreen.hint == .every { showHint() }
        guard live else { return }
        client.runSoundArguments()
        for time in (defaults.string(forKey: "SillDesktopTapAt") ?? "").split(separator: ",").compactMap({ Double($0) }) {
            after(time) {
                print("harness: the Desktop button tapped at " + Self.points(CGFloat(time)) + " s (it read \"" + client.desktopButton.label + "\")")
                client.tapDesktop()
            }
        }
        if defaults.bool(forKey: "SillDrawer") {
            after(1.5) { print("harness: the switcher opened"); dispatch(.openModal(.switcher(initialSearch: false))) }
        }
        if defaults.bool(forKey: "SillSettings") {
            after(1.5) { print("harness: the Control Center opened"); dispatch(.openModal(.controlCenter(.root))) }
            let closeAt = defaults.double(forKey: "SillSettingsCloseAt")
            if closeAt > 1.5 { after(closeAt) { print("harness: the Control Center closed"); dispatch(.closeModal(restoreKeyboard: true)) } }
        }
        for step in (defaults.string(forKey: "SillScaleScript") ?? "").split(separator: ";") {
            let parts = step.split(separator: " ")
            let time = parts.count == 2 ? Double(parts[0]) : nil
            let off = parts.count == 2 && parts[1].lowercased() == "off"
            let scale = parts.count == 2 ? Double(parts[1]).map { TextScale.snap($0, offered: false) } : nil
            guard let time, time >= 0, off || scale != nil else {
                print("harness: -SillScaleScript: “\(step.trimmingCharacters(in: .whitespaces))” is not “<s> <scale|off>”; skipped")
                continue
            }
            after(time) {
                print("harness: Aa set to " + (off ? "Off" : TextScale.title(at: scale!)) + " at " + Self.points(CGFloat(time)) + " s")
                textScale = off ? nil : scale
                dispatch(.textScaleCommitted)
            }
        }
    }
    private static var launchArgumentsRan = false

    static func zoomSteps(_ text: String) -> [(Double, CGFloat, CGPoint)] {
        text.split(separator: ";").compactMap { item in
            let words = item.split(separator: " ", omittingEmptySubsequences: true)
            guard words.count == 1 || words.count == 2 else { return nil }
            let time = words.count == 2 ? Double(words[0]) : 1
            let parts = words[words.count - 1].split(separator: "@")
            guard let time, time >= 0, let factor = Double(parts[0]), factor > 0, parts.count <= 2 else { return nil }
            let xy = parts.count == 2 ? parts[1].split(separator: ",").compactMap { Double($0) } : [0.5, 0.5]
            guard xy.count == 2 else { return nil }
            return (time, CGFloat(factor), CGPoint(x: xy[0], y: xy[1]))
        }
    }

    static func zoomLine(_ z: StreamZoom) -> String {
        String(format: "%.2f×, offset (%.1f, %.1f) in a %@×%@ pt pane", z.scale, z.offset.width, z.offset.height,
               points(z.pane.width), points(z.pane.height))
    }

    /// `-SillAXDump`: walks the key window as an assistive technology does (an element, else its
    /// `accessibilityElements`, else its element count, else its subviews) and prints one line per
    /// element: "ax: 1 Apps (14,454 76×50)".
    static func accessibilityDump() {
        guard let elements = accessibilityElementsInOrder() else { print("ax: no key window"); return }
        for (i, element) in elements.enumerated() {
            let f = element.accessibilityFrame
            let label = element.accessibilityLabel ?? element.accessibilityValue ?? "(no label)"
            // What VoiceOver says after the name: the value, the hint, dimmed and adjustable (Aa's
            // Off and its dimmed state over the Desktop, issue #179); and its actions (the version's Copy).
            var said: [String] = []
            if element.accessibilityLabel != nil, let value = element.accessibilityValue, !value.isEmpty { said.append("value “\(value)”") }
            if let hint = element.accessibilityHint, !hint.isEmpty { said.append("hint “\(hint)”") }
            if element.accessibilityTraits.contains(.notEnabled) { said.append("dimmed") }
            if element.accessibilityTraits.contains(.adjustable) { said.append("adjustable") }
            if let actions = element.accessibilityCustomActions, !actions.isEmpty {
                said.append("actions " + actions.map { "“\($0.name)”" }.joined(separator: ", "))
            }
            print("ax: \(i + 1) \(label) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))"
                  + (said.isEmpty ? "" : ": " + said.joined(separator: ", ")))
        }
    }

    /// The key window's accessibility elements in the order the tree hands them out.
    private static func accessibilityElementsInOrder() -> [NSObject]? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        var elements: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: Any, _ depth: Int) {
            guard depth < 60, seen.count < 5000, let element = object as? NSObject, !element.accessibilityElementsHidden,
                  seen.insert(ObjectIdentifier(element)).inserted else { return }
            if element.isAccessibilityElement { elements.append(element); return }
            if let children = element.accessibilityElements, !children.isEmpty {
                children.forEach { visit($0, depth + 1) }
                return
            }
            let count = element.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                (0..<count).forEach { if let child = element.accessibilityElement(at: $0) { visit(child, depth + 1) } }
                return
            }
            if let view = element as? UIView {
                view.subviews.filter { !$0.isHidden && $0.alpha > 0 }.forEach { visit($0, depth + 1) }
            }
        }
        visit(window, 0)
        return elements
    }

    /// `-SillAXAction '<label>|<action>'`: performs the custom action of that name on the first element
    /// whose label begins with that label, as VoiceOver's actions rotor does, and says what the
    /// clipboard holds after it (the version's Copy: docs/version-label-plan.md).
    static func accessibilityPerform(_ spec: String) {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { print("ax: -SillAXAction wants '<label>|<action>'"); return }
        guard let element = accessibilityElementsInOrder()?.first(where: { ($0.accessibilityLabel ?? "").hasPrefix(parts[0]) }) else {
            print("ax: no element whose label begins “\(parts[0])”"); return
        }
        guard let action = element.accessibilityCustomActions?.first(where: { $0.name == parts[1] }) else {
            print("ax: “\(element.accessibilityLabel ?? "")” has no action “\(parts[1])”"); return
        }
        let done: Bool
        if let handler = action.actionHandler { done = handler(action) }
        else if let target = action.target as? NSObject { _ = target.perform(action.selector, with: action); done = true }
        else { done = false }
        print("ax: performed “\(action.name)” on “\(element.accessibilityLabel ?? "")”: \(done); the clipboard holds "
              + (UIPasteboard.general.string.map { "“\($0)”" } ?? "no text"))
    }
    #endif

    // MARK: Pairing overlay

    private var overlayShown: Bool { workspace.modal == .pairingOverlay || client.pendingLink != nil }

    private func openPairingOverlay() {
        client.cancelPairing()
        withAnimation(.easeOut(duration: 0.2)) {
            dispatch(.openModal(.pairingOverlay))
        }
    }

    private func openLinkOverlay() {
        if workspace.modal != .pairingOverlay {
            switch client.pairing {
            case .working, .idle: break
            case .failed, .paired: client.pairing = .idle
            }
        }
        withAnimation(.easeOut(duration: 0.2)) {
            dispatch(.openModal(.pairingOverlay))
        }
    }

    // MARK: Full screen

    private var chromeHidden: Bool { chrome == .hidden }

    private var fullScreenEdges: FullScreenEdges {
        FullScreenEdges(
            hidden: chrome != .shown,
            onReveal: { state, travel, speed, width in revealMoved(state, travel: travel, speed: speed, width: width) },
            onDwell: { showChrome(by: "the pointer at the left edge") },
            onShake: {
                if FullScreenPolicy.shakeShows(chrome, switchOn: shakeShowsControls) {
                    showChrome(by: "a shake")
                } else if chrome != .shown {
                    #if DEBUG
                    print("full screen: a shake, and Shake to Show Controls is off: the controls stay hidden")
                    #endif
                }
            },
            onCoverage: { coversScreen = $0 },
            onInsets: { e in
                let now = FullScreenPolicy.Insets(top: e.top, left: e.left, bottom: e.bottom, right: e.right)
                windowInsets = now
                if chrome == .shown { shownInsets = now }
            })
    }

    private var fullScreenSituation: FullScreenPolicy.Situation {
        FullScreenPolicy.Situation(coversScreen: coversScreen,
                                   streaming: client.active != .none,
                                   somethingOpen: workspace.modal != .none || workspace.showsPhoneDeck || workspace.floatingPad.isVisible,
                                   tour: tour != nil,
                                   pairing: overlayShown,
                                   linkLine: linkReportLine != nil,
                                   lockCover: client.lockShade != nil,
                                   offConsoleView: client.lockView)
    }

    private var fullScreenRow: HostSettingsPanel.FullScreenRow {
        var s = fullScreenSituation
        s.somethingOpen = false
        return HostSettingsPanel.FullScreenRow(offered: FullScreenPolicy.hideAllowed(s), coversScreen: coversScreen,
                                               hide: hideFromSettings)
    }

    private static func insets(_ e: EdgeInsets) -> FullScreenPolicy.Insets {
        FullScreenPolicy.Insets(top: e.top, left: e.leading, bottom: e.bottom, right: e.trailing)
    }

    private func deviceInsets(_ geo: GeometryProxy) -> FullScreenPolicy.Insets {
        if let harnessSafeArea { return Self.insets(harnessSafeArea) }
        return windowInsets ?? Self.insets(geo.safeAreaInsets)
    }

    private static var roomChoice: FullScreenPolicy.Room {
        #if DEBUG
        return FullScreenDebug.current.room ?? .clearOfHousing
        #else
        return .clearOfHousing
        #endif
    }

    private var chromeMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.34, bounce: 0.06)
    }

    private var chromeTransition: AnyTransition {
        guard chromeSlides else { return .identity }
        return reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

    private func hideChrome(by how: String, keyboardWasUp: Bool? = nil) {
        guard chrome == .shown else { return }
        guard FullScreenPolicy.hideAllowed(fullScreenSituation) else {
            #if DEBUG
            print("full screen: \(how): not now (" + (FullScreenPolicy.mustShow(fullScreenSituation)?.rawValue ?? "something is open") + ")")
            #endif
            return
        }
        keyboardBeforeHide = keyboardWasUp ?? keyboardShown
        if keyboardShown { overlay.setKeyboard(shown: false) }
        chromeSlides = true
        reveal = nil
        withAnimation(chromeMotion) {
            chrome = chrome.afterHide
            dispatch(.setFullScreenHidden(true))
        }
        applyShakeToUndo()
        client.noteAction()
        if FullScreenPolicy.showsHint(shownBefore: hintsShown, forced: hintForced) {
            hintsShown += 1
            showHint()
        }
        UIAccessibility.post(notification: .screenChanged, argument: FullScreenPolicy.Copy.announcement)
        #if DEBUG
        print("full screen: hidden by \(how)" + (keyboardBeforeHide ? "; the keyboard comes back with the controls" : ""))
        #endif
    }

    private func showChrome(by why: String, person: Bool = true) {
        guard chrome != .shown else { return }
        hintFade?.cancel()
        hintFade = nil
        withAnimation(chromeMotion) {
            chrome = chrome.afterReveal
            reveal = nil
            hintShown = false
            dispatch(.setFullScreenHidden(false))
        }
        applyShakeToUndo()
        if keyboardBeforeHide { overlay.setKeyboard(shown: true) }
        keyboardBeforeHide = false
        if person { client.noteAction() }
        if voiceOverEnabled { UIAccessibility.post(notification: .screenChanged, argument: FullScreenPolicy.Copy.shownAnnouncement) }
        #if DEBUG
        print("full screen: shown by \(why)")
        #endif
    }

    private func applyShakeToUndo() {
        let off = FullScreenPolicy.shakeToUndoOff(chrome, switchOn: shakeShowsControls)
        guard off != shakeToUndoTurnedOff else { return }
        UIApplication.shared.applicationSupportsShakeToEdit = !off
        shakeToUndoTurnedOff = off
    }

    private func hideFromSettings() {
        let keyboard = workspace.restoreKeyboardAfterModal
        dispatch(.closeModal(restoreKeyboard: false))
        if workspace.showsPhoneDeck {
            dispatch(.setPhoneDeck(open: false))
        }
        if workspace.floatingPad.isVisible {
            dispatch(.toggleFloatingPad)
        }
        let mark = client.connectedAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            guard sameSession(mark) else { return }
            hideChrome(by: "Settings › Full Screen", keyboardWasUp: keyboard)
        }
    }

    private func showHint() {
        hintFade?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { hintShown = true }
        #if DEBUG
        if FullScreenDebug.current.hint == .hold { return }
        #endif
        hintFade = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FullScreenPolicy.hintSeconds))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.35)) { hintShown = false } }
        }
    }

    private var hintForced: Bool {
        #if DEBUG
        return FullScreenDebug.current.hint != .off
        #else
        return false
        #endif
    }

    private func revealMoved(_ state: UIGestureRecognizer.State, travel: CGFloat, speed: CGFloat, width: CGFloat) {
        guard chrome != .shown else { return }
        switch state {
        case .began, .changed:
            reveal = CGFloat(EdgeReveal.progress(translation: Double(travel), width: Double(width)))
        case .ended:
            let finishes = EdgeReveal.finishes(translation: Double(travel), velocity: Double(speed), width: Double(width))
            #if DEBUG
            print(String(format: "reveal: lifted after %.0f pt at %.0f pt/s on a screen %.0f pt wide: %@ (it finishes past %.0f pt)",
                         Double(travel), Double(speed), Double(width), finishes ? "comes in" : "springs back",
                         EdgeReveal.distance(width: Double(width))))
            #endif
            if finishes { landReveal() } else { springBack() }
        default:
            #if DEBUG
            print(String(format: "reveal: cancelled after %.0f pt", Double(travel)))
            #endif
            springBack()
        }
    }

    private func landReveal() {
        withAnimation(.easeOut(duration: 0.14 * revealSlow)) { reveal = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.14 * revealSlow))
            guard chrome != .shown, reveal != nil else { return }
            chromeSlides = false
            showChrome(by: "the swipe in from the left edge")
            try? await Task.sleep(for: .seconds(0.4))
            chromeSlides = true
        }
    }

    private var revealSlow: Double {
        #if DEBUG
        return FullScreenDebug.current.slow
        #else
        return 1
        #endif
    }

    private func springBack() {
        withAnimation(.easeOut(duration: 0.2 * revealSlow)) { reveal = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.22 * revealSlow))
            if chrome != .shown, reveal == 0 { reveal = nil }
        }
    }

    private func revealPreview(_ progress: CGFloat, size: CGSize, insets now: FullScreenPolicy.Insets) -> some View {
        let pad = !DuoLayout.phoneArrangement
        let insets = FullScreenPolicy.Insets(top: pad ? (shownInsets?.top ?? now.top) : now.top, left: now.left,
                                             bottom: now.bottom, right: now.right)
        let shown = CGRect(x: insets.left, y: insets.top, width: max(0, size.width - insets.left - insets.right),
                           height: max(0, size.height - insets.top))
        return workspaceChrome(size: shown.size, insets: insets, preview: true)
            .frame(width: shown.width, height: shown.height)
            .transformPreference(TourTargetsKey.self) { $0 = [:] }
            .transformPreference(KeyboardToggleFrameKey.self) { $0 = nil }
            .offset(x: shown.minX - (1 - progress) * size.width, y: shown.minY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.identity)
    }

    // MARK: The tour

    private var pictureReady: Bool {
        !client.macName.isEmpty && client.videoSize != .zero && client.active != .none && !client.lockView
    }

    private var tourOnScreen: Bool { tour != nil && !overlayShown }

    private func sameSession(_ mark: Date?) -> Bool { client.connected && client.connectedAt == mark }
    private var tourCard: TourTopic? { tourOnScreen ? tour?.at : nil }

    private var tourVoiceOver: Bool {
        #if DEBUG
        if TourDebug.current.voiceOver { return true }
        #endif
        return voiceOverEnabled
    }

    private var tourBusy: String? {
        if workspace.modal != .none { return "a modal was open" }
        if keyboardShown { return "the keyboard was up" }
        if overlayShown { return "the pairing overlay was open" }
        if chrome != .shown { return "the controls were hidden" }
        if UIApplication.shared.applicationState != .active { return "the app was not active" }
        return nil
    }

    private func tourCopy(_ run: TourRun, _ layout: TourLayout, keysOnItsSide: Bool = false, thumbnails: Bool = true,
                          features: TourFeatures) -> TourCopy {
        TourPolicy.copy(run.at, layout, mac: client.macName, device: StreamClient.deviceWord,
                        voiceOver: tourVoiceOver, firstOfRun: run.firstOfRun, keysOnItsSide: keysOnItsSide,
                        thumbnails: thumbnails, features: features)
    }

    private func tourFeatures(offersLarger: Bool) -> TourFeatures {
        TourFeatures(menus: client.menus.hasMenus,
                     gestures: StreamClient.gesturesOn && (client.hostGestures ?? 0) >= TrackpadGesture.generation,
                     virtualDisplay: client.settings.displayed?.virtualDisplay == true,
                     clipboard: ClipboardPolicy.hostTakes(client.hostClipboard),
                     pasteRightAway: StreamClient.pasteRightAwayOn,
                     sound: client.macHasSound,
                     largerPicture: offersLarger)
    }

    #if DEBUG
    static func tourRowsLine(_ run: TourRun, _ copy: TourCopy, _ f: TourFeatures) -> String {
        func has(_ on: Bool, _ name: String) -> String { on ? name : "no " + name }
        let what = [has(f.menus, "Menus button"), has(f.gestures, "gestures"), has(f.virtualDisplay, "Virtual Display"),
                    has(f.clipboard, "clipboard"), has(f.pasteRightAway, "paste right away"), has(f.sound, "sound"),
                    has(f.largerPicture, "Larger Picture")]
        return "tour: card \(run.at.rawValue) (\(copy.title)): \(copy.rows.count) rows, \(copy.rows.filter(\.isNew).count) New; "
            + what.joined(separator: ", ")
    }
    #endif

    private func tourLog(_ line: @autoclosure () -> String) {
        #if DEBUG
        print("tour: " + line())
        #endif
    }

    private func pictureCame() {
        guard pictureAt == nil else { return }
        pictureAt = ProcessInfo.processInfo.systemUptime
        #if DEBUG
        let debug = TourDebug.current
        let mark = client.connectedAt
        if let step = debug.start {
            Task { @MainActor in
                guard sameSession(mark) else { return }
                startTour(TourPolicy.replay(tourLayout ?? .landscape, voiceOver: tourVoiceOver, from: step))
            }
        }
        if let s = debug.activityAt, !TourDebug.touchedOnce {
            TourDebug.touchedOnce = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(s))
                guard sameSession(mark) else { return }
                touches.lastTouchAt = ProcessInfo.processInfo.systemUptime
                tourLog("a stand-in touch \(s) s after the picture")
                considerTour()
            }
        }
        if let s = debug.takeTourAt {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(s))
                guard sameSession(mark) else { return }
                tourLog("a stand-in for Control Center, then Take the Tour")
                dispatch(.openModal(.controlCenter(.root)))
                try? await Task.sleep(for: .seconds(1))
                guard sameSession(mark) else { return }
                takeTour()
            }
        }
        #endif
        considerTour()
    }

    private func layoutChanged(to layout: TourLayout) {
        let changed = tourLayout != nil && layout != tourLayout
        tourLayout = layout
        if changed {
            layoutAt = ProcessInfo.processInfo.systemUptime
            carryTour(reason: "a turn")
        }
        considerTour()
    }

    private func carryTour(reason: String) {
        guard let run = tour, let layout = tourLayout else { return }
        guard let carried = TourPolicy.carry(run, to: layout, voiceOver: tourVoiceOver, memory: tourStore.memory) else {
            tourLog("ended by \(reason): nothing of it here (\(layout.rawValue))")
            endTour()
            return
        }
        client.tourSession.offered.insert(layout)
        guard carried != run else { return }
        tourLog("carried to \(carried.at.rawValue) (\(carried.index + 1) of \(carried.count), \(layout.rawValue))")
        tour = carried
    }

    private func considerTour() {
        tourWait?.cancel()
        tourWait = nil
        guard tour == nil, let layout = tourLayout else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let activity = [touches.lastTouchAt, client.lastInputAt, client.lastActionAt].compactMap { $0 }.max()
        let session = client.tourSession
        let moment = TourMoment(now: now, pictureAt: pictureAt, layoutAt: layoutAt, decided: session.decided,
                                lastActivityAt: activity, touchesDown: touches.down, busy: tourBusy != nil,
                                offered: session.offered.contains(layout), voiceOver: tourVoiceOver,
                                enabled: tourStore.automatic)
        switch TourPolicy.automatic(moment, layout, tourStore.memory) {
        case .wait(let until):
            guard let until else { return }
            #if DEBUG
            if tourWaitLogged != until {
                tourWaitLogged = until
                let owed = TourPolicy.owed(layout, voiceOver: tourVoiceOver, tourStore.memory)
                tourLog("owed here: \(Self.names(owed.map(\.rawValue))) (\(layout.rawValue); seen: \(Self.names(tourStore.memory.names)))")
                tourLog("waiting until 1.0 s after the \(session.decided && layoutAt > (pictureAt ?? 0) ? "turn" : "picture")")
            }
            #endif
            let mark = client.connectedAt
            tourWait = Task { @MainActor in
                try? await Task.sleep(for: .seconds(max(0.01, until - ProcessInfo.processInfo.systemUptime)))
                if !Task.isCancelled, sameSession(mark) { considerTour() }
            }
        case .pass(let reason):
            guard pictureAt != nil, moment.enabled, !moment.offered else { return }
            let since = session.decided && layoutAt > (pictureAt ?? 0) ? "the turn" : "the picture"
            client.tourSession.offered.insert(layout)
            client.tourSession.decided = true
            switch reason {
            case .nothingOwed:
                tourLog("nothing owed here (\(layout.rawValue); seen: \(Self.names(tourStore.memory.names))\(tourStore.memory.skipped ? "; skipped" : ""))")
            case .used:
                tourLog("not this session: used within a second of \(since)")
            case .busy:
                tourLog("not this session: \(touches.down > 0 ? "a touch was down" : tourBusy ?? "something was open")")
            }
        case .show(let steps):
            startTour(TourPolicy.run(owed: steps))
        }
    }

    private static func names(_ list: [String]) -> String {
        list.isEmpty ? "none" : list.joined(separator: ", ")
    }

    private func startTour(_ run: TourRun?) {
        guard let run else { return }
        tourWait?.cancel()
        tourWait = nil
        if let layout = tourLayout { client.tourSession.offered.insert(layout) }
        client.tourSession.decided = true
        client.tourSession.running = true
        dispatch(.openModal(.tour))
        withAnimation(.easeOut(duration: 0.25)) { tour = run }
    }

    private func tourNext() {
        guard let run = tour else { return }
        tourStore.save(TourPolicy.passed(run.at, tourStore.memory))
        tourLog("passed \(run.at.rawValue)")
        if let next = TourPolicy.next(run) {
            let motion: Animation = reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.1)
            withAnimation(motion) { tour = next }
        } else {
            tourLog("done (saved: \(Self.names(tourStore.memory.names))\(tourStore.writes ? "" : "; this run only"))")
            endTour()
        }
    }

    private func tourSkip() {
        guard let run = tour else { return }
        let memory = TourPolicy.skip(run, tourStore.memory)
        if memory != tourStore.memory { tourStore.save(memory) }
        tourLog(run.replay ? "closed (Take the Tour; nothing more saved)" : "skipped (saved\(tourStore.writes ? "" : "; this run only"))")
        endTour()
    }

    private func endTour() {
        let onScreen = tourOnScreen
        withAnimation(.easeOut(duration: 0.2)) { tour = nil }
        client.tourSession.running = false
        if workspace.modal == .tour {
            dispatch(.closeModal(restoreKeyboard: !overlayShown))
        }
        if onScreen { AccessibilityNotification.ScreenChanged().post() }
    }

    private func takeTour() {
        tourLog("Take the Tour")
        startTour(TourPolicy.replay(tourLayout ?? .landscape, voiceOver: tourVoiceOver))
    }

    private func tourCardChanged(_ card: TourTopic?) {
        client.inputPaused = card != nil
        guard let run = tour else { return }
        if card != nil {
            let since = pictureAt.map { String(format: ", %.2f s after the picture", ProcessInfo.processInfo.systemUptime - $0) } ?? ""
            tourLog("showing \(run.at.rawValue) (\(run.index + 1) of \(run.count))\(since)")
            tourPressLater(run)
        } else {
            tourLog("put aside for the pairing overlay, at \(run.at.rawValue)")
        }
    }

    private func tourPressLater(_ run: TourRun) {
        #if DEBUG
        guard let press = TourDebug.current.press else { return }
        let seconds: Double
        let skip: Bool
        switch press {
        case .next(let s): seconds = s; skip = false
        case .skip(let s): seconds = s; skip = !tourSkipPressed
        }
        if skip { tourSkipPressed = true }
        let mark = client.connectedAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard sameSession(mark), tour?.at == run.at, tourOnScreen else { return }
            tourLog("a stand-in presses \(skip ? "Skip" : run.isLast ? "Done" : "Next")")
            if skip { tourSkip() } else { tourNext() }
        }
        #endif
    }
}

// MARK: - The link's line

/// The line over the stream while the link cannot carry the quality (docs/remote-bundle-plan.md §6.7):
/// a capsule at the top centre of the stream panel, 8 pt inside its top edge and at most the panel's
/// width less 32 pt, footnote text on the bar's colour; two lines at most, the text no larger than
/// xxLarge. It never takes a touch meant for the Mac, and comes and goes with a fade (with Reduce
/// Motion too). VoiceOver hears it once a spell (StreamScreen.updateLinkLine) and can read it here.
/// In the iPhone Duo's book pose it is centred on the leading page instead, off the fold
/// (docs/iphone-duo-plan.md).
struct LinkLineView: View {
    let text: String?
    /// Two lines for the link's words; the off-console view's take three (docs/off-console-plan.md).
    var lines = 2
    /// The Duo's hinge (iOS 27.1): with the fold, where the line goes.
    @Environment(\.duoEnvironment) private var duoEnvironment
    var body: some View {
        GeometryReader { geo in
            let page = DuoPosture.leadingPage(DuoPosture.read(geo, duoEnvironment).info(in: geo.size))
            line
                .frame(width: page ?? geo.size.width)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private var line: some View {
        ZStack {
            if let text {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(Palette.bar.opacity(0.92)))
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: text)
    }
}

// MARK: - A locked Mac's cover

/// What covers the stream while the Mac shows nothing of itself (`StreamClient.lockShade`, LockedMac,
/// docs/locked-mac-plan.md): an opaque panel with why, then after the unlock "Unlocking…" until its
/// picture's first keyframe. The picture under it was removed at the lock (HEVCDisplayView.blank), and the
/// Mac streams a black placeholder meanwhile. It takes no touch: a paired device's keys and taps still
/// reach a locked screen, where the Mac takes them; off console the Mac drops them. VoiceOver reads it as
/// one element.
struct LockedMacShade: View {
    @ObservedObject var client: StreamClient

    var body: some View {
        ZStack {
            if let shade = client.lockShade {
                Palette.panel
                VStack(spacing: 10) {
                    if shade == .unlocking {
                        ProgressView().tint(Palette.muted)
                    } else {
                        Image(systemName: shade == .locked(.otherUser) ? "person.2.fill" : "lock.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.muted)
                            .accessibilityHidden(true)
                    }
                    Text(LockedMac.title(mac: client.macName, shade: shade))
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.center)
                    if let detail = LockedMac.detail(shade: shade, paired: client.settings.host?.sessionPaired) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .frame(maxWidth: 440)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: client.lockShade)
    }
}

// MARK: - Top bar

/// The landscape top bar's numbers. The inner display gets the Main board's roomy bar; the outer
/// display gets the Laptop board's compact one, which is 8 pt shorter and tighter all round — on a
/// 500 pt tall screen the bar is a sixth of everything there is, so every point it gives back is a
/// point of Mac. Every bar carries the Aa control (Noah, 2026-09-22: both orientations); it takes
/// one button's width and unfolds over its neighbours only while touched.
struct BarMetrics {
    let height: CGFloat
    let padding: CGFloat
    let gap: CGFloat
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    let buttonSpacing: CGFloat      // between a button's icon and its label
    let thumbWidth: CGFloat
    let thumbHeight: CGFloat
    let thumbRadius: CGFloat
    let thumbSpacing: CGFloat
    let thumbPad: CGFloat
    let thumbFade: Double
    let showsTextSize: Bool
    /// The Settings panel hanging under this bar.
    let settingsWidth: CGFloat

    static let regular = BarMetrics(height: 86, padding: 22, gap: 12,
                                    buttonWidth: 66, buttonHeight: 66, buttonSpacing: 4,
                                    thumbWidth: 104, thumbHeight: 66, thumbRadius: 10,
                                    thumbSpacing: 16, thumbPad: 10, thumbFade: 0.86,
                                    showsTextSize: true, settingsWidth: 360)

    static let compact = BarMetrics(height: 78, padding: 14, gap: 12,
                                    buttonWidth: 64, buttonHeight: 58, buttonSpacing: 3,
                                    thumbWidth: 92, thumbHeight: 58, thumbRadius: 9,
                                    thumbSpacing: 14, thumbPad: 10, thumbFade: 0.88,
                                    showsTextSize: true, settingsWidth: 340)
}

private struct TopBar: View {
    @ObservedObject var client: StreamClient
    let metrics: BarMetrics
    /// The book pose: the strip's width, so that it ends short of the fold (BarMetrics.clearing);
    /// nil: it takes the room there is, as before.
    var stripWidth: CGFloat? = nil
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    @Binding var textScale: Double?
    @Binding var scaleOpen: Bool
    @Binding var windowMenu: UInt32?
    let settingsOpen: Bool
    /// Whether the bar holds the Menus button and still a whole thumbnail (`MacMenuButton.fits`).
    let menusFit: Bool
    let toggleKeyboard: () -> Void
    /// Opens or closes the Settings panel; the second argument says whether closing puts the
    /// keyboard back (see `StreamScreen.setSettings`).
    let setSettings: (_ open: Bool, _ restoreKeyboard: Bool) -> Void
    /// The Menus pull-down opened and went (see `StreamScreen.menusOpened`).
    let menusOpened: () -> Void
    let menusClosed: () -> Void

    var body: some View {
        HStack(spacing: metrics.gap) {
            button(open: drawerOpen, symbol: "magnifyingglass", label: "Apps",
                   accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                   action: {
                       setSettings(false, false)
                       withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() }
                   })

            WindowStrip(client: client, width: metrics.thumbWidth, height: metrics.thumbHeight,
                        radius: metrics.thumbRadius, spacing: metrics.thumbSpacing,
                        pad: metrics.thumbPad, fade: metrics.thumbFade, menuFor: $windowMenu)
                .opacity(scaleOpen ? 0.2 : 1)      // the ruler is centred on Aa and reaches over the strip's end
                .allowsHitTesting(!scaleOpen)
                .frame(width: stripWidth)
                .tourTarget(.strip, inset: WindowStrip.tourBand(pad: metrics.thumbPad))
            // The book pose: the fold's band, and nothing on it, between the strip and the buttons.
            if stripWidth != nil { Spacer(minLength: 0) }

            // The Mac's menus of the streamed app, next to the thumbnails because they are the picked
            // window's app's. Only while the Mac sent some, and where the bar holds it: with none the
            // strip takes its room back.
            if client.menus.hasMenus, menusFit {
                MacMenuButton(client: client, width: metrics.buttonWidth, height: metrics.buttonHeight,
                              spacing: metrics.buttonSpacing, onOpen: menusOpened, onClose: menusClosed)
                    .opacity(scaleOpen ? 0 : 1)    // under the Aa ruler, as the buttons after Aa
                    .allowsHitTesting(!scaleOpen)
                    .transition(.opacity)
            }

            // Text size: the host sizes the Mac window to the panel divided by this scale, so a
            // bigger number means a smaller Mac window and bigger text here. The slider unfolds to
            // the right, over the two buttons after it, which fade while it is open.
            TextScaleControl(scale: $textScale, open: $scaleOpen,
                             width: metrics.buttonWidth, height: metrics.buttonHeight,
                             pointsPerStep: metrics.buttonHeight >= 60 ? 44 : 40,
                             offered: client.textScaleOffersOff, available: client.textScaleSelectable,
                             unavailableHint: client.textScaleUnavailableHint)
                .tourTarget(.textSize)

            button(open: keyboardShown, symbol: "keyboard", label: "Keyboard",
                   accessibilityLabel: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                   action: { setSettings(false, false); toggleKeyboard() })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
                .tourTarget(.keyboard)

            // The Desktop on the Mac's stop it shows, and with two stops or more the next at a tap
            // (DesktopDisplays): "Desktop 2", a dot per stop while the Desktop streams.
            let desktop = client.desktopButton
            button(open: client.active == .desktop, symbol: "desktopcomputer", label: desktop.label,
                   accessibilityLabel: desktop.accessibilityLabel,
                   action: { client.tapDesktop() })
                .desktopStops(desktop, inset: metrics.buttonHeight >= 60 ? 5 : 3.5)
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)

            // Leave's old slot: Disconnect is the Settings panel's pinned last row now.
            button(open: settingsOpen, symbol: "gearshape", label: "Settings",
                   accessibilityLabel: settingsOpen ? "Close settings" : "Settings for \(client.macName.isEmpty ? "the Mac" : client.macName)",
                   action: { setSettings(!settingsOpen, true) })
                .opacity(scaleOpen ? 0 : 1)
                .allowsHitTesting(!scaleOpen)
                .tourTarget(.settings)
        }
        .animation(.easeOut(duration: 0.16), value: scaleOpen)
        .animation(.easeOut(duration: 0.18), value: client.menus.hasMenus)
        .frame(height: metrics.height)
        .padding(.horizontal, metrics.padding)
        // The bar's colour runs to the screen edge; its contents stay inside the safe area.
        .background(Palette.bar.ignoresSafeArea(edges: .top))
    }

    private func button(open: Bool, symbol: String, label: String, accessibilityLabel: String,
                        action: @escaping () -> Void) -> some View {
        BarButton(open: open, width: metrics.buttonWidth, height: metrics.buttonHeight,
                  accessibilityLabel: accessibilityLabel, action: action) {
            VStack(spacing: metrics.buttonSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(open ? Palette.accent : Palette.text)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(open ? Palette.accent : Palette.barLabel)
            }
        }
    }
}

// MARK: - Spotlight

/// Spotlight on the Mac: exactly ⌘Space, down then up. Whatever modifiers are latched never join
/// it — the button means Spotlight, not "space with whatever happens to be held".
enum Spotlight {
    /// The sparkle magnifier where the system has it. The Apps button already uses the plain
    /// magnifier, so the fallback must still look different from it.
    static let symbol: String = UIImage(systemName: "sparkle.magnifyingglass") != nil
        ? "sparkle.magnifyingglass" : "magnifyingglass.circle"

    static func press(send: (InputEvent) -> Void) {
        KeyChord.spotlight.forEach(send)
    }
}

/// A bar button: 66×66 in the roomy top bar, 64×58 in the compact one and the portrait window bar,
/// 56×50 with a 14 pt radius in the outer display's portrait bar, and 50 pt tall with its share of
/// the row's width in a phone's row 1.
struct BarButton<Content: View>: View {
    let open: Bool
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let accessibilityLabel: String
    let action: () -> Void
    let content: () -> Content

    init(open: Bool, width: CGFloat = 66, height: CGFloat = 66, radius: CGFloat = 16,
         accessibilityLabel: String,
         action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.open = open
        self.width = width
        self.height = height
        self.radius = radius
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(open ? Palette.controlOpen : Palette.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    /// The Desktop button beyond its label and symbol (DesktopDisplays.button), on a Mac with two stops or
    /// more: VoiceOver's value ("Display 2 of 3, DELL U2723QE") and hint ("Shows the next display." while
    /// a tap steps), and the stops' dots, the shown one filled ("3/7" from seven), over the button's bottom
    /// margin `inset` from its edge while the Desktop streams, so no bar's layout moves for them. Nothing
    /// with one stop or a Mac from before this, as before.
    func desktopStops(_ face: DesktopDisplays.Button, inset: CGFloat, dot: CGFloat = 4) -> some View {
        accessibilityValue(face.accessibilityValue ?? "")
            .accessibilityHint(face.accessibilityHint ?? "")
            .overlay(alignment: .bottom) { DesktopStopDots(face: face, dot: dot).padding(.bottom, inset) }
    }
}

/// The Desktop button's place among the Mac's stops while the Desktop streams (DesktopDisplays): one dot per
/// stop, the shown one filled, as a page control shows a page; "3/7" in place of seven dots or more. The
/// button reads it whole; VoiceOver hears its value instead.
struct DesktopStopDots: View {
    let face: DesktopDisplays.Button
    var dot: CGFloat = 4

    var body: some View {
        Group {
            if let counter = face.counter {
                // As tall as the dots it stands for, so its digits sit where they would and never reach the
                // label above (an 8 pt line of its own overlapped "Desktop 3" in a 58 pt window bar).
                Text(counter)
                    .font(.system(size: dot + 3, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
                    .frame(height: dot)
            } else if face.dots > 0 {
                HStack(spacing: dot * 0.75) {
                    ForEach(1...face.dots, id: \.self) { i in
                        Circle()
                            .fill(Palette.accent.opacity(i == face.lit ? 1 : 0.32))
                            .frame(width: dot, height: dot)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Text size control

/// The Aa control: a bar button that opens into a ruler while the finger is down, the way the
/// camera's zoom button opens into its dial and the Dynamic Island timer scrubs. The thumb stays
/// put at the button's centre and the ruler slides under it: six detents, Off and then 0.5× to 1.5×
/// in 0.25 steps, a tick of haptic at each. The bar fades the buttons next to it while `open` and
/// brings them back on release, when the chosen value is applied once (every change restarts the
/// stream, so nothing is sent mid-drag). A nil scale means the Mac window is not fitted: the leftmost
/// detent, Off, one step below 0.5× (`TextScale`; issue #179). Off is not offered while the virtual
/// display is on, where a nil scale is 1× (`offered`). Only a window is sized by it: while anything
/// else streams it is dimmed, its ruler never opens and VoiceOver hears why (`available`,
/// `TextScale.selectable`; Noah, 2026-10-29).
struct TextScaleControl: View {
    @Binding var scale: Double?
    @Binding var open: Bool
    var width: CGFloat = 66
    var height: CGFloat = 66
    var radius: CGFloat = 16
    /// Finger travel (and ruler spacing) per detent; smaller in the tighter bars so the ruler,
    /// centred on the button, stays inside the screen.
    var pointsPerStep: CGFloat = 44
    /// A fixed height for "Aa", and the space under it, so its value lines up with the labels of
    /// bar buttons whose symbols sit in a box of that height (a phone's row 1); nil: as tall as the
    /// text, 2 pt over the value (every bar that has always had it).
    var iconBox: CGFloat? = nil
    var iconSpacing: CGFloat = 2
    /// Whether the ruler has an Off detent (`TextScale.detents`, `TextScale.offersOff`).
    var offered = true
    /// Whether Aa can be used now (`TextScale.selectable`: only while a window streams). Otherwise
    /// dimmed, no ruler, a VoiceOver swipe changes nothing, and VoiceOver hears
    /// `TextScale.unavailableHint`; its value stays, for the next window.
    var available = true
    /// What VoiceOver hears while Aa cannot be used (the off-console view's own, else `TextScale.unavailableHint`).
    var unavailableHint = TextScale.unavailableHint

    var steps: [Double] { TextScale.detents(offered: offered) }
    /// Padding either side of the visible ruler; two detents show each side of the thumb.
    static let sliderInset: CGFloat = 30
    /// The ruler's frame shows two detents either side of the thumb, whatever the detents: Off's
    /// sixth slides in as the finger nears it. So every bar's ruler keeps the width it had with five,
    /// and a phone's row 1 the room it was laid out for (PhonePortraitLayout's `rulerSpans`).
    static let detentsEachSide = 2
    var sliderWidth: CGFloat { pointsPerStep * CGFloat(2 * Self.detentsEachSide) + Self.sliderInset * 2 }
    /// How much of itself a dimmed Aa shows.
    static let unavailableOpacity = 0.35

    @State private var live: Double = 1.0
    @State private var startValue: Double = 1.0
    /// Where the ruler has the scale now.
    private var position: Double { TextScale.position(of: scale, offered: offered) }
    @State private var startX: CGFloat = 0

    var body: some View {
        VStack(spacing: iconBox == nil ? 2 : iconSpacing) {
            if let iconBox {
                Text("Aa")
                    .font(.system(size: height >= 60 ? 19 : 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(height: iconBox)
            } else {
                Text("Aa")
                    .font(.system(size: height >= 60 ? 19 : 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
            Text(TextScale.title(at: position))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.barLabel)
        }
        .opacity(available ? 1 : Self.unavailableOpacity)     // dimmed: Aa sizes a window, and none streams
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.control))
        .opacity(open ? 0 : 1)
        .overlay {
            // Centred on the button: the thumb is where the finger came down.
            slider
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.6)
                .allowsHitTesting(false)
        }
        .zIndex(open ? 1 : 0)
        // A ruler asked open while Aa cannot be used (the harness's `-SillScaleOpen` over the Desktop)
        // folds at once; one open when the window stops streaming (closed on the Mac, the Desktop
        // picked from another device) folds without applying (`onChange(of: available)`, and `onEnded`
        // applies nothing while Aa cannot be used).
        .onChange(of: open, initial: true) { _, isOpen in
            guard isOpen else { return }
            if available { live = position } else { open = false }
        }
        .onChange(of: available) { _, now in if !now, open { withAnimation(.easeOut(duration: 0.2)) { open = false } } }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { g in
                    if !open {
                        startValue = position
                        live = startValue
                        startX = g.location.x
                        withAnimation(.spring(duration: 0.22, bounce: 0.15)) { open = true }
                    }
                    // The ruler follows the finger: dragging right raises the value, and the ticks
                    // slide left under the fixed thumb.
                    let dx = g.location.x - startX
                    let snapped = TextScale.snap(startValue + Double(dx / pointsPerStep) * 0.25, offered: offered)
                    if snapped != live {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeOut(duration: 0.1)) { live = snapped }
                    }
                }
                .onEnded { _ in
                    // A plain tap on an untouched control changes nothing, and nor does a drag the
                    // stream left a window during.
                    if available, position != live { scale = TextScale.scale(at: live) }
                    withAnimation(.easeOut(duration: 0.2)) { open = false }
                },
            including: available ? .all : .none      // dimmed: a touch opens nothing
        )
        .onDisappear { open = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text size")
        .accessibilityValue(TextScale.spoken(at: position))
        .accessibilityHint(available ? "" : unavailableHint)
        // Always adjustable, so Aa stays one view and one accessibility element when a window starts or
        // stops streaming: VoiceOver keeps its place on it, and the ruler's fold above runs. Dimmed, it
        // is what a disabled slider is ("dimmed, adjustable"): a swipe changes nothing. (Adding the
        // action only while Aa can be used made a new view and element at every change: the review of
        // #181.)
        .accessibilityAdjustableAction { direction in
            guard available else { return }
            switch direction {
            case .increment: scale = TextScale.scale(at: TextScale.step(from: position, up: true, offered: offered))
            case .decrement: scale = TextScale.scale(at: TextScale.step(from: position, up: false, offered: offered))
            @unknown default: break
            }
        }
        .disabled(!available)     // VoiceOver: "dimmed"
    }

    /// The ruler: a track with a tick and a label at each detent that slides so the live value sits
    /// under the fixed thumb; the ends fade out where they run past the frame (two detents each side).
    private var slider: some View {
        let w = sliderWidth
        let step = pointsPerStep
        let midX = w / 2
        let midY = height / 2 + 4
        func x(_ value: Double) -> CGFloat { midX + CGFloat((value - live) / 0.25) * step }
        let steps = self.steps
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.controlOpen)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.barLabel.opacity(0.35))
                    .frame(width: step * CGFloat(steps.count - 1), height: 3)
                    .offset(x: x(steps[0]), y: midY - 1.5)
                ForEach(steps, id: \.self) { value in
                    Rectangle().fill(Palette.barLabel.opacity(0.6))
                        .frame(width: 2, height: 9)
                        .offset(x: x(value) - 1, y: midY - 4.5)
                    Text(value == TextScale.off ? "Off" : TextScale.number(value))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(value == live ? Palette.text : Palette.barLabel)
                        .frame(width: step, alignment: .center)
                        .offset(x: x(value) - step / 2, y: midY + 9)
                }
            }
            .frame(width: w, height: height, alignment: .topLeading)   // the mask below is sized to this
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            Circle().fill(Palette.accent)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .offset(x: midX - 11, y: midY - 11)
            // The live value over the thumb, where the finger does not cover it. In a 50 pt ruler
            // (a phone's row 1, the compact window bar) `midY - 34` put the top of its digits 2 pt
            // outside the clip; it sits where the 58 pt bars put it (1 pt above the frame's top,
            // the digits 2 pt inside), and in the taller bars as it always has.
            Text(TextScale.title(at: live))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 60, alignment: .center)
                .offset(x: midX - 30, y: max(midY - 34, -1))
        }
        .frame(width: w, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 0.5, 0.75, 1, 1.25, 1.5: trailing zeros dropped, and "1" rather than "1.0".
    static func label(_ scale: Double) -> String { TextScale.number(scale) }
}

// MARK: - Window thumbnails

/// The live window thumbnails. Defaults are the roomy top bar's numbers; the compact bars are
/// tighter (92×58 gap 14 fade 88%, and 80×50 radius 8 gap 12 with a 22 pt badge on the outer
/// display), so every size travels as a parameter and the thumbnail, its badge and its active halo
/// stay one view in every posture.
struct WindowStrip: View {
    @ObservedObject var client: StreamClient
    var width: CGFloat = 104
    var height: CGFloat = 66
    var radius: CGFloat = 10
    var spacing: CGFloat = 16
    /// Room above and below for the badge (6 pt out) and the active halo (5 pt out), which the
    /// ScrollView would otherwise clip. It is also what makes the strip as tall as its bar.
    var pad: CGFloat = 10
    var fade: Double = 0.86
    var badge: CGFloat = 24
    /// Which thumbnail has its traffic-light submenu open. Owned by the screen root, which draws
    /// the submenu outside this clipped strip.
    @Binding var menuFor: UInt32?

    /// Press and hold a thumbnail for the hold (ThumbnailHold: 0.5 s unless changed in Settings ›
    /// This iPad or iPhone, 0.2 to 3 s; issue #113, it was a fixed 1.5 s): it starts to wiggle and its traffic
    /// lights (close, minimize, full screen) appear in a submenu beside it, the way a held Home Screen
    /// icon offers its menu. Keep holding and move: the submenu goes, the thumbnail lifts and drags
    /// into a new slot. The arrangement is the device's own, persisted per Mac. A tap selects.
    ///
    /// `Sill.thumbnailHold`, read for its changes (the panel's stepper writes it, and this redraws the
    /// strip, whose thumbnails take the new length at once); the length itself through
    /// `ThumbnailHold.seconds(stored:)`, since `-Sill.thumbnailHold 0.3` is a string in UserDefaults.
    @AppStorage(ThumbnailHold.key) private var storedHold = ThumbnailHold.standard
    private var hold: TimeInterval {
        _ = storedHold
        return ThumbnailHold.seconds(stored: UserDefaults.standard.object(forKey: ThumbnailHold.key))
    }
    #if DEBUG
    /// The last length the console was told ("thumbnails: hold 0.5 s"), so a strip that comes and goes
    /// (a rotation, another bar) says it only when it changes.
    @MainActor private static var loggedHold: TimeInterval?
    @MainActor private static func logHold(_ hold: TimeInterval) {
        guard loggedHold != hold else { return }
        loggedHold = hold
        print(ThumbnailHold.consoleLine(hold))
    }
    #endif
    /// What the tour lights of the strip: its thumbnails' band (the strip is as tall as its bar),
    /// with the active halo's 5 pt above and the app badge's 6 pt below.
    static func tourBand(pad: CGFloat) -> EdgeInsets {
        EdgeInsets(top: max(0, pad - 5), leading: 0, bottom: max(0, pad - 6), trailing: 0)
    }
    @State private var lifted: UInt32? = nil
    @State private var liftOffset: CGFloat = 0
    @State private var liftStartIndex = 0

    var body: some View {
        let windows = client.orderedWindows
        let slot = width + spacing
        let hold = self.hold    // read here, in the body, so a change of the setting redraws the strip
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    WindowThumbnail(window: window,
                                    image: client.thumbnails[window.id],
                                    icon: client.icons[window.bundleID],
                                    isActive: client.active == .window(window.id),
                                    width: width, height: height, radius: radius, badge: badge,
                                    menuOpen: menuFor == window.id,
                                    lifted: lifted == window.id,
                                    onSelect: { client.select(.window(window.id)) },
                                    onCommand: { client.command($0, window: window.id) },
                                    onMove: { step in
                                        client.moveWindow(window.id, to: index + step)
                                        client.persistWindowOrder()
                                    })
                        .overlay {
                            HoldDragOverlay(minimumHold: hold,
                                            onTap: { if menuFor != nil { closeMenu() } else { client.select(.window(window.id)) } },
                                            onHold: { openMenu(for: window.id) },
                                            onMove: { t in holdMoved(window: window, index: index, count: windows.count, slot: slot, translation: t) },
                                            onEnd: { holdEnded(window: window) })
                        }
                        .offset(x: lifted == window.id ? liftOffset : 0)
                        .zIndex(lifted == window.id ? 1 : 0)
                        // The lifted thumbnail follows the finger: its slot change must not animate,
                        // or the layout springs one way while the compensating offset jumps the other.
                        .transaction { if lifted == window.id { $0.animation = nil } }
                }
            }
            .padding(.vertical, pad)
            .padding(.horizontal, 8)
        }
        .coordinateSpace(name: "strip")
        .scrollDisabled(lifted != nil)
        .frame(maxWidth: .infinity)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: fade),
                                     .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .onChange(of: client.windows) { _, now in
            // A window that closed or minimized takes its menu, and any drag, with it.
            if let id = menuFor, !now.contains(where: { $0.id == id }) { closeMenu() }
            if let id = lifted, !now.contains(where: { $0.id == id }) {
                lifted = nil; liftOffset = 0
                client.persistWindowOrder()
            }
        }
        .onDisappear { lifted = nil; liftOffset = 0 }
        #if DEBUG
        // Harness: `-SillWindowMenu 1` opens the first window's submenu at launch.
        .onAppear {
            Self.logHold(hold)
            if UserDefaults.standard.bool(forKey: "SillWindowMenu"), let first = client.orderedWindows.first { menuFor = first.id }
        }
        .onChange(of: hold) { _, now in Self.logHold(now) }
        #endif
    }

    /// The finger moved while the hold is still down. More than 8 pt lifts the thumbnail and
    /// drags it; the drag reorders live: crossing the middle of a neighbour swaps slots, and the
    /// lifted thumbnail's offset is corrected by the slots it has moved so it stays under the finger.
    private func holdMoved(window: WindowInfo, index: Int, count: Int, slot: CGFloat, translation t: CGSize) {
        if lifted == nil {
            guard abs(t.width) > 8 || abs(t.height) > 8 else { return }
            closeMenu()
            lifted = window.id
            liftStartIndex = index
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        guard lifted == window.id else { return }
        let shift = Int((t.width / slot).rounded())
        let target = max(0, min(count - 1, liftStartIndex + shift))
        if let current = client.orderedWindows.firstIndex(where: { $0.id == window.id }), current != target {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) { client.moveWindow(window.id, to: target) }
        }
        liftOffset = t.width - CGFloat(target - liftStartIndex) * slot
    }

    /// The finger lifted after a hold: drop the thumbnail (the submenu, if open, stays).
    private func holdEnded(window: WindowInfo) {
        guard lifted == window.id else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { lifted = nil; liftOffset = 0 }
        client.persistWindowOrder()
    }

    private func openMenu(for id: UInt32) {
        guard menuFor != id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        menuFor = id
    }

    private func closeMenu() { menuFor = nil }
}

/// A thumbnail's touch handling, in UIKit: a tap selects; a hold of `minimumHold` opens the
/// submenu and keeps tracking the finger, so moving it afterwards drags. UIKit rather than SwiftUI
/// gestures because a SwiftUI long press sequenced with a drag swallowed plain taps inside the
/// ScrollView (2026-09-23), and UIKit's long press is exactly the Home Screen mechanic: by the time
/// it recognizes, the scroll view's pan has already given up, so the drag is ours.
struct HoldDragOverlay: UIViewRepresentable {
    /// The hold's length (ThumbnailHold): a change reaches the long press already made, so the
    /// thumbnails on screen wait the new length from their next press.
    var minimumHold: TimeInterval
    var onTap: () -> Void
    var onHold: () -> Void
    /// Translation since the hold began, in window coordinates (stable while the view moves).
    var onMove: (CGSize) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = minimumHold
        hold.allowableMovement = 12        // more than this before the hold fires is a scroll, not a hold
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        context.coordinator.hold = hold
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        // Settings › This iPad (or iPhone) changed the hold: this thumbnail's next press waits the new length.
        if let hold = context.coordinator.hold, hold.minimumPressDuration != minimumHold { hold.minimumPressDuration = minimumHold }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: HoldDragOverlay
        /// The thumbnail's long press, for `updateUIView` to give it a new length.
        weak var hold: UILongPressGestureRecognizer?
        private var start = CGPoint.zero
        init(_ parent: HoldDragOverlay) { self.parent = parent }

        @objc func tapped() { parent.onTap() }

        @objc func held(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: g.view?.window)
            switch g.state {
            case .began: start = p; parent.onHold()
            case .changed: parent.onMove(CGSize(width: p.x - start.x, height: p.y - start.y))
            case .ended, .cancelled, .failed: parent.onEnd()
            default: break
            }
        }
    }
}

/// The frame of the thumbnail whose submenu is open, reported up to the screen root.
struct WindowMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

/// macOS's three lights in a floating submenu beside the held thumbnail: below it when the bar
/// is at the top of the screen, above it when the bar is at the bottom (portrait's halves), and
/// always below it on a phone upright, where the strip sits under row 1 and the key row below has
/// room on every phone (above, it would cover row 1 on the shortest). A tap anywhere else
/// dismisses it. Drawn by the screen root, over everything.
struct WindowLightsMenu: View {
    let anchor: Anchor<CGRect>
    let window: WindowInfo
    let command: (WindowCommand.Action) -> Void
    let dismiss: () -> Void
    /// Whether a screen of this size always puts the lights below the thumbnail (the phone's
    /// arrangement); otherwise they go on the side of the screen's middle away from it.
    var alwaysBelow: (CGSize) -> Bool = { _ in false }

    private static let size = CGSize(width: 214, height: 62)
    /// The Duo's hinge (iOS 27.1): the lights keep off its fold.
    @Environment(\.duoEnvironment) private var duoEnvironment

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy[anchor]
            let w = Self.size.width, h = Self.size.height
            // Off the Duo's fold (iOS 27.1): onto a page beside it, below the thumbnail when above it
            // would sit on it; elsewhere as before.
            let at = DuoPosture.lightsMenu(x: min(max(frame.midX, w / 2 + 8), proxy.size.width - w / 2 - 8),
                                           below: alwaysBelow(proxy.size) || frame.midY < proxy.size.height / 2,
                                           thumbnail: frame, size: Self.size, gap: 8, screenWidth: proxy.size.width,
                                           fold: DuoPosture.read(proxy, duoEnvironment).info(in: proxy.size))
            let below = at.below, x = at.x, y = at.y
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: dismiss)
                HStack(spacing: 6) {
                    light(.close, Color(hex: 0xFF5F57), "xmark", "Close")
                    light(.minimize, Color(hex: 0xFEBC2E), "minus", "Minimize")
                    light(.fullScreen, Color(hex: 0x28C840), "arrow.up.left.and.arrow.down.right", "Full Screen")
                }
                .padding(.horizontal, 10)
                .frame(width: w, height: h)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.control)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                )
                .position(x: x, y: y)
                .transition(.scale(scale: 0.8, anchor: below ? .top : .bottom).combined(with: .opacity))
            }
            .accessibilityLabel("\(window.appName) window actions")
        }
    }

    private func light(_ action: WindowCommand.Action, _ color: Color, _ symbol: String, _ label: String) -> some View {
        Button { command(action) } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(color).frame(width: 24, height: 24)
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.65))
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.barLabel)
                    .lineLimit(1)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) window")
    }
}

private struct WindowThumbnail: View {
    let window: WindowInfo
    let image: UIImage?
    let icon: UIImage?
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let badge: CGFloat
    let menuOpen: Bool
    let lifted: Bool
    /// VoiceOver's routes to what the finger does with a tap, the hold submenu and the drag.
    let onSelect: () -> Void
    let onCommand: (WindowCommand.Action) -> Void
    let onMove: (Int) -> Void

    var body: some View {
        // Two stages: one long chain of modifiers here is more than the type checker will take.
        card
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.appName) window: \(window.title)" + (isActive ? ", showing now" : ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { onSelect() }
            .accessibilityAction(named: "Close window") { onCommand(.close) }
            .accessibilityAction(named: "Minimize window") { onCommand(.minimize) }
            .accessibilityAction(named: "Full screen") { onCommand(.fullScreen) }
            .accessibilityAction(named: "Move left") { onMove(-1) }
            .accessibilityAction(named: "Move right") { onMove(1) }
    }

    /// The thumbnail with its badge, halo, wiggle and lift.
    private var card: some View {
        let halo = RoundedRectangle(cornerRadius: radius + 5, style: .continuous)
            .strokeBorder(Palette.accent, lineWidth: 2)
            .padding(-5)
        return preview
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            // The active halo sits under the app badge: the badge's bar-coloured ring then reads as
            // cutting through the halo, instead of the halo slicing across the icon. It follows the
            // thumbnail's own radius so both sizes keep the same 3 pt gap.
            .overlay { if isActive { halo } }
            // The badge barely scales with the thumbnail; it is the app's identity, not chrome,
            // so it only shrinks once, to 22 pt, on the outer display's smallest bar.
            .overlay(alignment: .bottomLeading) { appBadge.offset(x: -6, y: 6) }
            // Held: the Home Screen wiggle, until the submenu is dismissed. Lifted: bigger, with a shadow.
            .rotationEffect(.degrees(menuOpen ? 1.8 : 0))
            .offset(y: menuOpen ? -1 : 0)
            .animation(menuOpen ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .easeOut(duration: 0.15),
                       value: menuOpen)
            .scaleEffect(lifted ? 1.08 : (menuOpen ? 1.04 : 1))
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 10, y: 4)
            .anchorPreference(key: WindowMenuAnchorKey.self, value: .bounds) { menuOpen ? $0 : nil }
    }

    @ViewBuilder private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            VStack(spacing: 0) {
                Palette.thumbTitleBar.frame(height: 9)
                Palette.thumbBody
            }
        }
    }

    /// The app icon, with a 2 pt bar-coloured ring around it so it cuts through the thumbnail's
    /// edge and its halo instead of sitting on top of them.
    private var appBadge: some View {
        let corner = (badge * 0.29).rounded()      // 7 at 24 pt, 6 at 22
        return AppIcon(image: icon, name: window.appName, size: badge, radius: corner,
                       fontSize: (badge * 0.42).rounded())
            .background {
                RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                    .fill(Palette.bar)
                    .frame(width: badge + 4, height: badge + 4)
            }
    }
}

/// An app icon, or its first two letters while the host has not sent one.
struct AppIcon: View {
    let image: UIImage?
    let name: String
    let size: CGFloat
    let radius: CGFloat
    let fontSize: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Palette.iconFallback.overlay(
                    Text(String(name.prefix(2)))
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - App drawer

private struct OpenApp: Identifiable {
    let bundleID: String
    let name: String
    let windows: [WindowInfo]
    var id: String { bundleID }
}

struct AppDrawer: View {
    @ObservedObject var client: StreamClient
    @Binding var drawerOpen: Bool
    @State private var search = ""
    /// The search field has the keyboard. Set only by DEBUG `-SillDrawerSearch` (ContentView's
    /// contract); a tap focuses the field as before.
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if let why = client.lockWhy, !client.lockView {
                // A locked Mac sends no windows, apps or icons (its LockPolicy, docs/locked-mac-plan.md),
                // and launches nothing: one line where they would be.
                lockedLine(why)
                Spacer(minLength: 0)
            } else {
                // The off-console view (docs/off-console-plan.md): what the picture is, above the open apps; nothing
                // is launched then, so no All apps.
                if client.lockView { viewLine }
                searchField
                ScrollView {
                    VStack(spacing: 6) {
                        if !openApps.isEmpty {
                            header("Open now")
                            ForEach(openApps) { app in
                                DrawerRow(height: 50,
                                          highlighted: app.bundleID == activeBundleID,
                                          title: app.name,
                                          trailing: app.windows.count == 1 ? "1 window" : "\(app.windows.count) windows",
                                          action: { show(app) }) {
                                    AppIcon(image: client.icons[app.bundleID], name: app.name,
                                            size: 32, radius: 9, fontSize: 12)
                                }
                            }
                        }
                        if !closedApps.isEmpty, !client.lockView {
                            header("All apps").padding(.top, 2)
                            ForEach(closedApps) { app in
                                DrawerRow(height: 46, highlighted: false, title: app.name, trailing: nil,
                                          action: { client.launch(bundleID: app.bundleID) }) {
                                    AppIcon(image: client.icons[app.bundleID], name: app.name,
                                            size: 32, radius: 9, fontSize: 12)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.bar))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 30, x: 0, y: 24)
    }

    /// A locked Mac (`StreamClient.lockWhy`): one line in place of the search field and both lists, read
    /// by VoiceOver as it is (the lock symbol is not).
    private func lockedLine(_ why: LockedMac.Why) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: why == .otherUser ? "person.2.fill" : "lock.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(LockedMac.line(mac: client.macName, why: why))
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }

    /// The off-console view's line, in the locked line's look (person.2.fill), read by VoiceOver as it is.
    private var viewLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(LockedMac.viewPanelLine)
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(Palette.muted)
            TextField("", text: $search,
                      prompt: Text("Search apps on \(client.macName)").foregroundColor(Palette.muted))
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel("Search apps on this Mac")
                .focused($searchFocused)
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
        #if DEBUG
        .onAppear(perform: searchFromLaunchArguments)
        #endif
    }

    #if DEBUG
    /// `-SillDrawerSearch <text>` (ContentView's contract): the drawer, once open, searches for that
    /// text with the keyboard up for its field, as a tap and typing would, so a photo shows what the
    /// keyboard leaves in view of the results.
    private func searchFromLaunchArguments() {
        guard let query = UserDefaults.standard.string(forKey: "SillDrawerSearch") else { return }
        search = query
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            searchFocused = true
            print("harness: the drawer's search field has the keyboard, searching for \"\(query)\"")
        }
    }
    #endif

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }

    // MARK: Contents

    /// Running apps, grouped from the window list and kept in its front-to-back order.
    private var openApps: [OpenApp] {
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [WindowInfo]] = [:]
        for window in client.windows {
            if grouped[window.bundleID] == nil {
                order.append(window.bundleID)
                names[window.bundleID] = window.appName
            }
            grouped[window.bundleID, default: []].append(window)
        }
        return order.map { OpenApp(bundleID: $0, name: names[$0] ?? $0, windows: grouped[$0] ?? []) }
            .filter { matches($0.name) }
    }

    private var closedApps: [AppInfo] {
        let running = Set(client.windows.map(\.bundleID))
        return client.apps
            .filter { !running.contains($0.bundleID) && matches($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var activeBundleID: String? {
        guard case .window(let id) = client.active else { return nil }
        return client.windows.first { $0.id == id }?.bundleID
    }

    private func matches(_ name: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || name.range(of: query, options: .caseInsensitive) != nil
    }

    /// First window of the app, or the next one if this app is already showing.
    private func show(_ app: OpenApp) {
        guard !app.windows.isEmpty else { return }
        var target = app.windows[0]
        if case .window(let id) = client.active,
           let index = app.windows.firstIndex(where: { $0.id == id }) {
            target = app.windows[(index + 1) % app.windows.count]
        }
        client.select(.window(target.id))
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
    }
}

/// One app row: icon, name, optional trailing count.
struct DrawerRow<Leading: View>: View {
    let height: CGFloat
    let highlighted: Bool
    let title: String
    let trailing: String?
    let action: () -> Void
    let leading: () -> Leading

    init(height: CGFloat, highlighted: Bool, title: String, trailing: String?,
         action: @escaping () -> Void, @ViewBuilder leading: @escaping () -> Leading) {
        self.height = height
        self.highlighted = highlighted
        self.title = title
        self.trailing = trailing
        self.action = action
        self.leading = leading
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    // Whole, on one line, whatever the title's length: the title truncates instead
                    // ("Not paired", "Update Sill" and "3 windows" hold a space).
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? Palette.control : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Larger Picture's view of what streams

extension PhonePortraitLayout.Streaming {
    /// What the Mac's window list says streams (`StreamClient.active`), as Larger Picture's rule
    /// (`PhonePortraitLayout.largerPicture(switchOn:streaming:)`) reads it.
    init(_ source: StreamSource) {
        switch source {
        case .none: self = .nothing
        case .desktop: self = .desktop
        case .window: self = .window
        }
    }
}
