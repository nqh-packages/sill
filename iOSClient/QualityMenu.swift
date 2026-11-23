import Foundation
// In the app StreamProtocol is its own module; the away-copy check compiles this file together with
// Sources/StreamProtocol/HostSettings.swift as one module, where there is nothing to import.
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// Quality's menu as both pickers build it (HostSettingsPanel and ControlCenterSheet): one pure
/// description, so Auto (docs/adaptive-quality-plan.md) is added once. Checked with swiftc
/// (Tests/checks/away-copy).
enum QualityMenu {
    enum Pick: Hashable {
        case auto
        case rate(Int)
    }

    struct Item: Equatable {
        let pick: Pick
        /// "Auto", "Extreme — 150 Mbps", "Custom — 12 Mbps" (shown, never offered).
        let title: String
        let offered: Bool
    }

    /// Auto first, only from a Mac whose state says `autoQuality` (non-nil; ledger rule 9); then the
    /// presets; then a hand-set rate, shown and never offered.
    static func items(_ s: StreamSettings) -> [Item] {
        var out: [Item] = []
        if s.autoQuality != nil { out.append(Item(pick: .auto, title: "Auto", offered: true)) }
        out += QualityPreset.allCases.map { Item(pick: .rate($0.rawValue), title: $0.title, offered: true) }
        if s.autoQuality != true, QualityPreset(rawValue: s.bitrate) == nil {
            out.append(Item(pick: .rate(s.bitrate), title: QualityPreset.title(forBitrate: s.bitrate), offered: false))
        }
        return out
    }

    /// `.auto` while `autoQuality` is true, else the rate.
    static func selection(_ s: StreamSettings) -> Pick {
        s.autoQuality == true ? .auto : .rate(s.bitrate)
    }

    /// The row's value: "Auto" (silent about the rung), or the preset's name.
    static func label(_ s: StreamSettings) -> String {
        s.autoQuality == true ? "Auto" : QualityPreset.name(forBitrate: s.bitrate)
    }

    /// What a pick sends. A preset from a Mac that says `autoQuality` also says `false`, so the pick
    /// fixes the rate even when it is the preset Auto happens to run at; a Mac that does not say it
    /// gets the bitrate alone. Both name the ledger's one `.bitrate` field, so either replaces the other.
    static func change(_ p: Pick, in s: StreamSettings) -> HostSettingsChange {
        switch p {
        case .auto: HostSettingsChange(autoQuality: true)
        case .rate(let r): HostSettingsChange(bitrate: r, autoQuality: s.autoQuality == nil ? nil : false)
        }
    }
}
