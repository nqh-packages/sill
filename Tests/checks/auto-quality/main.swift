// AutoQuality (docs/adaptive-quality-plan.md, docs/design/adaptive-quality/MODULES.md's cases):
// Sources/SillHost/AutoQuality.swift on its own, compiled with LinkJudge.swift (the rules it shares) and
// StreamProtocol's HostSettings.swift (QualityPreset) as one module by build.sh:
//
//   Tests/checks/auto-quality/build.sh . .build/checks/auto-quality/check && .build/checks/auto-quality/check
//
// Everything is driven through `close`, the policy's one entry; `downTarget`, `how`, `isLoaded` and
// `needs` are private. The cases are MODULES.md's, as the plan's resolved questions changed them:
// the Retina ladder skips Low · Retina (question 2), so Efficient · Retina steps to Low · Standard.
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok" : "FAIL") \(what)")
    if !ok { failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias S = LinkJudge.Second
typealias Rung = AutoQuality.Rung
typealias Step = AutoQuality.Step

extension AutoQuality.Rung: CustomStringConvertible {
    public var description: String { "\(preset.name) · \(retina ? "Retina" : "Standard")" }
}

final class Device {}
let devA = Device(), devB = Device(), devC = Device()
let idA = ObjectIdentifier(devA), idB = ObjectIdentifier(devB), idC = ObjectIdentifier(devC)
let names: [ObjectIdentifier: String] = [idA: "iPad (iPad14,1)", idB: "iPhone (iPhone16,2)", idC: "iPad (iPad8,1)"]

func R(_ p: QualityPreset, _ retina: Bool = true) -> Rung { Rung(preset: p, retina: retina) }

/// A short second (20 of 60 withheld) that measured nothing (little waiting, nothing taken); a clean,
/// loaded one; a still one.
let short = S(sent: 40, withheld: 20, taken: 0, waiting: 4_000, heard: true)
/// A short second whose link took `kbps` but whose backlog never reached LinkJudge's measure.
func unmeasured(_ kbps: Int) -> S { S(sent: 40, withheld: 20, taken: kbps * 1000 / 8, waiting: 4_000, heard: true) }
let clean = S(sent: 60, withheld: 0, taken: 300_000, waiting: 0, heard: true)
let still = S(sent: 0, withheld: 0, taken: 200, waiting: 0, heard: true)
/// A short second on a link that carries `kbps`: bytes waiting, so the second is measured.
func limited(_ kbps: Int) -> S { S(sent: 40, withheld: 20, taken: kbps * 1000 / 8, waiting: 100_000, heard: true) }

/// What the coordinator does with `close`: governing from the devices' routes, and a step taken (running
/// becomes its target at once, so the next second is judged at the new rung); `commit: false` leaves a
/// restart pending.
struct Rig {
    var q: AutoQuality
    var running: Rung
    var fps = 60
    var away: [ObjectIdentifier: Bool]
    var steps: [Step] = []
    init(_ q: AutoQuality, away: [ObjectIdentifier: Bool] = [idA: false]) { self.q = q; running = q.rung; self.away = away }

    @discardableResult
    mutating func tick(_ seconds: [ObjectIdentifier: S], commit: Bool = true) -> Step? {
        let step = q.close(seconds, governing: AutoQuality.governing(away), running: running, fps: fps)
        if let step {
            steps.append(step)
            if commit { running = step.to }
        }
        return step
    }

    /// `n` seconds of `s` for the one device A.
    @discardableResult
    mutating func feed(_ s: S, _ n: Int, commit: Bool = true) -> [Step] {
        (0..<n).compactMap { _ in tick([idA: s], commit: commit) }
    }
}

func tag(_ s: Step) -> String {
    let move = s.from.retina == s.to.retina ? "\(s.from.preset.name)>\(s.to.preset.name)" : "\(s.from)>\(s.to)"
    return "\(move) \(s.how == .live ? "live" : "restart")"
}

func home(retina: Bool = true, cap: Bool = true) -> Rig { Rig(AutoQuality(place: .home, retina: retina, cappedByLink: cap)) }
func away(retina: Bool = false) -> Rig { Rig(AutoQuality(place: .away, retina: retina), away: [idA: true]) }

// MARK: 1. The start

eq(AutoQuality(place: .home, retina: true).rung, R(.extreme), "the home start is Extreme · Retina")
eq(AutoQuality(place: .home, retina: false).rung, R(.extreme, false), "the home start at Standard is Extreme · Standard")
eq(AutoQuality(place: .away, retina: false).rung, R(.low, false), "the away start is Low · Standard")
eq(AutoQuality(place: .away, retina: true).rung, R(.low, false), "the away start at a Retina Mac is the ladder's Low · Standard")

// MARK: 2. The ladder

do {
    let retina = AutoQuality.ladder(retina: true)
    eq(retina.map(\.description), ["Low · Standard", "Efficient · Retina", "Balanced · Retina", "High · Retina", "Pro · Retina",
                                   "Ultra · Retina", "Extreme · Retina"], "the Retina ladder skips Low · Retina")
    check(!retina.contains(R(.low)), "…Low · Retina is not on it")
    let standard = AutoQuality.ladder(retina: false)
    eq(standard.map(\.description), ["Low · Standard", "Efficient · Standard", "Balanced · Standard", "High · Standard", "Pro · Standard",
                                     "Ultra · Standard", "Extreme · Standard"], "the Standard ladder has no Retina")
    eq(retina.last, R(.extreme), "the Retina ladder's top is Extreme")
    eq(standard.last, R(.extreme, false), "the Standard ladder's top is Extreme")
    check(retina == retina.sorted() && standard == standard.sorted(), "both are ascending")
    eq(AutoQuality(place: .home, retina: true).ladder, retina, "the policy keeps the Mac's ladder")
}

// MARK: 3 and 4. Behind at 3 short seconds of 5, one rung down, live

do {
    var r = home()
    eq(r.feed(short, 2).count, 0, "2 short seconds at Extreme do nothing")
    let first = r.feed(short, 1)
    eq(first.map(tag), ["Extreme>Ultra live"], "the third short second, nothing measured: one preset down, live (the cap names one)")
    eq(r.q.rung, R(.ultra), "…and the rung is Ultra now")
    eq(first.first?.why, .behind(device: idA, carriedKbps: nil), "…named by the device and no rate")
    eq(r.feed(short, 3).map(tag), ["Ultra>Pro live"], "3 short of 5 at Ultra with nothing measured goes to Pro, live")
}
do {
    var r = home()
    var steps: [Step] = []
    for second in [short, clean, clean, short, clean, clean, short, clean] { steps += [r.tick([idA: second])].compactMap { $0 } }
    eq(steps.count, 0, "3 short seconds in 8 but never 3 in the last 5: nothing")
}
do {
    var r = home()
    eq(r.feed(clean, 3).count, 0, "clean seconds do nothing at the top")
    var s = home()
    var spread: [Step] = []
    for second in [short, clean, short, clean, short] { spread += [s.tick([idA: second])].compactMap { $0 } }
    eq(spread.map(tag), ["Extreme>Ultra live"], "3 short seconds spread over 5 are behind, at the fifth")
    var t = home()
    var four: [Step] = []
    for second in [short, clean, clean, clean, short, short] { four += [t.tick([idA: second])].compactMap { $0 } }
    eq(four.count, 0, "3 short in 6 but 2 in the last 5: nothing")
}

// MARK: 5a. The start's cap before LinkJudge measures (the pacing harness's autodown)

do {
    var r = home()
    let cap = r.feed(unmeasured(24_000), 3)
    eq(cap.map(tag), ["Extreme>Balanced restart"], "no measure yet: the cap sizes from what the short seconds took, one restart")
    eq(cap.first?.why, .behind(device: idA, carriedKbps: 24_000), "…and names that rate")
    eq(r.feed(unmeasured(12_000), 3).map(tag), ["Balanced>Efficient live"], "after the cap, an unmeasured behind is one rung, live")
    let later = r.feed(limited(5_000), 3)
    eq(later.first?.why, .behind(device: idA, carriedKbps: 5_000), "after the cap, a measured behind names LinkJudge's carried rate")
}

// MARK: 5. The start's cap

do {
    var r = home()
    let steps = r.feed(limited(24_000), 3)
    eq(steps.map(tag), ["Extreme>Balanced restart"], "at Extreme with 24 Mbps carried: Balanced, by restart (≤ 0.7 × 24)")
    eq(steps.first?.why, .behind(device: idA, carriedKbps: 24_000), "…the rate in the step")
    var off = home(cap: false)
    eq(off.feed(limited(24_000), 3).map(tag), ["Extreme>Ultra live"], "with the cap off: Ultra, live")
    eq(AutoQuality.startCappedByLink, true, "the cap is on by default")
    // A second judgement is one rung, live, whatever the link carried.
    eq(r.feed(limited(5_000), 3).map(tag), ["Balanced>Efficient live"], "the second judgement is one rung (Efficient, not Low · Standard), live")
}
do {
    var r = home()
    r.feed(short, 3); r.feed(short, 3)
    eq(r.q.rung, R(.pro), "Pro")
    eq(r.feed(limited(26_000), 3).map(tag), ["Pro>High live"], "Pro with 26 Mbps carried goes to High, not Balanced: the cap was spent at the start")
}
do {
    var r = home()
    eq(r.feed(limited(3_000), 3).map(tag), ["Extreme · Retina>Low · Standard restart"], "a link carrying 3 Mbps at the start: Low · Standard, by restart")
    var s = home(retina: false)
    eq(s.feed(limited(3_000), 3).map(tag), ["Extreme>Low restart"], "…at Standard: Low, by restart")
    var one = home()
    eq(one.feed(limited(150_000), 3).map(tag), ["Extreme>Ultra live"], "a measured rate that fits one rung down is a live step")
}
do {
    // A climb spends the cap too: an away Auto that climbed needs none.
    var r = away()
    r.feed(clean, 5); r.feed(clean, 5)
    eq(r.q.rung, R(.balanced, false), "away: two climbs, to Balanced · Standard")
    eq(r.feed(limited(1_000), 3).map(tag), ["Balanced>Efficient live"], "…a behind link then is one rung down, live, not the cap's Low")
    var cold = away()
    cold.feed(limited(1_000), 3)
    eq(cold.q.rung, R(.low, false), "away at Low · Standard: nothing below, whatever it carried")
}

do {
    var r = home()
    eq(r.feed(limited(21_000), 3).map(tag), ["Extreme>Efficient restart"], "21 Mbps carried at the start: Efficient (0.7 × 21 = 14.7 < 15)")
    var two = home()
    eq(two.feed(limited(80_000), 3).map(tag), ["Extreme>Pro restart"], "a step of two rungs (80 Mbps carried: Pro) is a restart, not live")
    var f = home(); f.fps = 120
    eq(f.feed(limited(24_000), 3).map(tag), ["Extreme>Efficient restart"], "at 120 fps the same 24 Mbps fits Efficient (twice the rate per preset), not Balanced")
}

// MARK: 6. The bottom

do {
    var r = home(cap: false)
    var all: [Step] = []
    for _ in 0..<6 { all += r.feed(short, 3) }
    eq(all.map(tag), ["Extreme>Ultra live", "Ultra>Pro live", "Pro>High live", "High>Balanced live", "Balanced>Efficient live",
                      "Efficient · Retina>Low · Standard restart"], "one rung at a time; Efficient · Retina to Low · Standard is a restart")
    eq(r.q.rung, R(.low, false), "Low · Standard")
    eq(r.feed(short, 9).count, 0, "nothing below the bottom: Auto holds")
    eq(r.q.rung, R(.low, false), "…and the rung stays")
    var s = home(retina: false, cap: false)
    var standardSteps: [Step] = []
    for _ in 0..<6 { standardSteps += s.feed(short, 3) }
    check(standardSteps.allSatisfy { $0.how == .live } && s.q.rung == R(.low, false), "at Standard every step is live, down to Low")
}

// MARK: 7. Climbing

do {
    var r = away()
    eq(r.feed(clean, 4).count, 0, "4 clean, loaded seconds do not climb")
    let up = r.feed(clean, 1)
    eq(up.map(tag), ["Low>Efficient restart"], "5 climb one rung, by restart")
    eq(up.first?.why, .clean(seconds: 5), "…clean for 5 s")
    var s = away()
    eq(s.feed(still, 30).count, 0, "clean still seconds do not climb")
    var t = away()
    t.feed(clean, 4); t.feed(still, 20)
    eq(t.feed(clean, 1).map(tag), ["Low>Efficient restart"], "still seconds neither count nor break the run: the fifth loaded second climbs")
    var u = away()
    u.feed(clean, 4); u.feed(short, 1); u.feed(clean, 4)
    eq(u.q.rung, R(.low, false), "a short second restarts the count: 4 + short + 4 does not climb")
    eq(u.feed(clean, 1).map(tag), ["Low>Efficient restart"], "…the fifth after it does")
    var top = home()
    eq(top.feed(clean, 30).count, 0, "nothing above Extreme")
    // Loaded: at least fps / 4 frames offered.
    func offered(_ n: Int) -> S { S(sent: n, withheld: 0, taken: 100_000, waiting: 0, heard: true) }
    var f60 = away()
    eq(f60.feed(offered(14), 20).count, 0, "14 frames offered at 60 fps are not loaded")
    eq(f60.feed(offered(15), 5).count, 1, "15 are")
    var f120 = away(); f120.fps = 120
    eq(f120.feed(offered(29), 20).count, 0, "29 frames offered at 120 fps are not loaded")
    eq(f120.feed(offered(30), 5).count, 1, "30 are")
}

do {
    var r = away()
    var all: [Step] = []
    for _ in 0..<6 { all += r.feed(clean, 5) }
    eq(all.map(tag), ["Low>Efficient restart", "Efficient>Balanced restart", "Balanced>High restart", "High>Pro restart", "Pro>Ultra restart",
                      "Ultra>Extreme restart"], "a full climb at Standard: every step a restart, up to Extreme")
    eq(r.feed(clean, 10).count, 0, "…and no further")
    var retina = Rig(AutoQuality(place: .away, retina: true), away: [idA: true])
    var up: [Step] = []
    for _ in 0..<6 { up += retina.feed(clean, 5) }
    eq(up.map(tag), ["Low · Standard>Efficient · Retina restart", "Efficient>Balanced restart", "Balanced>High restart", "High>Pro restart",
                     "Pro>Ultra restart", "Ultra>Extreme restart"], "…at Retina the first climb crosses the resolution")
    var nobody = Rig(AutoQuality(place: .away, retina: false), away: [:])
    var none: [Step] = []
    for _ in 0..<10 { none += [nobody.tick([:])].compactMap { $0 } }
    eq(none.count, 0, "no device connected: nothing climbs")
}

// MARK: 8. A failed climb holds the next one

do {
    // At each rung the climb arrives at, 3 short seconds are a failed climb.
    var r = away()
    var waits: [Int] = []
    for _ in 0..<6 {
        var n = 0
        while true {
            n += 1
            if r.tick([idA: clean]) != nil { break }
            if n > 200 { break }
        }
        waits.append(n)
        r.feed(short, 3)
    }
    eq(waits, [5, 10, 20, 40, 60, 60], "the clean seconds a climb needs: 5, then 10, 20, 40, 60 and no more after failures")
    eq(r.q.rung, R(.low, false), "…and Auto is back at Low · Standard each time")
    // The failure counts within 10 s of arriving, not after.
    func afterFailure(at second: Int) -> Int {
        var r = away()
        r.feed(clean, 5)
        r.feed(still, second - 3); r.feed(short, 3)
        var n = 0
        while r.tick([idA: clean]) == nil && n < 100 { n += 1 }
        return n + 1
    }
    eq(afterFailure(at: 10), 10, "a climb behind on its tenth second doubles the next one's seconds")
    eq(afterFailure(at: 11), 5, "…on its eleventh it does not")
    eq(afterFailure(at: 3), 10, "…an early failure doubles it too")
}

do {
    // A rung reached by a step down is no failed climb: a behind link there holds nothing.
    var r = home(cap: false)
    r.feed(short, 3); r.feed(short, 3); r.feed(short, 3)
    eq(r.q.rung, R(.high), "down to High")
    var n = 0
    while r.tick([idA: clean]) == nil && n < 100 { n += 1 }
    eq(n + 1, 5, "…the climb back to Pro needs 5 clean seconds: Pro's judgement was no failed climb")
}

do {
    // A hold on a rung is cleared once Auto has stayed at it 60 s without a behind judgement.
    func climbAfter(stayed seconds: Int) -> Int {
        var r = away()
        r.feed(clean, 5)
        r.feed(short, 3)
        r.feed(clean, 9)
        r.feed(clean, 1)
        eq(r.q.rung, R(.efficient, false), "the second climb into Efficient needed 10 clean seconds")
        r.feed(still, seconds)
        r.feed(short, 3)
        eq(r.q.rung, R(.low, false), "…and Auto fell back to Low")
        var n = 0
        while r.tick([idA: clean]) == nil && n < 100 { n += 1 }
        return n + 1
    }
    eq(climbAfter(stayed: 57), 10, "a rung left on its 60th second by a behind judgement keeps its hold: the next climb needs 10")
    eq(climbAfter(stayed: 60), 5, "a rung kept 60 s without a behind judgement loses it: the next climb needs 5")
}

// MARK: 9. It does not blind itself

do {
    var r = home()
    eq(r.feed(short, 3, commit: false).map(tag), ["Extreme>Ultra live"], "a step with the running rung not yet committed")
    eq(r.feed(short, 10, commit: false).count, 0, "…while the pipeline still runs Extreme, nothing is judged: close returns nil, every time")
    eq(r.q.rung, R(.ultra), "…and the wanted rung stays")
    r.running = R(.ultra)
    eq(r.feed(short, 2).count, 0, "after the live step the shorts from before do not count: 2 new ones do nothing")
    eq(r.feed(short, 1).map(tag), ["Ultra>Pro live"], "…the third new one steps again")
}
do {
    var r = away()
    eq(r.feed(clean, 5, commit: false).map(tag), ["Low>Efficient restart"], "a climb whose restart is pending")
    eq(r.feed(clean, 20, commit: false).count, 0, "…is not climbed again while it is pending")
    eq(r.feed(short, 20, commit: false).count, 0, "…nor judged behind")
    r.running = R(.efficient, false)
    eq(r.feed(clean, 4).count, 0, "once it runs, the seconds at the old rung are not counted: 4 clean do not climb")
    eq(r.feed(clean, 1).map(tag), ["Efficient>Balanced restart"], "…the fifth does")
}
do {
    var r = home()
    r.running = R(.balanced)
    eq(r.feed(short, 10).count, 0, "a pipeline running another rung than the wanted one judges nothing")
}
do {
    // A device that leaves is forgotten; one that returns starts afresh.
    var r = Rig(AutoQuality(place: .away, retina: false), away: [idA: true, idB: true])
    for _ in 0..<4 { r.tick([idA: clean, idB: clean]) }
    r.tick([idB: clean])
    eq(r.tick([idA: clean, idB: clean]).map(tag), nil, "a device that left a second and came back is counted from 1 again: 4 + gap + 1 does not climb")
    for _ in 0..<3 { r.tick([idA: clean, idB: clean]) }
    eq(r.tick([idA: clean, idB: clean]).map(tag), "Low>Efficient restart", "…it climbs when it has 5 of its own")
}

// MARK: 10. Governance

do {
    eq(AutoQuality.governing([idA: false, idB: true]), [idA], "a device at home governs alone")
    eq(AutoQuality.governing([idA: true, idB: true]), [idA, idB], "with every device away, all govern")
    eq(AutoQuality.governing([idA: false, idB: false, idC: true]), [idA, idB], "two at home govern, the one away does not")
    eq(AutoQuality.governing([:]), [], "no device, no one governs")

    var r = Rig(AutoQuality(place: .home, retina: true), away: [idA: false, idB: true])
    var steps: [Step] = []
    for _ in 0..<10 { steps += [r.tick([idA: clean, idB: short])].compactMap { $0 } }
    eq(steps.count, 0, "an away device's short seconds do not move Auto while a device is at home")
    for _ in 0..<3 { steps += [r.tick([idA: short, idB: clean])].compactMap { $0 } }
    eq(steps.map(tag), ["Extreme>Ultra live"], "…the home device's do")
    eq(steps.first?.why, .behind(device: idA, carriedKbps: nil), "…named by it")

    var all = Rig(AutoQuality(place: .home, retina: true), away: [idA: true, idB: true])
    var down: [Step] = []
    for _ in 0..<3 { down += [all.tick([idA: clean, idB: short])].compactMap { $0 } }
    eq(down.map(tag), ["Extreme>Ultra live"], "all away: one short device moves Auto down")
    eq(down.first?.why, .behind(device: idB, carriedKbps: nil), "…named by it")

    var up = Rig(AutoQuality(place: .away, retina: false), away: [idA: true, idB: true])
    var climbed: [Step] = []
    for _ in 0..<10 { climbed += [up.tick([idA: clean, idB: still])].compactMap { $0 } }
    eq(climbed.count, 0, "all away: a climb needs every device clean and loaded (one still: no)")
    for _ in 0..<4 { climbed += [up.tick([idA: clean, idB: clean])].compactMap { $0 } }
    eq(climbed.count, 0, "…B's fourth loaded second: no")
    climbed += [up.tick([idA: clean, idB: clean])].compactMap { $0 }
    eq(climbed.map(tag), ["Low>Efficient restart"], "…its fifth: yes")

    var two = Rig(AutoQuality(place: .home, retina: true), away: [idA: true, idB: true])
    var asks: [Step] = []
    for _ in 0..<3 { asks += [two.tick([idA: limited(24_000), idB: limited(3_000)])].compactMap { $0 } }
    eq(asks.map(tag), ["Extreme · Retina>Low · Standard restart"], "two behind devices: the lowest rung either asks for")
    eq(asks.first?.why, .behind(device: idB, carriedKbps: 3_000), "…named by the slower one, with its rate")

    var none = Rig(AutoQuality(place: .home, retina: true), away: [:])
    eq(none.tick([:]).map(tag), nil, "no device connected: nothing")
    var absent = Rig(AutoQuality(place: .away, retina: false), away: [idA: true])
    var nothing: [Step] = []
    for _ in 0..<10 { nothing += [absent.tick([idB: clean])].compactMap { $0 } }
    eq(nothing.count, 0, "a governing device with no seconds blocks a climb")
}

// MARK: 11. The lines

do {
    let sketch = Step(from: R(.extreme), to: R(.balanced), how: .restart, why: .behind(device: idA, carriedKbps: 21_000))
    eq(AutoQuality.stepLine(sketch, device: { names[$0]! }),
       "Auto: Extreme → Balanced (the link to iPad (iPad14,1) carried about 21 Mbps); restarting.", "a measured step's line")
    var r = home()
    let cap = r.feed(limited(24_000), 3)
    eq(AutoQuality.stepLine(cap[0], device: { names[$0]! }),
       "Auto: Extreme → Balanced (the link to iPad (iPad14,1) carried about 24 Mbps); restarting.", "the cap's line")
    var s = home()
    let live = s.feed(short, 3)
    eq(AutoQuality.stepLine(live[0], device: { names[$0]! }),
       "Auto: Extreme → Ultra (frames withheld from iPad (iPad14,1) in 3 of the last 5 seconds); lowered live.", "a live step's line")
    var t = home(cap: false)
    var last: [Step] = []
    for _ in 0..<6 { last = t.feed(short, 3) }
    eq(AutoQuality.stepLine(last[0], device: { names[$0]! }),
       "Auto: Efficient · Retina → Low · Standard (frames withheld from iPad (iPad14,1) in 3 of the last 5 seconds); restarting.",
       "a step across the resolution names it")
    let climb = Step(from: R(.pro), to: R(.ultra), how: .restart, why: .clean(seconds: 5))
    eq(AutoQuality.stepLine(climb, device: { names[$0]! }), "Auto: Pro → Ultra (clean for 5 s); restarting.", "a climb's line")
    let across = Step(from: R(.low, false), to: R(.efficient), how: .restart, why: .clean(seconds: 10))
    eq(AutoQuality.stepLine(across, device: { names[$0]! }),
       "Auto: Low · Standard → Efficient · Retina (clean for 10 s); restarting.", "a climb across the resolution, after a hold")
    var u = away()
    let first = u.feed(clean, 5)
    eq(AutoQuality.stepLine(first[0], device: { names[$0]! }), "Auto: Low → Efficient (clean for 5 s); restarting.", "…the same through close")
    eq(AutoQuality.startLine(place: .home, rung: R(.extreme)),
       "Auto: starting at Extreme · Retina at home; it lowers the quality when the link cannot carry it.", "the home start's line")
    eq(AutoQuality.startLine(place: .away, rung: R(.low, false)),
       "Auto: starting at Low · Standard away from home; it climbs while the link keeps up.", "the away start's line")
}

// MARK: 12. Simulated links, which set the pacing gates' numbers

/// One line of link: the stream offers 0.7 × the rung's rate (its frames are that big), the link carries
/// `link(t)` Mbit/s; a second is short when the stream offers more than the link carries (20 of 60 frames
/// withheld, the bytes waiting), else clean. A step is taken at once.
func simulate(_ rig: Rig, seconds: Int, link: (Int) -> Double) -> [(t: Int, step: Step)] {
    var r = rig
    var log: [(Int, Step)] = []
    for t in 1...seconds {
        let offered = Double(r.running.bitrate) * 0.7 / 1_000_000
        let second: S
        if offered > link(t) {
            second = S(sent: 40, withheld: 20, taken: Int(link(t) * 1_000_000 / 8), waiting: 100_000, heard: true)
        } else {
            second = S(sent: 60, withheld: 0, taken: Int(offered * 1_000_000 / 8), waiting: 0, heard: true)
        }
        if let step = r.tick([idA: second]) { log.append((t, step)) }
    }
    return log
}

do {
    let log = simulate(home(), seconds: 260) { _ in 24 }
    let head = log.prefix(4).map { "\($0.t) \(tag($0.step))" }
    eq(head, ["3 Extreme>Balanced restart", "8 Balanced>High restart", "13 High>Pro restart", "16 Pro>High live"],
       "24 Mbit/s from Extreme: cap to Balanced, climb to High (17.5 fits), to Pro (28 does not), live back to High")
    check(log.allSatisfy { $0.step.to <= R(.pro) }, "…never above Pro")
    let restartsDown = log.filter { $0.step.to < $0.step.from && $0.step.how == .restart }
    eq(restartsDown.count, 1, "…the cap is the only restart down")
    let climbsToPro = log.filter { $0.step.to == R(.pro) }.map(\.t)
    let livesFromPro = log.filter { $0.step.from == R(.pro) }.map(\.t)
    let gaps = zip(livesFromPro, climbsToPro.dropFirst()).map { $1 - $0 }
    eq(Array(gaps.prefix(5)), [10, 20, 40, 60, 60], "Pro's hold doubles 10 → 20 → 40 → 60 s")
    let atHigh = (1...260).filter { t in
        var rung = R(.extreme)
        for entry in log where entry.t < t { rung = entry.step.to }
        return rung == R(.high)
    }.count
    check(atHigh * 100 >= 260 * 70, "…and most of the time is spent at High (\(atHigh) of 260 s)")
}
do {
    let log = simulate(away(), seconds: 200) { $0 <= 20 ? 8 : 200 }
    let ups = log.filter { $0.step.to > $0.step.from }.map(\.t)
    check(log.filter { $0.step.to > $0.step.from }.allSatisfy { $0.step.how == .restart }, "away, 8 → 200 Mbit/s at 20 s: every step up is a restart")
    check(zip(ups, ups.dropFirst()).allSatisfy { $1 - $0 >= 5 }, "…at least 5 s apart: \(ups)")
    let top = log.first { $0.step.to == R(.extreme, false) }?.t
    check(top.map { $0 <= 20 + 60 } ?? false, "…Extreme within 60 s of the rise: \(top.map(String.init) ?? "never")")
}
do {
    var r = away()
    eq(r.feed(still, 120).count, 0, "a still window on a slow link: no climb in 120 s")
}

print(failures == 0 ? "auto-quality: all passed" : "auto-quality: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
