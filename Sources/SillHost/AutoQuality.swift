import Foundation
import StreamProtocol

/// Auto (docs/adaptive-quality-plan.md): the rung the Mac's one encoder runs at, decided once a second
/// from what the host did for each device that governs it. Pure (Foundation, StreamProtocol's
/// QualityPreset and LinkJudge's rules), checked with swiftc (Tests/checks/auto-quality).
///
/// It owns three things and nothing else: the ladder, the rung it wants, and each device's window of
/// seconds since the running rung last changed. It never reads LinkJudge's state (which is reset and
/// hidden on every bitrate change, `judgedAfresh`, `settingsState`): it shares LinkJudge's *rules*
/// (`isShort`, the 3-of-5 and 5-clean timing, the carried rate, `suggestion`) and keeps its own
/// windows, so its own steps can never blind it.
///
/// Invariants:
/// - `rung` is always on `ladder`; the ladder's top is Extreme (decision 3), its bottom Low · Standard.
/// - A step is returned only while the pipeline runs `rung` (`running == rung`): a restart still
///   pending is never judged on, so `close` is idempotent across a pending restart.
/// - Every window is cleared when the running rung changes, whoever changed it: the seconds a rung is
///   judged on were all spent at that rung.
struct AutoQuality: Equatable {
    /// A point on the ladder: a preset's bitrate (per 60 fps) and Retina or Standard.
    struct Rung: Hashable, Comparable {
        let preset: QualityPreset
        let retina: Bool
        var bitrate: Int { preset.rawValue }
        var captureScale: Double { retina ? 2 : 1 }
        static func < (a: Rung, b: Rung) -> Bool {
            a.preset.rawValue != b.preset.rawValue ? a.preset.rawValue < b.preset.rawValue : (!a.retina && b.retina)
        }
    }

    /// Where Auto started, which sets the start (decision 4). Home and away each get their own
    /// AutoQuality: a flip makes a new one.
    enum Place: Equatable { case home, away }

    /// How a step reaches the encoder. `live`: the running session's rate lowered in place, one preset
    /// down, same resolution (the only change the encoder follows live: docs/evidence/adaptive-quality).
    /// `restart`: a new session (every climb, every resolution change, and a jump of two or more rungs).
    enum How: Equatable { case live, restart }

    enum Why: Equatable {
        /// Frames withheld in `LinkJudge.shortToBehind` of the last `LinkJudge.window` seconds from this
        /// device; `carriedKbps` what its link carried, when measured.
        case behind(device: ObjectIdentifier, carriedKbps: Int?)
        /// Every governing device clean and loaded for this many seconds in a row.
        case clean(seconds: Int)
    }

    struct Step: Equatable {
        let from: Rung
        let to: Rung
        let how: How
        let why: Why
    }

    /// The start's cap (docs/adaptive-quality-plan.md, open question 1). True: the FIRST judgement after
    /// Auto starts (or flips home/away) is decision 4's "capped by the link the first seconds show": its
    /// target is what the link carried (`LinkJudge.suggestion`), one restart when two or more rungs
    /// down. Every later judgement is one rung, live. False: the first judgement is one rung too (~15 s
    /// from Extreme to Balanced on 24 Mbps Wi-Fi). An `init` argument defaults to it, so the check can
    /// run both.
    static let startCappedByLink = true
    /// A climb counts a clean second only when the stream offered at least this share of its frame rate
    /// (sent + withheld >= fps / loadedDivisor): a still window is clean at any rate and says nothing
    /// about the rung above. A calibration, not a decoded rule (open question 3); gated by the pacing
    /// harness's `autostill` case, to be measured there.
    static let loadedDivisor = 4
    /// A climb that is judged behind within `failedClimbWithin` seconds of arriving doubles the clean
    /// seconds the next climb to that rung needs, up to `holdMax`. A calibration, not a decoded rule
    /// (open question 4); gated by the pacing harness's `autodown` case, to be measured there.
    static let failedClimbWithin = 10, holdMax = 60

    let place: Place
    /// Ascending; built once from the Mac's Resolution (`ladder(retina:)`).
    let ladder: [Rung]
    /// The rung Auto wants. What the pipeline runs is the coordinator's.
    private(set) var rung: Rung

    private let cappedByLink: Bool

    /// One device's seconds at the running rung, oldest first, at most `LinkJudge.window`; and its clean,
    /// loaded seconds in a row.
    private struct Track: Equatable {
        var recent: [LinkJudge.Second] = []
        var cleanLoaded = 0
    }
    private var tracks: [ObjectIdentifier: Track] = [:]
    /// The running rung the windows were filled at; nil before the first second.
    private var judgedAt: Rung?
    /// Seconds since the running rung last changed, and whether a climb brought it there.
    private var secondsAtRung = 0
    private var climbedHere = false
    /// The rung the last climb step asked for: `climbedHere` once the pipeline runs it.
    private var climbingTo: Rung?
    /// Clean seconds a climb into a rung needs, when more than `LinkJudge.cleanToFine` (a failed climb).
    private var climbNeeds: [Rung: Int] = [:]
    /// The start's cap has been judged (`startCappedByLink`): set by the first behind judgement, and by
    /// the first step of any kind (a link that let Auto climb needed no cap). Never cleared: a new start
    /// is a new value.
    private var capped = false

