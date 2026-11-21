import SwiftUI
import UIKit
import StreamProtocol

/// The one switcher (the tactile workspace's `WorkspaceModal.switcher`): a sheet that replaces the
/// old phone window bar and the iPad's apps card with a single searchable surface — the pinned
/// Desktop, the Mac's windows as live thumbnails in the Mac's own order, and below them every app
/// the Mac offers as a plain list of rows.
///
/// The look inside a `ScrollView` is solid machined hardware (`TactileSurfaceRole.recessedHardware`)
/// on purpose: Liquid Glass belongs on the fixed chrome — the dock, the capsule — never inside
/// anything that scrolls. The app rows stay rows, not an icon grid: Sill launches a window for a
/// tap and no more, and a launcher grid is the one thing App Store 4.2.7 reads as a second system.
///
/// Every window the sheet shows is live on the Mac already (`client.orderedWindows`), so picking
/// one only asks for it (`client.select`); an app the Mac knows but has no window for is launched
/// (`client.launch(bundleID:)`). `initialSearch` opens the field with the keyboard up (the
/// capsule's Apps key), a tap on the dock's chip without it.
struct UnifiedSwitcherSheet: View {
    @ObservedObject var client: StreamClient
    let initialSearch: Bool
    let dismiss: () -> Void

    @State private var query = ""
    /// The search field's focus, so the Apps key's sheet can open with the keyboard up; iOS 18 and
    /// later honour `searchable(isPresented:)`, iPadOS 17 simply shows the field.
    @State private var searchPresented = false

    private static let searchPrompt = "Search windows & Mac apps"

    var body: some View {
        NavigationStack {
            if #available(iOS 18.0, *) {
                content
                    .searchable(text: $query, isPresented: $searchPresented, prompt: Self.searchPrompt)
            } else {
                content
                    .searchable(text: $query, prompt: Self.searchPrompt)
            }
        }
        .onAppear { if initialSearch { searchPresented = true } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if desktopShown { desktopCard }
                if !windows.isEmpty { windowsGrid }
                if !apps.isEmpty { appsList }
                if nothingShown { nothingFound }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(TactileTokens.canvasBlack)
        .navigationTitle(client.macName.isEmpty ? "Windows & Apps" : client.macName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: What the query leaves

    /// The query, trimmed; a sheet with none shows everything.
    private var needle: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var desktopShown: Bool {
        needle.isEmpty || "desktop".contains(needle) ||
            (client.hostDesktopDisplayNames ?? []).contains { $0.lowercased().contains(needle) }
    }

    private var windows: [WindowInfo] {
        let all = client.orderedWindows
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(needle) ||
            $0.appName.lowercased().contains(needle) ||
            $0.bundleID.lowercased().contains(needle)
        }
    }

    private var apps: [AppInfo] {
        let all = client.apps
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(needle) || $0.bundleID.lowercased().contains(needle)
        }
    }

    private var nothingShown: Bool { !desktopShown && windows.isEmpty && apps.isEmpty }

    // MARK: The Desktop card

