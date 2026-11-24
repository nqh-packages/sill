import SwiftUI
import UIKit
import StreamProtocol

/// The Control Center sheet (the tactile workspace's `WorkspaceModal.controlCenter`): the Settings
/// panel's reach condensed for the dock and the capsule. Two tiers — a machined control deck of the
/// four or five things a hand reaches for (Mute, Paste, the Mac's menus, Picture in Picture, then
/// the Aa detent track and the live link pill), over the panel's own grouped settings rows with the
/// same `HostSettingsChange` calls and `@AppStorage` keys, so nothing here behaves differently from
/// `HostSettingsPanel`.
///
/// The sheet keeps the panel's rules where they matter: controls read `client.settings.displayed`
/// (the Mac's last word with this device's picks laid over it) and send one field a touch through
/// `client.changeSettings`; refused or timed-out picks come back through the same ledger, and
/// `settingsRefusals` still warns. What it does not copy is the panel's bespoke Rows/Footnote
/// chrome — the deck and the sections are native grouped `Form` with tactile tiles, since nothing
/// tactile scrolls that isn't solid (`recessedHardware`: no Liquid Glass inside anything that
/// scrolls).
///
/// `route` is the workspace's own: `.macMenus` swaps the root for `MacMenusDrillInView` (the Mac's
/// menus drilled into, menu by menu, fetched on open — `StreamClient.fetchTopMenu`/`fetchMenu`,
/// the same lazy fetches the iPad's menu bar and `MacMenuTrigger` make).
struct ControlCenterSheet: View {
    @ObservedObject var client: StreamClient
    @Binding var textScale: Double?
    @Binding var route: WorkspaceModal.ControlCenterRoute
    /// Full Screen's row as the stream screen computes it (`HostSettingsPanel.FullScreenRow`); its
    /// row shows only while a hide can start (`offered`).
    let fullScreenRow: HostSettingsPanel.FullScreenRow?
    /// The Aa dial's commit: the parent re-sends the viewport, as `StreamScreen`'s `onChange(of:
    /// textScale)` does for the bar's ruler.
    let onTextScaleCommit: () -> Void
    /// Pair This iPad…'s row: the parent opens the pairing overlay (`WorkspaceModal.pairingOverlay`).
    let onPairThisDevice: () -> Void
    /// Take the Tour's row: the parent opens the tour (`WorkspaceModal.tour`).
    let onTakeTour: () -> Void
    let dismiss: () -> Void

