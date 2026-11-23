#!/bin/bash
# usage: build.sh ROOT OUT [AutoQuality.swift override [LinkJudge.swift override]]
# Compiles Sources/SillHost/AutoQuality.swift and LinkJudge.swift (their `import StreamProtocol`
# stripped) with StreamProtocol's HostSettings.swift (QualityPreset) as one module.
ROOT=$1; OUT=$2; T=$(mktemp -d)
cp "$ROOT/Sources/StreamProtocol/HostSettings.swift" "$T/"
sed '/^import StreamProtocol$/d' "${3:-$ROOT/Sources/SillHost/AutoQuality.swift}" > "$T/AutoQuality.swift"
sed '/^import StreamProtocol$/d' "${4:-$ROOT/Sources/SillHost/LinkJudge.swift}" > "$T/LinkJudge.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error" ; rm -rf "$T"