    /// The pinned card: a machined display bezel — the dark screen, its LED — labelled with the
    /// Desktop button's own words ("Desktop", "Desktop 2", "All Displays" while all stream), and
    /// the displays' names under a Mac of more than one.
    private var desktopCard: some View {
        Button {
            TactileHaptics.play(.tick)
            client.tapDesktop()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TactileTokens.chassisDark)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(TactileTokens.canvasBlack)
                        .padding(7)
                    Image(systemName: "display")
                        .font(.system(size: 34, weight: .thin))
                        .foregroundStyle(TactileTokens.textSecondary)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            TactileLED(isOn: client.active == .desktop, color: TactileTokens.ledEmerald)
                                .padding(6)
                        }
                    }
                }
                .frame(height: 108)
                HStack(spacing: 8) {
                    Text(client.desktopButton.label)
                        .font(.headline)
                        .foregroundStyle(TactileTokens.textPrimary)
                    if let names = client.hostDesktopDisplayNames,
                       (client.hostDesktopDisplays ?? 0) > 1, !names.isEmpty {
                        Text(names.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(TactileTokens.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if client.active == .desktop {
                        Text("Streaming")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TactileTokens.ledEmerald)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
        .tactileSurface(.recessedHardware, shape: .rounded(14))
        .accessibilityLabel(client.desktopButton.accessibilityLabel)
        .accessibilityValue(client.desktopButton.accessibilityValue ?? "")
        .accessibilityHint(client.desktopButton.accessibilityHint ?? "")
    }

    // MARK: The window cards

    /// The Mac's windows, front to back, each card its live thumbnail over a machined frame, its
    /// app's icon and the window's title; the one streaming carries the blue rim. A long press is
    /// the window's traffic lights: Close, Minimize, Full Screen.
    private var windowsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Windows")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(windows, id: \.id) { w in
                    windowCard(w)
                }
            }
        }
    }

    private func windowCard(_ w: WindowInfo) -> some View {
        Button {
            TactileHaptics.play(.tick)
            client.select(.window(w.id))
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(TactileTokens.canvasBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .overlay {
                        if let thumb = client.thumbnails[w.id] {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        } else {
                            Image(systemName: "macwindow")
                                .font(.system(size: 28, weight: .thin))
                                .foregroundStyle(TactileTokens.textSecondary.opacity(0.5))
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let icon = client.icons[w.bundleID] {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                                .padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(TactileTokens.specularRimTop.opacity(0.45), lineWidth: 0.5)
                    )
                Text(w.title.isEmpty ? w.appName : w.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TactileTokens.textPrimary)
                    .lineLimit(1)
                Text(w.appName)
                    .font(.caption2)
                    .foregroundStyle(TactileTokens.textSecondary)
                    .lineLimit(1)
            }
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .tactileSurface(.recessedHardware, shape: .rounded(14))
        .overlay {
            if client.active == .window(w.id) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TactileTokens.ledBlue, lineWidth: 2)
                    .shadow(color: TactileTokens.ledBlue.opacity(0.55), radius: 6)
            }
        }
        .contextMenu {
            Button { client.command(.close, window: w.id) } label: {
                Label("Close", systemImage: "xmark")
            }
            Button { client.command(.minimize, window: w.id) } label: {
                Label("Minimize", systemImage: "minus")
            }
            Button { client.command(.fullScreen, window: w.id) } label: {
                Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }
    }

    // MARK: The app rows

    /// Every app the Mac offers, a row each — icon and name — in a recessed tray. A tap asks the
    /// Mac to launch or front it (`client.launch`): one window at a time, never a launcher.
    private var appsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Apps on \(client.macName.isEmpty ? "Mac" : client.macName)")
            VStack(spacing: 0) {
                ForEach(Array(apps.indices), id: \.self) { index in
                    let app = apps[index]
                    Button {
                        client.launch(bundleID: app.bundleID)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = client.icons[app.bundleID] {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(TactileTokens.chassisRaised)
                                    .frame(width: 30, height: 30)
                            }
                            Text(app.name)
                                .font(.body)
                                .foregroundStyle(TactileTokens.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TactileTokens.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index + 1 < apps.count {
                        Divider()
                            .overlay(TactileTokens.chassisRaised)
                            .padding(.leading, 56)
                    }
                }
            }
            .tactileSurface(.recessedHardware, shape: .rounded(14))
        }
    }

    // MARK: Odds and ends

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TactileTokens.textSecondary)
            .textCase(nil)
            .padding(.leading, 4)
    }

    private var nothingFound: some View {
        HStack {
            Spacer()
            Text("No windows or apps match “\(query.trimmingCharacters(in: .whitespaces))”")
                .font(.callout)
                .foregroundStyle(TactileTokens.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.top, 30)
    }
}
