import SwiftUI
import StreamProtocol

/// The tactile connect screen (the Slice 0 contract's consumer): the Macs the browsers found and the
/// saved ones they do not list, as machined display cards in an adaptive grid — one column on a
/// phone held upright, two on an iPad or any window at least 680 pt wide. Each card is a recessed
/// hardware surface (`TactileSurfaceRole.recessedHardware`, never Liquid Glass, which does not
/// belong inside a ScrollView) framing a 16:10 dark-anodized bezel with the Mac's kept picture
/// (`StreamClient.macPreviews`, synced to `.tiles` on appear), its name, a `TactileLED` for how it
/// is reachable (emerald Wired, cyan Wi-Fi, amber Direct, blue Remote, dark when a tap cannot
/// connect: "Not paired", "Update Sill", or a route the interfaces do not name), and its route word.
///
/// Add a Mac, a sill://pair link's confirmation (`client.pendingLink`, LinkConfirmation) and the
/// home card (`client.homeAsk`, AddMacCard's `home:`) open as native sheets over the grid. A saved
/// Mac's context menu keeps the connect screen's actions: Connect Remotely on a network row, its
/// group, Remove Preview Picture, and Forget. The footer carries the auto-reconnect switch
/// (`Sill.autoReconnectEnabled`): on, and the Mac last tapped (`Sill.lastConnectedMacID`) shows
/// reachable on this screen, a floating pill counts down 1.5 s before connecting, with Cancel.
///
/// `suppressAutoReconnectOnAppear` lets a caller show this screen without the countdown (coming back
/// from a session the person ended). `scannerOverride` is the DEBUG harness's stand-in for the
/// camera, as ConnectScreen's is.
struct TactileConnectView: View {
    @ObservedObject var client: StreamClient
    var suppressAutoReconnectOnAppear: Bool = false
    /// The DEBUG harness's stand-in for the camera (the simulator has none); nil on a device.
    var scannerOverride: CodeScanner.Mode? = nil

    /// The card up in a sheet: Add a Mac, the home card for a Mac showing its code, or an outside
    /// link's confirmation. One sheet slot, so a link's Pair swaps straight into the card.
    private enum CardSheet: Identifiable, Equatable {
        case addMac
        case home(String)
        case link(PairLink)

        var id: String {
            switch self {
            case .addMac: return "addMac"
            case .home(let name): return "home:\(name)"
            case .link(let link): return "link:\(link.name)"
            }
        }
    }

    @State private var sheet: CardSheet?
    /// The card's typed path (the scanner, or the fields); set when a sheet opens, as ConnectScreen
    /// does: where the scanner cannot run, the fields come first.
    @State private var typed = false
    /// A field of the card has the keyboard.
    @State private var editing = false
    /// The saved Mac whose New Group… alert is up, and the name typed there.
    @State private var newGroupFor: String?
    @State private var newGroupName = ""

    /// The person's choice: reconnect to the last Mac on launch. Off until they turn it on.
    @AppStorage("Sill.autoReconnectEnabled") private var autoReconnectEnabled = false
    /// The saved ID of the Mac last tapped (`FoundMac.savedID`: its tag's, else its Bonjour name's).
    @AppStorage("Sill.lastConnectedMacID") private var lastConnectedMacID = ""

    /// The Mac the floating pill counts down to; nil while nothing counts.
    @State private var reconnectMac: FoundMac?
    /// A cancel suppresses the countdown until this screen is made again (the next launch).
    @State private var reconnectSuppressed = false
    @State private var reconnectTask: Task<Void, Never>?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var device: String { StreamClient.deviceWord }
    private var scannerMode: CodeScanner.Mode { scannerOverride ?? CodeScanner.currentMode }
    /// Where the scanner cannot run (the simulator), the card starts on the typed path.
    private var scannerUsable: Bool { scannerOverride != nil || CodeScanner.isSupported }

