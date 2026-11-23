#!/bin/bash
# The guard on Auto's seam (docs/adaptive-quality-plan.md): `lowerBitrate(` only from StreamCoordinator+Auto.swift
# (and its definition), `autoRunning` assigned only inside `commitRunning`, `AutoQuality(` constructed only by the
# coordinator's Auto file, the auto-quality check and the pacing harness; the fixtures prove each rule fires.
#   Tests/checks/auto-seam/run.sh             scan the sources, then run the fixtures
#   Tests/checks/auto-seam/run.sh --mutants   one-line mutants of the guard; each must fail its fixtures
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/seam.py" "$root"
python3 "$here/seam.py" "$root" --selftest
