#!/bin/bash
# AutoQuality (docs/adaptive-quality-plan.md): the rung Auto runs the stream at, from what the host did
# for each governing device each second: the ladder, the start, the cap, one rung down live, a climb by
# restart, the hold after a failed climb, governance across devices, the host's lines.
#   Tests/checks/auto-quality/run.sh             compile and run the check
#   Tests/checks/auto-quality/run.sh --mutants   one-line mutants of AutoQuality.swift and the LinkJudge
#                                                rules it shares; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
