import SwiftUI
import StreamProtocol

/// The clipboard's chip over the stream (docs/clipboard-plan.md): "Paste on ‹Mac›", where the text goes
/// with Paste on ‹Mac› Right Away on ("Where the cursor is.": the Paste presses ⌘V there too),
/// else "Then press ⌘V there.", with the system's Paste button and Dismiss; for a moment after a Paste,
/// its note in the same place. Offered by StreamClient (`clipboardChip`, ClipboardPolicy.offersChip);
/// placed and hidden by StreamScreen. Takes no touch outside itself.
struct ClipboardChip: View {
    @ObservedObject var client: StreamClient
    /// Paste on ‹Mac› Right Away (StreamClient.pasteRightAwayOn), for the words.
    @AppStorage(StreamClient.pasteRightAwayKey) private var pasteRightAway = true

    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let note = client.clipboardNote {
                noteView(note)
                    .transition(.opacity)
            } else if client.clipboardChip {
                chip
                    .transition(.opacity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.easeOut(duration: 0.2), value: client.clipboardChip)
        .animation(.easeOut(duration: 0.2), value: client.clipboardNote)
    }

    private var chip: some View {
        TactileGlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                ClipboardPasteButton(client: client)
                    .controlSize(.small)
                    .accessibilityLabel(ClipboardPolicy.Copy.chipSpoken(mac: mac, device: StreamClient.deviceWord, rightAway: pasteRightAway))

                dismissButton
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var dismissButton: some View {
        let button = Button {
            client.dismissClipboardChip()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
        }
        .accessibilityLabel(ClipboardPolicy.Copy.dismiss)

        if #available(iOS 26, *) {
            button
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            button
                .tactileButton(.secondary, shape: .circle)
        }
    }

    private func noteView(_ note: ClipboardNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: note.warning ? "exclamationmark.triangle" : "checkmark")
                .foregroundStyle(note.warning ? TactileTokens.ledAmber : TactileTokens.ledCyan)
                .accessibilityHidden(true)
            Text(note.text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(ClipboardGlassSurface())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.spoken)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct ClipboardGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.tactileSurface(.floatingChrome, shape: .capsule)
        }
    }
}

/// The system's Paste button (SwiftUI's PasteButton, UIPasteControl): the person's tap reads this
/// device's clipboard without iOS asking, and what it read goes to the Mac (`sendClipboard`), pasted
/// there once the Mac has it while Paste on ‹Mac› Right Away is on. Disabled by the system while the
/// clipboard has no text. Its label is the system's ("Paste").
struct ClipboardPasteButton: View {
    @ObservedObject var client: StreamClient
    var iconOnly: Bool = false
    var tint: Color = Palette.accent
    @AppStorage(StreamClient.pasteRightAwayKey) private var pasteRightAway = true

    var body: some View {
        let base = PasteButton(payloadType: String.self) { strings in
            DispatchQueue.main.async { client.sendClipboard(strings) }
        }
        .buttonBorderShape(.capsule)
        .tint(tint)
        .accessibilityHint(ClipboardPolicy.Copy.pasteHint(mac: client.macName.isEmpty ? "the Mac" : client.macName,
                                                          device: StreamClient.deviceWord, rightAway: pasteRightAway))

        if iconOnly {
            base.labelStyle(.iconOnly)
        } else {
            base.labelStyle(.titleAndIcon)
        }
    }
}
