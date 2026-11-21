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
                TactileDisplayBezel(
                    image: nil,
                    placeholderSymbol: "display",
                    placeholderSize: 34,
                    height: 108,
                    outerRadius: TactileRadius.card,
                    innerRadius: TactileRadius.screen,
                    bezelPadding: 7,
                    led: (isOn: client.active == .desktop, color: TactileTokens.ledEmerald)
                )
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
        .tactileSurface(.recessedHardware, shape: .rounded(TactileRadius.card))
        .accessibilityLabel(client.desktopButton.accessibilityLabel)
        .accessibilityValue(client.desktopButton.accessibilityValue ?? "")
        .accessibilityHint(client.desktopButton.accessibilityHint ?? "")
    }

    // MARK: The window cards

    private var windowsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            TactileSectionHeader("Windows")
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
                TactileDisplayBezel(
                    image: client.thumbnails[w.id],
                    placeholderSymbol: "macwindow",
                    placeholderSize: 28,
                    height: 100,
                    innerRadius: TactileRadius.screen,
                    cornerIcon: client.icons[w.bundleID]
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
            .contentShape(RoundedRectangle(cornerRadius: TactileRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .tactileSurface(.recessedHardware, shape: .rounded(TactileRadius.card))
        .tactileSelectionRim(client.active == .window(w.id), shape: .rounded(TactileRadius.card))
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

    private var appsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            TactileSectionHeader("Apps on \(client.macName.isEmpty ? "Mac" : client.macName)")
            VStack(spacing: 0) {
                ForEach(Array(apps.indices), id: \.self) { index in
                    let app = apps[index]
                    Button {
                        client.launch(bundleID: app.bundleID)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            TactileAppIcon(image: client.icons[app.bundleID], size: 30, cornerRadius: TactileRadius.icon)
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
            .tactileSurface(.recessedHardware, shape: .rounded(TactileRadius.card))
        }
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
