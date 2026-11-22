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
        TactileGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ClipboardPolicy.Copy.chipTitle(mac: mac))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(ClipboardPolicy.Copy.chipSubtitle(rightAway: pasteRightAway))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(-1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ClipboardPolicy.Copy.chipSpoken(mac: mac, device: StreamClient.deviceWord, rightAway: pasteRightAway))
                    .accessibilityAddTraits(.isStaticText)

                    ClipboardPasteButton(client: client)
                        .controlSize(.small)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .modifier(ClipboardGlassSurface())

                dismissButton
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var dismissButton: some View {
        let button = Button(action: { client.dismissClipboardChip() }) {
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
    @AppStorage(StreamClient.pasteRightAwayKey) private var pasteRightAway = true

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            // On the main thread whatever queue the system hands it on.
            DispatchQueue.main.async { client.sendClipboard(strings) }
        }
        .buttonBorderShape(.capsule)
        .labelStyle(.titleAndIcon)
        .tint(Palette.accent)
        .accessibilityHint(ClipboardPolicy.Copy.pasteHint(mac: client.macName.isEmpty ? "the Mac" : client.macName,
                                                          device: StreamClient.deviceWord, rightAway: pasteRightAway))
    }
}
