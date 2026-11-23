"""Mutants of Sources/SillHost/AutoQuality.swift and of the LinkJudge.swift rules it shares (the 3-of-5
timing, the clean run, the carried rate, the suggestion): each changes one place, is compiled with the
check by build.sh and must make it fail. usage: mutants.py ROOT"""
import os, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
AQ = "Sources/SillHost/AutoQuality.swift"; LJ = "Sources/SillHost/LinkJudge.swift"
MUTANTS = [
    # The shared rules (LinkJudge.swift): Auto's pace is LinkJudge's.
    ("LJ1 behind at 2 short of 5 (3-of-5 became 2-of-5)", LJ, "static let window = 5, shortToBehind = 3,", "static let window = 5, shortToBehind = 2,"),
    ("LJ2 a climb after 4 clean seconds (cleanToFine 5 became 4)", LJ, "cleanToFine = 5, stallSeconds = 3", "cleanToFine = 4, stallSeconds = 3"),
    ("LJ3 the window is 4 seconds", LJ, "static let window = 5, shortToBehind = 3,", "static let window = 4, shortToBehind = 3,"),
    ("LJ4 a still second is short", LJ, "s.withheld >= 3 && 10 * s.withheld >= s.sent + s.withheld", "(s.withheld >= 3 || s.sent == 0) && 10 * s.withheld >= s.sent + s.withheld"),
    ("LJ5 the carried rate never measured", LJ, "guard measured.count >= measureNeeded else { return nil }", "guard measured.count > 99 else { return nil }"),
    ("LJ6 0.8 headroom for 0.7", LJ, "static let headroom = 0.7", "static let headroom = 0.8"),
    ("LJ7 the suggestion ignores fps", LJ, "pick = lower.last { Double($0) * Double(max(fps, 1)) / 60 <= budget } ?? lower[0]", "pick = lower.last { Double($0) <= budget } ?? lower[0]"),
    ("LJ8 Standard never suggested", LJ, "return (pick, pick == QualityPreset.low.rawValue && retina ? 1 : nil)", "return (pick, nil)"),
    # The ladder and the start.
    ("AQ1 Low · Retina on the ladder", AQ, "presets.dropFirst().map { Rung(preset: $0, retina: true) }", "presets.map { Rung(preset: $0, retina: true) }"),
    ("AQ2 Retina on the Standard ladder", AQ, ": presets.map { Rung(preset: $0, retina: false) }", ": presets.map { Rung(preset: $0, retina: true) }"),
    ("AQ3 the away start at the top and home at the bottom", AQ, "self.rung = place == .home ? ladder[ladder.count - 1] : ladder[0]", "self.rung = place == .away ? ladder[ladder.count - 1] : ladder[0]"),
    ("AQ4 the home start one below the top", AQ, "self.rung = place == .home ? ladder[ladder.count - 1] : ladder[0]", "self.rung = place == .home ? ladder[ladder.count - 2] : ladder[0]"),
    ("AQ5 the top is below Extreme", AQ, "guard let i = ladder.firstIndex(of: rung), i + 1 < ladder.count, !governing.isEmpty else { return nil }", "guard let i = ladder.firstIndex(of: rung), i + 2 < ladder.count, !governing.isEmpty else { return nil }"),
    # The cap.
    ("AQ6 the start's cap disabled", AQ, "static let startCappedByLink = true", "static let startCappedByLink = false"),
    ("AQ7 a step does not spend the cap", AQ, "        capped = true\n        climbingTo", "        climbingTo"),
    ("AQ8 the cap keeps Retina for Low", AQ, "fit.captureScale.map { $0 >= 1.5 } ?? rung.retina", "fit.captureScale.map { $0 >= 1.5 } ?? true"),
    # Live or restart.
    ("AQ9 live for a drop of two rungs", AQ, "i - j == 1 else { return .restart }", "i - j <= 2 else { return .restart }"),
    ("AQ10 live across a resolution", AQ, "guard to < from, from.retina == to.retina,", "guard to < from,"),
    ("AQ11 a climb is live", AQ, "guard to < from, from.retina == to.retina,\n              let i = ladder.firstIndex(of: from), let j = ladder.firstIndex(of: to), i - j == 1 else { return .restart }", "guard from.retina == to.retina,\n              let i = ladder.firstIndex(of: from), let j = ladder.firstIndex(of: to), abs(i - j) == 1 else { return .restart }"),
    ("AQ12 every step a restart", AQ, "        return .live\n", "        return .restart\n"),
    # Climbing: loaded, hold.
    ("AQ13 the loaded guard removed", AQ, "s.sent + s.withheld >= max(1, fps / loadedDivisor)", "true"),
    ("AQ14 loaded needs more than fps / 4", AQ, "s.sent + s.withheld >= max(1, fps / loadedDivisor)", "s.sent + s.withheld > max(1, fps / loadedDivisor)"),
    ("AQ15 loaded at fps / 2", AQ, "static let loadedDivisor = 4", "static let loadedDivisor = 2"),
    ("AQ16 the hold not doubled", AQ, "climbNeeds[rung] = min(Self.holdMax, 2 * needs(rung))", "climbNeeds[rung] = min(Self.holdMax, needs(rung))"),
    ("AQ17 the hold not capped", AQ, "climbNeeds[rung] = min(Self.holdMax, 2 * needs(rung))", "climbNeeds[rung] = 2 * needs(rung)"),
    ("AQ18 the hold capped at 120", AQ, "static let failedClimbWithin = 10, holdMax = 60", "static let failedClimbWithin = 10, holdMax = 120"),
    ("AQ19 a climb fails within 9 s", AQ, "static let failedClimbWithin = 10, holdMax = 60", "static let failedClimbWithin = 9, holdMax = 60"),
    ("AQ20 a climb fails within 11 s", AQ, "static let failedClimbWithin = 10, holdMax = 60", "static let failedClimbWithin = 11, holdMax = 60"),
    ("AQ21 any step counts as a climb", AQ, "if climbedHere && secondsAtRung <= Self.failedClimbWithin", "if secondsAtRung <= Self.failedClimbWithin"),
    ("AQ22 a climb never known", AQ, "climbedHere = running == climbingTo", "climbedHere = false"),
    ("AQ23 every step a climb", AQ, "climbingTo = target > from ? target : nil", "climbingTo = target"),
    ("AQ24 the seconds at a rung not counted", AQ, "        secondsAtRung += 1\n", ""),
    ("AQ52 a kept rung keeps its hold", AQ, "        if secondsAtRung >= Self.holdMax { climbNeeds[rung] = nil }\n", ""),
    ("AQ53 the hold cleared after 30 s", AQ, "if secondsAtRung >= Self.holdMax { climbNeeds[rung] = nil }", "if secondsAtRung >= Self.holdMax / 2 { climbNeeds[rung] = nil }"),
    ("AQ25 the hold ignored", AQ, "climbNeeds[rung] ?? LinkJudge.cleanToFine", "LinkJudge.cleanToFine"),
    ("AQ26 a short second does not end the clean run", AQ, "if LinkJudge.isShort(second) { track.cleanLoaded = 0 }", "if LinkJudge.isShort(second) { track.cleanLoaded += 0 }"),
    # Not blinding itself.
    ("AQ27 judged while a restart is pending", AQ, "        guard running == rung else { return nil }\n", ""),
    ("AQ28 the windows kept when the running rung changes", AQ, "            tracks = [:]\n            judgedAt = running", "            judgedAt = running"),
    ("AQ29 a device that left is kept", AQ, "        tracks = tracks.filter { seconds[$0.key] != nil }\n", ""),
    ("AQ30 the window never trimmed", AQ, "            if track.recent.count > LinkJudge.window { track.recent.removeFirst(track.recent.count - LinkJudge.window) }\n", ""),
    # Governance.
    ("AQ31 the home device ignored in governance", AQ, "Set(home.isEmpty ? Array(away.keys) : Array(home))", "Set(away.keys)"),
    ("AQ32 the away devices govern when any is home", AQ, "Set(home.isEmpty ? Array(away.keys) : Array(home))", "Set(away.filter { $0.value }.isEmpty ? Array(away.keys) : Array(away.filter { $0.value }.keys))"),
    ("AQ33 a climb needs only one clean device", AQ, "governing.allSatisfy({ (tracks[$0]?.cleanLoaded ?? 0) >= needs(up) })", "governing.contains(where: { (tracks[$0]?.cleanLoaded ?? 0) >= needs(up) })"),
    ("AQ34 a device not governing can be behind", AQ, "let behind = governing.filter { id in", "let behind = Set(tracks.keys).filter { id in"),
    ("AQ35 the highest target of the behind devices", AQ, "asks.min(by: { $0.target < $1.target })", "asks.max(by: { $0.target < $1.target })"),
    ("AQ36 a climb with no device governing", AQ, "i + 1 < ladder.count, !governing.isEmpty else { return nil }", "i + 1 < ladder.count else { return nil }"),
    ("AQ37 the step names no rate", AQ, "carriedKbps: LinkJudge.carriedKbps(of: tracks[lowest.id]?.recent ?? [])))", "carriedKbps: nil))"),
    # The lines.
    ("AQ38 a live line says lowering", AQ, '"lowered live"', '"lowering live"'),
    ("AQ39 a restart line says restarted", AQ, '"restarting"', '"restarted"'),
    ("AQ40 a clean line without its seconds", AQ, 'reason = "clean for \\(seconds) s"', 'reason = "clean"'),
    ("AQ41 a resolution not named across a change", AQ, "step.from.retina == step.to.retina\n", "true\n"),
    ("AQ42 the carried rate not named", AQ, 'reason = "the link to \\(device(id)) carried about \\(LinkJudge.mbps(kbps: carried)) Mbps"', 'reason = "frames withheld from \\(device(id)) in \\(LinkJudge.shortToBehind) of the last \\(LinkJudge.window) seconds"'),
    ("AQ43 the home start line without its place", AQ, '"Auto: starting at \\(title(rung)) at home;', '"Auto: starting at \\(title(rung));'),
]
caught = 0
for name, rel, old, new in MUTANTS:
    src = open(os.path.join(ROOT, rel)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, os.path.basename(rel)); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        args = [os.path.join(HERE, "build.sh"), ROOT, exe, mf if rel == AQ else "", mf if rel == LJ else ""]
        args = [a for a in args if a]
        if rel == LJ: args = [os.path.join(HERE, "build.sh"), ROOT, exe, os.path.join(ROOT, AQ), mf]
        subprocess.run(args, capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        except subprocess.TimeoutExpired:
            caught += 1; print(f"{name}: caught (timed out)"); continue
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