    /// Home: the ladder's top (Extreme, at the Mac's Resolution); the first judgement caps it by what the
    /// link carried. Away: the bottom (Low · Standard, the Retina ladder's only Low), climbing. `retina`
    /// is the Resolution of the place being started.
    init(place: Place, retina: Bool, cappedByLink: Bool = AutoQuality.startCappedByLink) {
        self.place = place
        self.ladder = Self.ladder(retina: retina)
        self.cappedByLink = cappedByLink
        self.rung = place == .home ? ladder[ladder.count - 1] : ladder[0]
    }

    /// Retina: Low · Standard, then every preset above Low at Retina. The ladder skips Low · Retina:
    /// the hardware encoder drops frames itself at that rate and the link judge never sees them
    /// (ratelive, 3024×1964: 7 a second at 8 Mbps, 34 at 4 Mbps; open question 2), so Efficient · Retina
    /// steps to Low · Standard. Standard: every preset at Standard. Top: Extreme (decision 3).
    static func ladder(retina: Bool) -> [Rung] {
        let presets = QualityPreset.allCases.sorted { $0.rawValue < $1.rawValue }
        return retina ? [Rung(preset: .low, retina: false)] + presets.dropFirst().map { Rung(preset: $0, retina: true) }
                      : presets.map { Rung(preset: $0, retina: false) }
    }

    /// The devices whose links govern the rung (decision 6): those at home while any is, else all.
    /// `away`: each connected device, true when the Mac counts it away (ClientRoute.isAway).
    static func governing(_ away: [ObjectIdentifier: Bool]) -> Set<ObjectIdentifier> {
        let home = away.filter { !$0.value }.keys
        return Set(home.isEmpty ? Array(away.keys) : Array(home))
    }

    /// Closes one second for every connected device (`seconds`, the server's sweep) and returns the step
    /// to take, if any; `rung` is already the step's `to` when it returns. `running`: the rung the
    /// pipeline runs now. `fps`: the stream's rate (the carried rate is compared at it, as
    /// `LinkJudge.suggestion` does). Down when any governing device is behind (to the lowest rung any of
    /// them asks for); up only when every governing device has been clean and loaded for what the climb
    /// needs.
    mutating func close(_ seconds: [ObjectIdentifier: LinkJudge.Second], governing: Set<ObjectIdentifier>,
                        running: Rung, fps: Int) -> Step? {
        if running != judgedAt {
            tracks = [:]
            judgedAt = running
            secondsAtRung = 0
            climbedHere = running == climbingTo
            climbingTo = nil
        }
        guard running == rung else { return nil }
        tracks = tracks.filter { seconds[$0.key] != nil }
        for (id, second) in seconds {
            var track = tracks[id] ?? Track()
            track.recent.append(second)
            if track.recent.count > LinkJudge.window { track.recent.removeFirst(track.recent.count - LinkJudge.window) }
            if LinkJudge.isShort(second) { track.cleanLoaded = 0 }
            else if Self.isLoaded(second, fps: fps) { track.cleanLoaded += 1 }
            tracks[id] = track
        }
        secondsAtRung += 1

        let behind = governing.filter { id in
            (tracks[id]?.recent.filter(LinkJudge.isShort).count ?? 0) >= LinkJudge.shortToBehind
        }
        if !behind.isEmpty {
            let capping = !capped
            capped = true
            let asks = behind.compactMap { id -> (target: Rung, id: ObjectIdentifier)? in
                let carried = LinkJudge.carriedKbps(of: tracks[id]?.recent ?? [])
                return Self.downTarget(from: rung, carriedKbps: carried, fps: fps, ladder: ladder, capping: capping && cappedByLink)
                    .map { ($0, id) }
            }
            guard let lowest = asks.min(by: { $0.target < $1.target }) else { return nil }
            if climbedHere && secondsAtRung <= Self.failedClimbWithin {
                climbNeeds[rung] = min(Self.holdMax, 2 * needs(rung))
            }
            return take(to: lowest.target, why: .behind(device: lowest.id,
                                                       carriedKbps: LinkJudge.carriedKbps(of: tracks[lowest.id]?.recent ?? [])))
        }

        guard let i = ladder.firstIndex(of: rung), i + 1 < ladder.count, !governing.isEmpty else { return nil }
        let up = ladder[i + 1]
        guard governing.allSatisfy({ (tracks[$0]?.cleanLoaded ?? 0) >= needs(up) }) else { return nil }
        return take(to: up, why: .clean(seconds: needs(up)))
    }

