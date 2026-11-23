#!/usr/bin/env python3
"""The guard on Auto's seam (docs/adaptive-quality-plan.md, "codebase-design check"): who may move what
runs, and who may make the policy. Three declared rules; each failure prints the file and line, the rule
and a `fix:` line. `--selftest` runs the fixtures: every rule fires on a file that breaks it and stays
quiet on one that keeps it, and every allow-list names files that exist.

    seam.py ROOT              scan ROOT's Swift sources
    seam.py ROOT --selftest   the fixtures (needs no repository: it builds its own trees)

To widen a rule, edit RULES below in the same commit as the code that needs it, and say why in the
commit; never skip, silence or delete the check (AGENTS.md, "Guard every shared seam")."""
import os, re, sys, tempfile

COORDINATOR = "Sources/SillHost/StreamCoordinator+Auto.swift"
# id, what it forbids (a regex on a line with its comment removed), where it may appear, `within`: the one
# function it may appear in (None: anywhere in the allowed files), the scanned folders, and the fix text.
RULES = [
    dict(id="lower-live", pattern=r"\blowerBitrate\(", files=[COORDINATOR, "Sources/SillHost/HEVCEncoder.swift"],
         within=None, scan=["Sources", "Scripts", "iOSClient"],
         fix="move the call into StreamCoordinator.lowerLive (StreamCoordinator+Auto.swift): a live lower must commit what runs (commitRunning) in the same step"),
    dict(id="auto-running", pattern=r"\bautoRunning\s*=[^=]", files=[COORDINATOR],
         within="commitRunning", scan=["Sources"],
         fix="call commitRunning(_:streaming:) instead of assigning autoRunning: it moves what runs, judges the links and publishes in one place"),
    dict(id="auto-construct", pattern=r"\bAutoQuality\(",
         files=[COORDINATOR, "Tests/checks/auto-quality/main.swift"],
         dirs=["Scripts/pacing"], within=None, scan=["Sources", "Scripts", "Tests", "iOSClient"],
         fix="ask AutoQuality.start(place:retina:) for a start rung, or let StreamCoordinator.syncAuto make the policy; only the coordinator, the auto-quality check and the pacing harness construct one"),
]

def strip(line):
    return re.sub(r"//.*$", "", line)

def swift_files(root, folders):
    for folder in folders:
        for base, _, names in os.walk(os.path.join(root, folder)):
            for n in sorted(names):
                if n.endswith(".swift"):
                    yield os.path.relpath(os.path.join(base, n), root)

def allowed(rule, rel):
    return rel in rule["files"] or any(rel.startswith(d + "/") for d in rule.get("dirs", []))

def scan(root):
    found = []
    for rule in RULES:
        for rel in swift_files(root, rule["scan"]):
            func = None
            for number, raw in enumerate(open(os.path.join(root, rel), errors="replace").read().split("\n"), 1):
                line = strip(raw)
                m = re.search(r"\bfunc\s+(\w+)", line)
                if m: func = m.group(1)
                if not re.search(rule["pattern"], line): continue
                if allowed(rule, rel) and (rule["within"] is None or func == rule["within"]): continue
                found.append(f"{rel}:{number}: rule {rule['id']}: {raw.strip()}\n  fix: {rule['fix']}")
    return found

def missing(root):
    """Allow-list entries that name no file: a rule's list that has rotted."""
    out = []
    for rule in RULES:
        for rel in rule["files"]:
            if not os.path.exists(os.path.join(root, rel)): out.append(f"rule {rule['id']}: allowed file {rel} does not exist")
        for d in rule.get("dirs", []):
            if not os.path.isdir(os.path.join(root, d)): out.append(f"rule {rule['id']}: allowed folder {d} does not exist")
    return out

def selftest(root):
    failures = []
    def tree(files):
        t = tempfile.mkdtemp()
        for rel, text in files.items():
            os.makedirs(os.path.dirname(os.path.join(t, rel)), exist_ok=True)
            open(os.path.join(t, rel), "w").write(text)
        return t
    def fires(rule, files, want=True):
        hits = [f for f in scan(tree(files)) if f"rule {rule}:" in f]
        if bool(hits) != want: failures.append(f"{rule}: {'did not fire on' if want else 'fired on'} {sorted(files)}")
        if want and hits and "fix:" not in hits[0]: failures.append(f"{rule}: no fix line")
    other = "Sources/SillHost/StreamServer.swift"
    fires("lower-live", {other: "encoder.lowerBitrate(to: 1)\n"})
    fires("lower-live", {"Scripts/pacing/main.swift": "e.lowerBitrate(to: 1)\n"})
    fires("lower-live", {COORDINATOR: "encoder?.lowerBitrate(to: 1)\n"}, want=False)
    fires("lower-live", {"Sources/SillHost/HEVCEncoder.swift": "    func lowerBitrate(to bps: Int) -> Bool {\n"}, want=False)
    fires("lower-live", {other: "// lowerBitrate( is the coordinator's\n"}, want=False)
    fires("auto-running", {other: "autoRunning = nil\n"})
    fires("auto-running", {COORDINATOR: "func lowerLive() {\n    autoRunning = rung\n}\n"})
    fires("auto-running", {COORDINATOR: "func commitRunning() {\n    autoRunning = rung\n}\n"}, want=False)
    fires("auto-running", {COORDINATOR: "func commitRunning() {\n    if autoRunning == rung {}\n}\n"}, want=False)
    fires("auto-construct", {"Sources/SillHost/HostConfig.swift": "let a = AutoQuality(place: .home, retina: true)\n"})
    fires("auto-construct", {"Tests/checks/other/main.swift": "var q = AutoQuality(place: .home, retina: true)\n"})
    fires("auto-construct", {COORDINATOR: "let a = AutoQuality(place: .home, retina: true)\n"}, want=False)
    fires("auto-construct", {"Scripts/pacing/main.swift": "let a = AutoQuality(place: .home, retina: true)\n"}, want=False)
    fires("auto-construct", {"Tests/checks/auto-quality/main.swift": "let a = AutoQuality(place: .home, retina: true)\n"}, want=False)
    if not missing(tree({})): failures.append("the allow-list check did not see a tree without the allowed files")
    failures += missing(root)
    return failures

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(__doc__)
    root = sys.argv[1]
    problems = selftest(root) if "--selftest" in sys.argv else scan(root) + missing(root)
    for p in problems: print(p)
    print("auto-seam: all passed" if not problems else f"auto-seam: {len(problems)} FAILED")
    sys.exit(1 if problems else 0)
