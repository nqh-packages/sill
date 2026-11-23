import CoreGraphics
import StreamProtocol

/// Away from home (docs/remote-bundle-plan.md §5), the host's rules on their own: who counts as away,
/// when the away quality is the target, and the two lines that say so. The coordinator keeps the
/// state (`awayWanted`, `awayRunning`) and the restarts; everything it decides from is here. Pure
/// (StreamProtocol, OriginPolicy's `Origin` and HostConfig), checked with swiftc
/// (Tests/checks/away-quality).
enum AwayPolicy {
    /// A device is away when the remote door admitted it from a VPN, from the internet or through a
    /// relay on this Mac ("through Tailscale", "through your VPN", "over the internet", "through a
    /// relay on this Mac"). A relay (a userspace Tailscale or WireGuard node, an SSH tunnel, a proxy)
    /// hands the door every device from this Mac's own address, wherever the device is, so it counts
    /// as a VPN does: away, until the device comes home and moves to the home door (issue #326,
    /// docs/away-through-relay-plan.md). The remote door from this Mac's own networks ("by address")
    /// is at home, since a device that dials the Mac's LAN address is in the house, and so is every
    /// connection through the home door.
    static func isAway(remoteDoor: Bool, origin: OriginPolicy.Origin) -> Bool {
        remoteDoor && (origin == .vpn || origin == .internet || origin == .relay)
    }

    /// Whether the away quality is the target: while at least one device is connected and every
    /// connected device is away; any device at home brings the home quality back. With no device
    /// connected the flag keeps its last value (`current`): nothing streams then, and the next
    /// device to register decides, before its catalog goes out.
    static func wanted(devicesAway: [Bool], current: Bool) -> Bool {
        devicesAway.isEmpty ? current : devicesAway.allSatisfy { $0 }
    }

    /// The line when the away quality becomes the target: "Away from home: every connected device is
    /// away; streaming at Low · Standard (4 Mbps per 60 fps, points). The home quality stays Pro ·
    /// Retina."
    static func awayLine(_ c: HostConfig) -> String {
        let streaming: String
        switch c.awayBitrate {
        case .auto: streaming = "Auto (starting at Low · Standard, climbing while the link keeps up)"
        case .fixed(let b): streaming = "\(title(b, c.awayCaptureScale)) (\(HostConfig.mbps(b)) Mbps per 60 fps, \(scaleWord(c.awayCaptureScale)))"
        }
        return "Away from home: every connected device is away; streaming at \(streaming). "
            + "The home quality stays \(name(c.bitrate, c.captureScale))."
    }

    /// The line when a device at home brings the home quality back: "Home quality again: a device
    /// connected at home (fe80::1c2d:3e4f:5a6b:7c8d%en0.51447); streaming at Pro · Retina." Under Auto:
    /// "streaming at Auto."
    static func homeLine(_ c: HostConfig, endpoint: String) -> String {
        "Home quality again: a device connected at home (\(endpoint)); streaming at \(name(c.bitrate, c.captureScale))."
    }

    /// "Auto", or "Pro · Retina" for a rate a pick fixed.
    static func name(_ choice: BitrateChoice, _ captureScale: CGFloat) -> String {
        switch choice {
        case .auto: "Auto"
        case .fixed(let bitrate): title(bitrate, captureScale)
        }
    }

    /// "Low · Standard", from the host's knobs.
    static func title(_ bitrate: Int, _ captureScale: CGFloat) -> String {
        QualityPreset.shortTitle(bitrate: bitrate, captureScale: Double(captureScale))
    }

    /// The word `HostConfig.changes(to:)` uses for a capture scale.
    static func scaleWord(_ captureScale: CGFloat) -> String { captureScale >= 1.5 ? "Retina" : "points" }
}