    /// Takes a step: `rung` moves and the start's cap is spent.
    private mutating func take(to target: Rung, why: Why) -> Step {
        let from = rung
        rung = target
        capped = true
        climbingTo = target > from ? target : nil
        return Step(from: from, to: target, how: Self.how(from: from, to: target, ladder: ladder), why: why)
    }

    /// Where a judgement goes. The start's cap (`capping`): `LinkJudge.suggestion` at this rung mapped
    /// onto the ladder (what fits in 70 % of the carried rate; one preset down without a measure; Low ·
    /// Standard from Efficient · Retina), so the cap and the old callout name the same quality. A behind
    /// link carries under the stream's ~0.7 × target, so the cap is at most ~0.49 × the rung: two or
    /// more rungs, a restart. Otherwise one rung down, live (or a restart across a resolution). Nil at
    /// the bottom (nothing lower: Auto holds).
    private static func downTarget(from rung: Rung, carriedKbps: Int?, fps: Int, ladder: [Rung], capping: Bool) -> Rung? {
        guard let i = ladder.firstIndex(of: rung), i > 0 else { return nil }
        guard capping,
              let fit = LinkJudge.suggestion(carriedKbps: carriedKbps, bitrate: rung.bitrate, fps: fps, captureScale: rung.captureScale),
              let preset = QualityPreset(rawValue: fit.bitrate) else { return ladder[i - 1] }
        let wanted = Rung(preset: preset, retina: fit.captureScale.map { $0 >= 1.5 } ?? rung.retina)
        guard let j = ladder.firstIndex(of: wanted) else { return ladder[i - 1] }
        return ladder[min(j, i - 1)]
    }

    /// Live only for one rung down at the same resolution (the measured case); a restart otherwise.
    private static func how(from: Rung, to: Rung, ladder: [Rung]) -> How {
        guard to < from, from.retina == to.retina,
              let i = ladder.firstIndex(of: from), let j = ladder.firstIndex(of: to), i - j == 1 else { return .restart }
        return .live
    }

    /// The second offered at least fps / `loadedDivisor` frames: the window moved.
    private static func isLoaded(_ s: LinkJudge.Second, fps: Int) -> Bool {
        s.sent + s.withheld >= max(1, fps / loadedDivisor)
    }

    /// Clean seconds a climb into `rung` needs: `LinkJudge.cleanToFine` (decision 5), more after it failed.
    private func needs(_ rung: Rung) -> Int { climbNeeds[rung] ?? LinkJudge.cleanToFine }

    // MARK: The host's lines (decision 7: the Mac's log names every step; nothing else does)

    /// "Auto: Extreme → Balanced (the link to iPad (iPad14,1) carried about 21 Mbps); restarting."
    /// "Auto: Ultra → Pro (frames withheld from iPad (iPad14,1) in 3 of the last 5 seconds); lowered live."
    /// "Auto: Efficient · Retina → Low · Standard (…); restarting."  (a resolution is named only when it changes)
    /// "Auto: Pro → Ultra (clean for 5 s); restarting."
    static func stepLine(_ step: Step, device: (ObjectIdentifier) -> String) -> String {
        let move = step.from.retina == step.to.retina
            ? "\(QualityPreset.name(forBitrate: step.from.bitrate)) → \(QualityPreset.name(forBitrate: step.to.bitrate))"
            : "\(title(step.from)) → \(title(step.to))"
        let reason: String
        switch step.why {
        case .behind(let id, let carried?):
            reason = "the link to \(device(id)) carried about \(LinkJudge.mbps(kbps: carried)) Mbps"
        case .behind(let id, nil):
            reason = "frames withheld from \(device(id)) in \(LinkJudge.shortToBehind) of the last \(LinkJudge.window) seconds"
        case .clean(let seconds):
            reason = "clean for \(seconds) s"
        }
        return "Auto: \(move) (\(reason)); \(step.how == .live ? "lowered live" : "restarting")."
    }

    /// At the start, once: "Auto: starting at Extreme · Retina at home; it lowers the quality when the link
    /// cannot carry it." / "Auto: starting at Low · Standard away from home; it climbs while the link keeps up."
    static func startLine(place: Place, rung: Rung) -> String {
        switch place {
        case .home: "Auto: starting at \(title(rung)) at home; it lowers the quality when the link cannot carry it."
        case .away: "Auto: starting at \(title(rung)) away from home; it climbs while the link keeps up."
        }
    }

    /// "Pro · Retina", "Low · Standard".
    private static func title(_ rung: Rung) -> String {
        QualityPreset.shortTitle(bitrate: rung.bitrate, captureScale: rung.captureScale)
    }
}
