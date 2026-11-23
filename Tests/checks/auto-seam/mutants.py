"""Mutants of the seam guard (seam.py): each weakens one rule or one fixture's reach, runs the fixtures and
must make them fail. usage: mutants.py ROOT"""
import os, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
SEAM = os.path.join(HERE, "seam.py")
MUTANTS = [
    ("S1 lowerBitrate allowed anywhere", 'pattern=r"\\blowerBitrate\\("', 'pattern=r"\\blowerBitrateNever\\("'),
    ("S2 the encoder's file not allowed", 'files=[COORDINATOR, "Sources/SillHost/HEVCEncoder.swift"]', 'files=[COORDINATOR]'),
    ("S3 autoRunning allowed in any function", 'within="commitRunning"', 'within=None'),
    ("S4 autoRunning assigned anywhere in the file", 'if allowed(rule, rel) and (rule["within"] is None or func == rule["within"]): continue', 'if allowed(rule, rel): continue'),
    ("S5 the pacing harness not allowed to construct", 'dirs=["Scripts/pacing"], ', ''),
    ("S6 anyone may construct", 'pattern=r"\\bAutoQuality\\("', 'pattern=r"\\bAutoQualityNever\\("'),
    ("S7 comments count", 'return re.sub(r"//.*$", "", line)', 'return line'),
    ("S8 an assignment pattern that misses", 'pattern=r"\\bautoRunning\\s*=[^=]"', 'pattern=r"\\bautoRunning\\s*:="'),
    ("S9 the failure prints no fix line", 'f"{rel}:{number}: rule {rule[\'id\']}: {raw.strip()}\\n  fix: {rule[\'fix\']}"', 'f"{rel}:{number}: rule {rule[\'id\']}: {raw.strip()}"'),
    ("S10 allow-lists not checked for rot", "def missing(root):", "def missing(root):\n    return []"),
    ("S11 Tests not scanned for construction", 'scan=["Sources", "Scripts", "Tests", "iOSClient"]', 'scan=["Sources", "Scripts", "iOSClient"]'),
]
src = open(SEAM).read(); caught = 0
for name, old, new in MUTANTS:
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        p = os.path.join(t, "seam.py"); open(p, "w").write(src.replace(old, new, 1))
        r = subprocess.run([sys.executable, p, ROOT, "--selftest"], capture_output=True, text=True)
        if r.returncode != 0:
            caught += 1; print(f"{name}: caught ({(r.stdout.splitlines() or ['exit'])[0][:100]})")
        else: print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