    /// These five are the panel's own keys (HostSettingsPanel): the values StreamClient+Clipboard,
    /// the input view, PictureInPictureHub and StreamClient.sendGesture read. Never sent.
    @AppStorage(StreamClient.clipboardKey) private var clipboardOn = true
    @AppStorage(StreamClient.pasteRightAwayKey) private var pasteRightAway = true
    @AppStorage(StreamClient.reverseScrollKey) private var reverseScroll = false
    @AppStorage(StreamClient.gesturesKey) private var gesturesOn = true
    @AppStorage(StreamClient.pictureInPictureKey) private var pictureInPicture = PictureInPicturePolicy.defaultOn

    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }
    private var device: String { DuoLayout.phoneArrangement ? "iPhone" : "iPad" }

    var body: some View {
        NavigationStack {
            Group {
                if route == .macMenus {
                    MacMenusDrillInView(client: client, onItemChosen: dismiss)
                } else {
                    root
                }
            }
            .navigationTitle(route == .macMenus ? (client.menus.top.app ?? "Menus") : mac)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if route == .macMenus {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { route = .root } label: {
                            Label("Controls", systemImage: "chevron.left")
                        }
                    }
                } else if #available(iOS 26, *) {
                    ToolbarItem(placement: .principal) { principal }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) { principal }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .presentationCornerRadius(28)
        // A refused or timed-out pick goes back to the Mac's value, as the panel's does; the
        // warning lands with it (HostSettingsPanel).
        .sensoryFeedback(.warning, trigger: client.settingsRefusals)
        .onChange(of: pictureInPicture) { _, _ in
            client.noteAction()
            PictureInPictureHub.shared.update()
        }
    }

    /// The bar's centre: the Mac's name over the live readout ("2560×1440 · 60 fps · 15 Mbps ·
    /// Wi-Fi"; from afar, the remote route), amber while the link cannot keep up.
    private var principal: some View {
        VStack(spacing: 1) {
            Text(mac)
                .font(.headline)
                .lineLimit(1)
            Text(linkBadge)
                .font(.caption2)
                .foregroundStyle(linkWarning ? TactileTokens.ledAmber : TactileTokens.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mac)
        .accessibilityValue(HostSettingsPanel.spokenReadout(client.settings.host?.stream,
                                                            route: client.route,
                                                            remote: client.remoteRoute,
                                                            rttMs: client.linkStats?.rtt?.median))
    }

    /// What actually runs and how this device reaches the Mac, one line: the panel's own readout
    /// (HostSettingsPanel.readout) plus the remote route's phrase from afar.
    private var linkBadge: String {
        var text = HostSettingsPanel.readout(client.settings.host?.stream, route: client.route)
        if let remote = client.remoteRoute { text += " · Connected \(remote.phrase)" }
        return text
    }

    /// The warning tint's rule: this connection's link cannot keep up, or the Mac says so.
    private var linkWarning: Bool { client.slowLink || client.settings.host?.link != nil }

    // MARK: Tier 1 — the control deck

    private var root: some View {
        Form {
            Section {
                deck
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
            }
            streamingSection
            deviceSection
            if let info = client.macInfo { awaySection(info) }
            tourSection
            Section {
                Button(role: .destructive) {
                    client.disconnect()
                    dismiss()
                } label: {
                    Text("Disconnect from \(mac)")
                }
                .accessibilityHint("Ends this stream and returns to your Macs")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TactileTokens.canvasBlack)
    }

    /// The machined deck: Mute, Paste, Menus and Picture in Picture as anodized tiles, then the
    /// full-width Aa track and the link pill — solid `recessedHardware`, since the sheet scrolls.
    private var deck: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                if let row = fullScreenRow, row.offered { fullScreenTile(row) }
                if client.macHasSound { muteTile }
                if ClipboardPolicy.hostTakes(client.hostClipboard) { pasteTile }
                menusTile
                if PictureInPicture.supported { pipTile }
            }
            TextScaleDetentDial(scale: $textScale,
                                offered: client.textScaleOffersOff,
                                available: client.textScaleSelectable,
                                unavailableHint: client.textScaleUnavailableHint,
                                commit: onTextScaleCommit)
            linkPill
        }
    }

    /// Full Screen: hides status bar, Home indicator, and dock/capsule so only the Mac stream stays
    /// on screen; swipe in from the left edge or shake to return.
    private func fullScreenTile(_ row: HostSettingsPanel.FullScreenRow) -> some View {
        DeckTile(symbol: "arrow.up.left.and.arrow.down.right",
                 title: FullScreenPolicy.Copy.rowTitle,
                 enabled: row.coversScreen) {
            TactileHaptics.play(.detent)
            row.hide()
        }
        .accessibilityHint(FullScreenPolicy.Copy.rowHint)
    }

    /// Mute: this device's own (the panel's Mute row, `soundMuted`), an amber LED while silenced,
    /// emerald while the Mac's sound plays here.
    private var muteTile: some View {
        DeckTile(symbol: client.soundMuted ? "speaker.slash" : "speaker.wave.2",
                 title: client.soundMuted ? "Muted" : "Sound",
                 led: (isOn: true, color: client.soundMuted ? TactileTokens.ledAmber : TactileTokens.ledEmerald)) {
            TactileHaptics.play(.detent)
            client.setSoundMuted(!client.soundMuted)
        }
        .accessibilityLabel(client.soundMuted ? "Unmute sound from \(mac)" : "Mute sound from \(mac)")
    }

    private var pasteTile: some View {
        VStack(spacing: 5) {
            ClipboardPasteButton(client: client, iconOnly: true, tint: TactileTokens.controlRaised)
                .controlSize(.mini)
            Text("Paste")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TactileTokens.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 66)
        .tactileDeckTileSurface(shape: .rounded(14))
    }

    /// Menus: drills into the Mac's menus inside this sheet (`route = .macMenus`); dimmed while the
    /// Mac has none to show (an older host, or none yet).
    private var menusTile: some View {
        DeckTile(symbol: MacMenuButton.symbol, title: "Menus",
                 enabled: client.menus.hasMenus) {
            route = .macMenus
        }
    }

    /// Picture in Picture where iOS has it (the panel's switch): the LED follows the stored switch;
    /// the hub re-reads it on the change (the `onChange` on the NavigationStack above).
    private var pipTile: some View {
        DeckTile(symbol: "pip", title: PictureInPicturePolicy.Copy.title,
                 led: (isOn: pictureInPicture, color: TactileTokens.ledCyan)) {
            TactileHaptics.play(.detent)
            pictureInPicture.toggle()
        }
    }

    /// The deck's last piece: the live readout on a pill — route, fps, resolution — its LED amber
    /// while the link cannot keep up (the panel's slow-link warning made tactile).
    private var linkPill: some View {
        HStack(spacing: 9) {
            TactileLED(isOn: true, color: linkWarning ? TactileTokens.ledAmber : TactileTokens.ledEmerald)
            Text(linkBadge)
                .font(.caption.weight(.medium))
                .foregroundStyle(TactileTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(HostSettingsPanel.rttText(client.linkStats))
                .font(.caption)
                .foregroundStyle(TactileTokens.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .tactileSurface(.recessedHardware, shape: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Link and stream")
        .accessibilityValue(linkBadge + ", round trip " + HostSettingsPanel.rttText(client.linkStats))
    }

    // MARK: Tier 2 — the grouped settings

    /// Streaming: the panel's own controls — Quality, Resolution, Frame Rate, Prioritize Encoding
    /// Speed, Virtual Display, Send Audio — each sending only its field (`binding`), reading
    /// `client.settings.displayed`.
    private var streamingSection: some View {
        Section {
            if let shown = client.settings.displayed, let state = client.settings.host {
                if let problem = client.settingsProblem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                qualityPicker(shown)
                Picker("Resolution", selection: binding(shown.captureScale) { HostSettingsChange(captureScale: $0) }) {
                    Text("Retina").tag(2.0)
                    Text("Standard").tag(1.0)
                }
                .pickerStyle(.segmented)
                Picker("Frame Rate", selection: binding(shown.maxFPS) { HostSettingsChange(maxFPS: $0) }) {
                    Text("60 fps").tag(60)
                    Text("120 fps").tag(120)
                }
                .pickerStyle(.segmented)
                Toggle(isOn: binding(shown.prioritizeSpeed) { HostSettingsChange(prioritizeSpeed: $0) }) {
                    settingTitle("Prioritize Encoding Speed", field: .prioritizeSpeed)
                }
                Toggle(isOn: binding(shown.virtualDisplay) { HostSettingsChange(virtualDisplay: $0) }) {
                    settingTitle("Virtual Display", field: .virtualDisplay)
                }
                // Off and impossible on this host: disabled; on, it can always be turned off, as on
                // the Mac (HostSettingsPanel).
                .disabled(!state.virtualDisplayAvailable && !shown.virtualDisplay)
                .accessibilityHint(state.virtualDisplayNote ?? "")
                Toggle(isOn: binding(shown.sendAudio ?? false) { HostSettingsChange(sendAudio: $0) }) {
                    HStack(spacing: 8) {
                        Text("Send Audio")
                        betaTag
                        pendingSpinner(.sendAudio)
                    }
                }
                .disabled(shown.sendAudio == nil)
                .accessibilityLabel("Send Audio, beta")
                .accessibilityHint(shown.sendAudio == nil ? "Update Sill on \(mac) to use this." : "")
                if shown.sendAudio == true, let note = state.audioNote {
                    Text(note).font(.footnote).foregroundStyle(.orange)
                }
                if !state.persistent {
                    Text("SillHost keeps these until it quits.").font(.footnote)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading settings…")
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Streaming")
        } footer: {
            streamingFooter
        }
    }

    /// Quality's menu, as the panel builds it (HostSettingsPanel.qualityPicker): the presets with
    /// their rates, a hand-set bitrate shown but never offered, and from iOS 18 the row showing the
    /// name alone.
    @ViewBuilder private func qualityPicker(_ shown: StreamSettings) -> some View {
        let selection = binding(QualityMenu.selection(shown)) { QualityMenu.change($0, in: shown) }
        if #available(iOS 18.0, *) {
            Picker("Quality", selection: selection) {
                qualityChoices(shown)
            } currentValueLabel: {
                Text(QualityMenu.label(shown))
            }
            .pickerStyle(.menu)
        } else {
            Picker("Quality", selection: selection) { qualityChoices(shown) }
                .pickerStyle(.menu)
        }
    }

    @ViewBuilder private func qualityChoices(_ shown: StreamSettings) -> some View {
        ForEach(QualityMenu.items(shown), id: \.pick) { Text($0.title).tag($0.pick) }
    }

    /// Under Streaming: the panel's words for quality, then the virtual display's note or what it
    /// does, Send Audio's beta line, and away-from-home quality when the connection is one.
    @ViewBuilder private var streamingFooter: some View {
        let host = client.settings.host
        VStack(alignment: .leading, spacing: 4) {
            Text("Quality is per 60 fps; a 120 fps stream gets twice as much. " + QualityPreset.fastLinkNote)
            if let note = host?.virtualDisplayNote {
                Text(note).foregroundStyle(.orange)
            } else if client.settings.displayed?.virtualDisplay == true {
                Text("The window you pick moves onto an invisible display on \(mac) while it streams, so it keeps updating when covered. Applies to every device streaming from \(mac). The stream restarts for a moment.")
            }
            Text(HostSettingsPanel.sendAudioFooter(client.settings.displayed?.sendAudio,
                                                   muted: client.soundMuted, mac: mac, device: device))
            if let note = AwayCopy.footnote(host?.away, mac: mac,
                                          remoteAccessOn: client.macInfo?.remoteAccess == true) {
                Text(note)
            }
        }
    }

    /// This iPhone/iPad: Share Clipboard with Paste Right Away under it (while the Mac shares its
    /// clipboard), Reverse Scrolling, Three-Finger Gestures, and Full Screen while a hide can
    /// start. The switches send nothing; the clipboard's subscribes or stops
    /// (`clipboardSwitchChanged`).
    private var deviceSection: some View {
        Section {
            if ClipboardPolicy.hostTakes(client.hostClipboard) {
                Toggle(ClipboardPolicy.Copy.switchTitle, isOn: $clipboardOn)
                    .onChange(of: clipboardOn) { _, _ in client.clipboardSwitchChanged() }
                if clipboardOn {
                    Toggle(ClipboardPolicy.Copy.rightAwayTitle(mac: mac), isOn: $pasteRightAway)
                }
            }
            Toggle("Reverse Scrolling", isOn: $reverseScroll)
            Toggle("Three-Finger Gestures", isOn: $gesturesOn)
            if let row = fullScreenRow, row.offered {
                Button(action: row.hide) {
                    HStack {
                        Text(FullScreenPolicy.Copy.rowTitle)
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHint(FullScreenPolicy.Copy.rowHint)
            }
        } header: {
            Text("This \(device)")
        } footer: {
            deviceFooter
        }
    }

    @ViewBuilder private var deviceFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ClipboardPolicy.hostTakes(client.hostClipboard) {
                Text(ClipboardPolicy.Copy.footnote(on: clipboardOn, rightAway: pasteRightAway,
                                                   mac: mac, device: device))
            }
            Text(HostSettingsPanel.reverseScrollFooter(device: device))
            Text(gesturesFootnote)
            if let row = fullScreenRow, row.offered {
                Text(row.coversScreen ? FullScreenPolicy.Copy.footnote : FullScreenPolicy.Copy.notOffered)
            }
        }
    }

    /// Under Three-Finger Gestures: the panel's footnote cut to the parts its rows here still do
    /// (the panel's gesture rows stay on the full Settings sheet — `HostSettingsPanel`).
    private var gesturesFootnote: String {
        guard gesturesOn else { return "Three-finger strokes do nothing while this is off." }
        guard (client.hostGestures ?? 0) >= TrackpadGesture.generation else {
            return "Update Sill on \(mac) to use these."
        }
        return "Three fingers on the trackpad or over the stream."
    }

    /// Away from home (the panel's last group, DiscoveryPolicy.awayFromHome): "Paired" for a saved
    /// Mac with how it is reached from afar; Pair This iPad… where a pairing can start; how to turn
    /// Remote Access on where nothing can.
    @ViewBuilder private func awaySection(_ info: MacInfo) -> some View {
        let away = DiscoveryPolicy.awayFromHome(saved: client.macInfoSaved,
                                                remoteSession: client.remoteRoute != nil,
                                                remoteAccess: info.remoteAccess,
                                                tlsAtHome: client.sessionAtHomeOverTLS)
        switch away {
        case .paired(let reach):
            Section {
                Label("Paired", systemImage: "checkmark.circle.fill")
            } header: {
                Text("Away from home")
            } footer: {
                switch reach {
                case .connected:
                    if let r = client.remoteRoute { Text("Connected \(r.phrase).") }
                case .reaches:
                    Text("Away from home, Sill reaches \(mac) \(HostSettingsPanel.reach(info)).")
                case .turnOnRemoteAccess:
                    Text(HostSettingsPanel.turnOnRemoteAccess(mac))
                }
            }
        case .pairThisDevice(let atHome):
            Section {
                Button("Pair This \(device)…", action: onPairThisDevice)
            } header: {
                Text("Away from home")
            } footer: {
                Text(atHome ? DiscoveryPolicy.HomeCopy.pairThisDeviceAtHome(mac: mac, device: device)
                            : "Pair once to reach \(mac) through your VPN or the internet. \(mac) shows a code; scan it with this \(device).")
            }
        case .turnOnRemoteAccess:
            Section {
                Text(HostSettingsPanel.turnOnRemoteAccess(mac))
                    .font(.footnote)
            } header: {
                Text("Away from home")
            }
        }
    }

    /// Take the Tour (the panel's own row), before Disconnect.
    private var tourSection: some View {
        Section {
            Button(TourPolicy.takeTourTitle, action: onTakeTour)
                .accessibilityHint(TourPolicy.takeTourHint(device: device))
        } footer: {
            Text(TourPolicy.takeTourFootnote(device: device))
        }
    }

    // MARK: Small pieces

    /// A settings field's title with the pending spinner beside it while the Mac has not answered
    /// (`client.settings.pendingSince`, the panel's RowTitle).
    private func settingTitle(_ title: String, field: SettingsField) -> some View {
        HStack(spacing: 8) {
            Text(title)
            pendingSpinner(field)
        }
    }

    @ViewBuilder private func pendingSpinner(_ field: SettingsField) -> some View {
        if client.settings.pendingSince(field) != nil {
            ProgressView().controlSize(.small)
        }
    }

    /// Send Audio's beta tag, as the panel's (a small bordered "Beta" that reads as part of the row,
    /// and "Send Audio, beta" to VoiceOver through the label set on the row).
    private var betaTag: some View {
        Text("Beta")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary, lineWidth: 1))
            .accessibilityHidden(true)
    }

    /// Shows the value the panel displays; moving the control sends that one field
    /// (`client.changeSettings`) — HostSettingsPanel's own binding, unchanged.
    private func binding<V>(_ value: V, _ change: @escaping (V) -> HostSettingsChange) -> Binding<V> {
        Binding(get: { value }, set: { client.changeSettings(change($0)) })
    }
}

/// One machined deck tile: a round-cornered `recessedHardware` key (solid, never glass — the sheet
/// scrolls) with an unenclosed symbol, its LED where the thing has a state, title and detail.
private struct DeckTile: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    var led: (isOn: Bool, color: Color)? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                    if let led {
                        TactileLED(isOn: led.isOn, color: led.color)
                    }
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(TactileTokens.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(TactileTokens.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 66)
        }
        .tactileRecessedButton(.secondary, shape: .rounded(14))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// The Aa track (Tier 1's full-width piece): a machined groove with a tick at every `TextScale`
/// detent and a knob that snaps to them — the bar's `TextScaleControl` ruler laid flat. A drag or
/// tap moves the knob a detent a tick with the `.detent` haptic; letting go commits
/// (`TextScale.scale(at:)` on the binding, then `commit`, which re-sends the viewport). While the
/// Desktop streams (`available` false) it shows the hint and moves nothing, as the dimmed ruler
/// does.
private struct TextScaleDetentDial: View {
    @Binding var scale: Double?
    /// Whether the track has an Off detent (`client.textScaleOffersOff`).
    let offered: Bool
    /// Whether Aa can be used now (`client.textScaleSelectable`: a window streams, the Mac unlocked).
    let available: Bool
    /// What the disabled track says (`client.textScaleUnavailableHint`).
    let unavailableHint: String
    /// What follows a committed scale: the parent's viewport re-send.
    let commit: () -> Void

    /// The detent under the finger while a drag runs; nil when it rests on the committed scale.
    @State private var live: Double? = nil

    private var detents: [Double] { TextScale.detents(offered: offered) }
    private var position: Double { live ?? TextScale.position(of: scale, offered: offered) }
    private static let knob: CGFloat = 22

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Aa")
                    .font(.headline)
                    .foregroundStyle(TactileTokens.textPrimary)
                Text(TextScale.title(at: position))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TactileTokens.textSecondary)
                Spacer()
                if !available {
                    Text(unavailableHint)
                        .font(.caption2)
                        .foregroundStyle(TactileTokens.textSecondary)
                }
            }
            GeometryReader { geo in
                let usable = max(geo.size.width - Self.knob, 1)
                ZStack {
                    Capsule()
                        .fill(TactileTokens.trackpadWell)
                        .frame(height: 6)
                        .padding(.horizontal, Self.knob / 2)
                        .position(x: geo.size.width / 2, y: 22)
                    ForEach(Array(detents.enumerated()), id: \.offset) { i, detent in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(TactileTokens.textSecondary.opacity(detent == position ? 1 : 0.45))
                            .frame(width: 2, height: 10)
                            .position(x: Self.knob / 2 + CGFloat(i) * usable / CGFloat(max(detents.count - 1, 1)), y: 22)
                    }
                    Circle()
                        .fill(TactileTokens.keycapTop)
                        .frame(width: Self.knob, height: Self.knob)
                        .overlay(Circle().stroke(TactileTokens.specularRimTop, lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .position(x: Self.knob / 2 + CGFloat(indexOf(position)) * usable / CGFloat(max(detents.count - 1, 1)), y: 22)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard available else { return }
                            let fraction = min(1, max(0, (g.location.x - Self.knob / 2) / usable))
                            let i = min(detents.count - 1, max(0, Int((fraction * Double(detents.count - 1)).rounded())))
                            let detent = detents[i]
                            if detent != live {
                                TactileHaptics.play(.detent)
                                live = detent
                            }
                        }
                        .onEnded { _ in
                            guard available, let chosen = live else { return }
                            live = nil
                            if chosen != position {
                                scale = TextScale.scale(at: chosen)
                                commit()
                            }
                        }
                )
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .tactileSurface(.recessedHardware, shape: .rounded(16))
        .opacity(available ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text size")
        .accessibilityValue(TextScale.spoken(at: position))
        .accessibilityHint(available ? "" : unavailableHint)
        .accessibilityAdjustableAction { direction in
            guard available else { return }
            switch direction {
            case .increment:
                scale = TextScale.scale(at: TextScale.step(from: position, up: true, offered: offered))
                commit()
            case .decrement:
                scale = TextScale.scale(at: TextScale.step(from: position, up: false, offered: offered))
                commit()
            @unknown default: break
            }
        }
    }

    /// The detent index nearest the live or committed position (a position between detents, while
    /// `live` moves, already is one).
    private func indexOf(_ value: Double) -> Int {
        if let exact = detents.firstIndex(of: value) { return exact }
        var nearest = 0
        var distance = Double.greatestFiniteMagnitude
        for (i, d) in detents.enumerated() where abs(d - value) < distance {
            distance = abs(d - value)
            nearest = i
        }
        return nearest
    }
}

/// The Mac's menus drilled into (Control Center's `.macMenus` route): the top level as native
/// rows, each menu fetched when opened — the top level through `client.fetchTopMenu` (which asks
/// by title when the tree moved, `MacMenuState` rule 11), a submenu through `client.fetchMenu` —
/// a spinner while it answers, its `.message` rows as words, and a `.item` pressed with
/// `client.pressMenuItem` and the sheet closed (`onItemChosen`).
///
/// Drilling keeps its own small stack rather than pushing NavigationLinks: `MacMenuState.Row` is
/// Equatable, not Hashable, and the rows a deeper level holds arrive only after their fetch —
/// the same lazy flow `MacMenuTrigger` drives for UIKit.
struct MacMenusDrillInView: View {
    @ObservedObject var client: StreamClient
    /// Choosing a menu item: the sheet closes (the Mac shows what the item did).
    let onItemChosen: () -> Void

    /// The menus drilled into, deepest last; empty is the top level itself.
    @State private var stack: [Level] = []

    /// One opened menu: the row that opened it, how it is fetched, and what the Mac answered (nil
    /// while the fetch waits).
    private struct Level: Equatable {
        enum Fetch: Equatable { case topMenu, submenu }
        let row: MacMenuState.Row
        let fetch: Fetch
        var content: MacMenuState.Content?
    }

    var body: some View {
        List {
            if let level = stack.last {
                levelRows(level)
            } else {
                topRows
            }
        }
        .listStyle(.plain)
    }

    /// The top level: the Mac's menus in its order, each a drill-in row, plus its note when the
    /// Mac sends one (Accessibility off on the Mac, the app not answering).
    @ViewBuilder private var topRows: some View {
        if let note = client.menus.top.note {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if client.menus.top.menus.isEmpty && client.menus.top.note == nil {
            Text("No menus")
                .foregroundStyle(.secondary)
        }
        ForEach(Array(client.menus.top.menus.enumerated()), id: \.offset) { _, row in
            Button { push(row, .topMenu) } label: {
                menuRow(row, chevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.enabled)
        }
    }

    /// One drilled level: a back row titled for where it returns, then the menu's own sections as
    /// the Mac sent them (`.sections` carries "‹n› more on the Mac" and "No items" itself,
    /// MacMenuState rule 10), the fetch's spinner meanwhile, or the fetch's words.
    @ViewBuilder private func levelRows(_ level: Level) -> some View {
        Section {
            Button { _ = stack.popLast() } label: {
                Label(stack.count > 1 ? stack[stack.count - 2].row.title : "Menus",
                      systemImage: "chevron.left")
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text(level.row.title)
        }
        if let content = level.content {
            switch content {
            case .message(let text):
                Section {
                    Text(text).foregroundStyle(.secondary)
                }
            case .sections(let sections, _):
                ForEach(Array(sections.enumerated()), id: \.offset) { _, rows in
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            itemRow(row)
                        }
                    }
                }
            }
        } else {
            Section {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Opening…")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    /// One row of a fetched menu: an item sends its choice and closes; a submenu drills again; a
    /// note only shows.
    @ViewBuilder private func itemRow(_ row: MacMenuState.Row) -> some View {
        switch row.kind {
        case .item:
            Button {
                client.pressMenuItem(row)
                onItemChosen()
            } label: {
                menuRow(row, chevron: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.enabled)
        case .submenu:
            Button { push(row, .submenu) } label: {
                menuRow(row, chevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.enabled)
        case .note:
            menuRow(row, chevron: false)
                .foregroundStyle(.secondary)
        }
    }

    /// A menu row as the Mac drew it: its mark in a fixed slot (check on, dash mixed), title, the
    /// shortcut as trailing grey text, a chevron where it drills.
    private func menuRow(_ row: MacMenuState.Row, chevron: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.mark == .mixed ? "minus" : "checkmark")
                .font(.caption.weight(.semibold))
                .opacity(row.mark == .off ? 0 : 1)
                .frame(width: 14)
            Text(row.title)
                .foregroundStyle(row.enabled ? Color.primary : Color.secondary)
            Spacer(minLength: 12)
            if let key = row.key {
                Text(key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Opens a menu's level and asks the Mac for it at once, the answer landing on the level still
    /// on the stack (a popped level's answer falls away, as a menu closed while it fetched).
    private func push(_ row: MacMenuState.Row, _ fetch: Level.Fetch) {
        stack.append(Level(row: row, fetch: fetch, content: nil))
        let index = stack.count - 1
        let level = stack[index]
        let done: (MacMenuState.Content) -> Void = { content in
            guard stack.indices.contains(index), stack[index].row == level.row else { return }
            stack[index].content = content
        }
        switch fetch {
        case .topMenu:
            client.fetchTopMenu(id: row.id ?? "", title: row.title,
                                builtVersion: row.version ?? client.menus.top.version ?? 0,
                                completion: done)
        case .submenu:
            client.fetchMenu(row, completion: done)
        }
    }
}