    /// The wait the floating pill counts down before it connects.
    private static let reconnectWait: Duration = .seconds(1.5)

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                grid(geo)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        reconnectPill
                    }
            }
            .background(TactileTokens.canvasBlack.ignoresSafeArea())
            .navigationTitle("Sill")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        TactileHaptics.play(.detent)
                        openCard(nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .tactileButton(.secondary, shape: .circle)
                    .accessibilityLabel("Add a Mac")
                    .accessibilityHint("Pairs this \(device) with a Mac so you can reach it away from home.")
                }
            }
            .sheet(item: $sheet, content: sheetContent)
            .alert("New Group", isPresented: Binding(get: { newGroupFor != nil }, set: { if !$0 { newGroupFor = nil } })) {
                TextField("Name", text: $newGroupName)
                // A blank name, or Other (where the Macs with no group already are), names no group.
                Button("Add") { if let id = newGroupFor { client.setGroup(newGroupName, for: id) } }
                    .disabled(ConnectionList.cleanGroup(newGroupName) == nil)
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                client.syncPreviews(to: .tiles)
                maybeReconnect()
            }
            .onDisappear {
                reconnectTask?.cancel()
                reconnectTask = nil
            }
            .onChange(of: client.macs) { _, _ in maybeReconnect() }
            .onChange(of: client.pendingLink, initial: true) { _, link in
                if let link {
                    sheet = .link(link)
                } else if case .link = sheet {
                    sheet = nil
                }
            }
            .onChange(of: client.homeAsk, initial: true) { _, ask in
                if let ask, ask.phase == .shown {
                    // The Mac shows its code: the home card for that row, unless already up.
                    if sheet != .home(ask.name) { openCard(ask.name) }
                } else if ask == nil, isHomeSheet {
                    // The ask ended while the card was up. A pairing that went through keeps the card
                    // until the session comes, or the pairing observer below folds it.
                    switch client.pairing {
                    case .working, .paired: break
                    case .idle, .failed: sheet = nil
                    }
                }
            }
            .onChange(of: client.pairing) { old, new in
                // Paired but no session came: the card closes, and the Mac is a saved card.
                if case .paired = old, new == .idle, !client.connected { sheet = nil }
            }
        }
    }

    private var isHomeSheet: Bool {
        if case .home = sheet { return true }
        return false
    }

    // MARK: The grid

    private func grid(_ geo: GeometryProxy) -> some View {
        // One column on a phone held upright, two on an iPad (a regular size class) or any window
        // at least 680 pt wide. Accessibility text sizes keep one column, as ConnectionList.columns
        // does for its tiles.
        let two = (horizontalSizeClass == .regular || geo.size.width >= 680) && !typeSize.isAccessibilitySize
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: two ? 2 : 1)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                // The discovery status under the title: what the search is doing, or what happened.
                Text(client.status)
                    .font(.footnote)
                    .foregroundStyle(TactileTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if client.macs.isEmpty {
                    emptyState
                } else {
                    let sections = ConnectionList.sections(
                        for: client.macs,
                        macID: { ConnectionList.tileMac(macID: $0.macID, savedByName: $0.savedByName) },
                        groups: client.macGroups)
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TactileTokens.textSecondary)
                                .textCase(.uppercase)
                                .accessibilityAddTraits(.isHeader)
                        }
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(section.items) { mac in
                                macCard(mac)
                            }
                        }
                    }
                }

                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// No Mac found: a hardware card that says so, with Search Nearby while it can still help
    /// (`client.showsNearbyHint`) or its "Also looking nearby" line once asked.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(TactileTokens.textSecondary)
                .frame(maxWidth: .infinity)
            if client.showsNearbyHint {
                if client.searchingNearby {
                    Text("Also looking nearby")
                        .font(.system(size: 15))
                        .foregroundStyle(TactileTokens.textSecondary)
                        .frame(minHeight: 44)
                } else {
                    Button {
                        TactileHaptics.play(.detent)
                        client.searchNearby()
                        AccessibilityNotification.Announcement("Also looking nearby").post()
                    } label: {
                        Text("Search Nearby")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(minHeight: 44)
                    }
                    .tactileRecessedButton(.secondary, shape: .capsule)
                    .accessibilityHint("Also looks for a Mac with Direct Wireless Connection turned on, without a Wi\u{2011}Fi network.")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .tactileSurface(.recessedHardware, shape: .rounded(20))
    }

    // MARK: A Mac's card

    /// The LED's colour and whether it is lit: the route's word (Wired, Wi-Fi, Direct, Remote), or
    /// dark for a Mac a tap cannot connect ("Not paired", "Update Sill", a route the interfaces do
    /// not name). The same test tells the auto-reconnect whether a Mac is reachable.
    private func routeLED(_ mac: FoundMac) -> (color: Color, lit: Bool) {
        if mac.route == .remote { return (TactileTokens.ledBlue, true) }
        if case .method(let method) = mac.homeWord, let method {
            switch method {
            case .wired: return (TactileTokens.ledEmerald, true)
            case .wifi: return (TactileTokens.ledCyan, true)
            case .direct: return (TactileTokens.ledAmber, true)
            }
        }
        // Over the cable an unpaired Mac pairs by itself, then connects: lit, as a Wired row is.
        if mac.homeWord == .pairsOverCable { return (TactileTokens.ledEmerald, true) }
        return (TactileTokens.textSecondary, false)
    }

    /// The card's saved Mac: whose picture its bezel shows, whose group it is filed under, and whose
    /// menu it gets (ConnectionList.tileMac: a tag's Mac, else one taken by its Bonjour name).
    private func tileMac(_ mac: FoundMac) -> String? {
        ConnectionList.tileMac(macID: mac.macID, savedByName: mac.savedByName)
    }

    /// The row a tap's ask is waiting on (the Mac is being asked to show its code): its card stays
    /// lit while the status line says "Pairing with…".
    private func asking(_ mac: FoundMac) -> Bool {
        client.homeAsk.map { $0.phase == .asking && $0.target.row == mac.id } ?? false
    }

    private func macCard(_ mac: FoundMac) -> some View {
        let led = routeLED(mac)
        let preview = tileMac(mac).flatMap { client.macPreviews[$0] }
        return Button {
            connect(mac)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                bezel(preview: preview)
                HStack(spacing: 8) {
                    TactileLED(isOn: led.lit, color: led.color)
                    Text(mac.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TactileTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let word = mac.word {
                        Text(word)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(led.lit ? led.color : TactileTokens.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(TactileTokens.chassisRaised))
                    }
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .tactileSurface(.recessedHardware, shape: .rounded(20))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(asking(mac) ? TactileTokens.ledCyan.opacity(0.55) : .clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel(cardLabel(mac))
        .accessibilityHint(cardHint(mac))
        .contextMenu { macMenu(mac) }
    }

    /// The 16:10 dark-anodized display bezel: a machined frame around the screen, which is the Mac's
    /// kept picture or a machined monitor glyph until one lands.
    private func bezel(preview: UIImage?) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(TactileTokens.chassisDark)
            .aspectRatio(1.6, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TactileTokens.trackpadWell)
                    .overlay {
                        if let preview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        } else {
                            Image(systemName: "display")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(TactileTokens.textSecondary.opacity(0.55))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [TactileTokens.specularRimTop, TactileTokens.specularRimBottom],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    /// A saved Mac's menu, as the connect screen's rows offer it: Connect (a Remote card) or Connect
    /// Remotely (its network card, to try the VPN path at home), its group, Remove Preview Picture,
    /// and Forget. Other Macs' cards have no menu.
    @ViewBuilder private func macMenu(_ mac: FoundMac) -> some View {
        if let id = mac.macID {
            if mac.route == .remote {
                Button { connect(mac) } label: { Label("Connect", systemImage: "globe") }
            } else if mac.route == .network {
                Button { client.connectRemotely(id) } label: { Label("Connect Remotely", systemImage: "globe") }
            }
            let currentGroup = ConnectionList.cleanGroup(client.macGroups[id])
            Menu {
                Picker("Group", selection: Binding(get: { currentGroup }, set: { client.setGroup($0, for: id) })) {
                    Text("None").tag(String?.none)
                    ForEach(ConnectionList.availableGroups(in: client.macGroups), id: \.self) { group in
                        Text(group).tag(String?.some(group))
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button { newGroupName = ""; newGroupFor = id } label: {
                    Label("New Group…", systemImage: "folder.badge.plus")
                }
            } label: {
                Label(currentGroup.map { "Group: \($0)" } ?? "Group", systemImage: "folder")
            }
            if client.macPreviews[id] != nil {
                Button(role: .destructive) { client.removePreview(for: id) } label: {
                    Label("Remove Preview Picture", systemImage: "photo.badge.minus")
                }
            }
            let name = client.savedMac(id) != nil ? client.displayName(id) : mac.name
            Button(role: .destructive) { client.forget(id) } label: { Label("Forget \(name)", systemImage: "trash") }
        }
    }

    private func cardLabel(_ mac: FoundMac) -> String {
        mac.route == .remote ? "\(mac.name), Remote" : mac.homeWord.label(name: mac.name)
    }

    private func cardHint(_ mac: FoundMac) -> String {
        mac.route == .remote ? "Connects through your VPN or the internet."
            : mac.homeWord.hint(name: mac.name, device: device, direct: mac.direct)
    }

    private func connect(_ mac: FoundMac) {
        TactileHaptics.play(.tick)
        if let id = mac.savedID { lastConnectedMacID = id }
        client.connect(to: mac)
    }

    // MARK: The sheets

    /// Add a Mac (a nil `home`), or the home card for a Mac showing its code: the sheet opens on the
    /// scanner, or on the typed path where the scanner cannot run.
    private func openCard(_ home: String?) {
        if home == nil {
            client.cancelHomeAsk()      // a tap's ask still waiting for its answer: Add a Mac is another way
            client.pairing = .idle
        }
        // The home card leaves the ask and the pairing as they are: its ask already answered, and
        // the pairing the answer started is what the card shows.
        typed = !scannerUsable
        editing = false
        sheet = home.map { .home($0) } ?? .addMac
    }

    /// Cancel and Esc on either card: the ask or pairing in flight stops, and the sheet folds.
    private func closeSheet() {
        client.cancelPairing()
        editing = false
        sheet = nil
    }

    @ViewBuilder private func sheetContent(_ sheet: CardSheet) -> some View {
        switch sheet {
        case .addMac:
            cardSheet(home: nil)
        case .home(let name):
            cardSheet(home: name)
        case .link(let link):
            NavigationStack {
                LinkConfirmation(link: link, pair: {
                    // The card shows the pairing's progress; should it fail, the scanner (or the
                    // typed path where there is none) is there to try again.
                    client.confirmPendingLink()
                    openCard(nil)
                }, cancel: {
                    client.cancelPendingLink()
                })
                .padding(20)
                .background(TactileTokens.canvasBlack.ignoresSafeArea())
                .navigationTitle("Add a Mac")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    private func cardSheet(home: String?) -> some View {
        NavigationStack {
            GeometryReader { geo in
                let layout = ConnectLayout(size: geo.size)
                ScrollView(.vertical) {
                    AddMacCard(client: client, layout: layout, typed: $typed, scannerMode: scannerMode,
                               close: closeSheet, editing: $editing, home: home)
                        .frame(width: layout.short && !typed ? layout.sideBySideWidth : layout.columnWidth,
                               alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(TactileTokens.canvasBlack.ignoresSafeArea())
            .navigationTitle(home.map { DiscoveryPolicy.HomeCopy.cardTitle(mac: $0) } ?? "Add a Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeSheet()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .tactileButton(.secondary, shape: .circle)
                    .accessibilityLabel("Cancel")
                }
            }
        }
    }

    // MARK: The footer

    /// The auto-reconnect switch, the site's links (as the connect screen's footer, App Review
    /// guidelines 1.5, 2.1 and 5.1.1(i)), and this app's version.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $autoReconnectEnabled) {
                Text("Reconnect automatically")
                    .font(.system(size: 14))
                    .foregroundStyle(TactileTokens.textPrimary)
            }
            .tint(TactileTokens.ledEmerald)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .tactileSurface(.recessedHardware, shape: .rounded(14))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    links
                    Spacer(minLength: 12)
                    version
                }
                VStack(alignment: .leading, spacing: 8) {
                    links
                    version.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.footnote)
            .foregroundStyle(TactileTokens.textSecondary)
        }
        .padding(.top, 8)
    }

    private var links: some View {
        HStack(spacing: 0) {
            footerLink("Get it at \(SillLinks.siteName)", to: SillLinks.download)
            linkSeparator
            footerLink("Support", to: SillLinks.support)
            linkSeparator
            footerLink("Privacy Policy", to: SillLinks.privacy)
        }
    }

    private var linkSeparator: some View {
        Text(" · ")
            .foregroundStyle(TactileTokens.textSecondary)
            .accessibilityHidden(true)
    }

    private func footerLink(_ title: LocalizedStringKey, to url: URL) -> some View {
        Link(destination: url) {
            Text(title)
                .foregroundStyle(TactileTokens.ledCyan)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .padding(.vertical, -14)
    }

    @ViewBuilder private var version: some View {
        if let label = VersionLabel.shown {
            VersionLine(label: label)
                .accessibilitySortPriority(-1)
        }
    }

    // MARK: The auto-reconnect countdown

    /// On appear, and whenever the list of Macs changes: the switch is on, this screen allows it,
    /// nobody cancelled, and the Mac last tapped shows reachable — start the pill's countdown. It
    /// fires once; a miss (the Mac gone again) does not start it over.
    private func maybeReconnect() {
        guard autoReconnectEnabled, !suppressAutoReconnectOnAppear, !reconnectSuppressed,
              reconnectMac == nil, reconnectTask == nil, !lastConnectedMacID.isEmpty,
              let mac = client.macs.first(where: { $0.savedID == lastConnectedMacID && routeLED($0).lit })
        else { return }
        TactileHaptics.play(.detent)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.1)) {
            reconnectMac = mac
        }
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(for: Self.reconnectWait)
            guard !Task.isCancelled else { return }
            reconnectTask = nil
            reconnectSuppressed = true
            if let mac = reconnectMac {
                withAnimation(.easeOut(duration: 0.15)) { reconnectMac = nil }
                connect(mac)
            }
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectSuppressed = true
        TactileHaptics.play(.detent)
        withAnimation(.easeOut(duration: 0.15)) { reconnectMac = nil }
    }

    /// The floating pill the countdown shows: "Reconnecting to Mac mini…" and Cancel, on floating
    /// chrome above the grid's bottom edge.
    @ViewBuilder private var reconnectPill: some View {
        if let mac = reconnectMac {
            HStack(spacing: 12) {
                TactileLED(isOn: true, color: TactileTokens.ledCyan)
                Text("Reconnecting to \(mac.name)…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TactileTokens.textPrimary)
                    .lineLimit(1)
                Button("Cancel", action: cancelReconnect)
                    .tactileButton(.secondary, shape: .capsule)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .tactileSurface(.floatingChrome, shape: .capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }
}
