#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"
baseline=d5a75c766871436619b8fb431567b7d7ebf2d839
scratch="$(mktemp -d "${TMPDIR:-/tmp}/forge-udp-benchmark.XXXXXX")"

# Keep both implementations in separate optimized modules. The fixture is the
# actual reviewed PR head, renamed only to avoid a module/type name collision.
git show "${baseline}:Sources/ForgeBase/Net/Packets/UDPIPPacketBuilder.swift" \
    | sed 's/FBUDPIPPacketBuilder/BaselineUDPIPPacketBuilder/g' > "$scratch/Baseline.swift"
swift build -c release
build_path="$(swift build -c release --show-bin-path)"
swiftc -O -parse-as-library -module-name Baseline \
    -emit-module -emit-module-path "$scratch/Baseline.swiftmodule" \
    -emit-object "$scratch/Baseline.swift" -o "$scratch/Baseline.o"
swiftc -O -I "$scratch" -I "$build_path/Modules" -I "$build_path/ForgeBaseC.build" \
    Benchmarks/UDPIPPacketBuilder/main.swift "$scratch/Baseline.o" \
    "$build_path/ForgeBase.build/"*.o "$build_path/ForgeBaseC.build/include/forge_base.c.o" \
    -o "$scratch/benchmark"
swift --version
printf 'baseline=%s\nretained_benchmark=%s\n' "$baseline" "$scratch"
"$scratch/benchmark"
