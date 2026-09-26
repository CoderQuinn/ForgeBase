# CI and coverage gate

ForgeBase uses one required macOS Swift package workflow for pull requests,
pushes to `main`, and manual runs. The workflow uses least-privilege read-only
repository permissions and cancels superseded runs for the same branch or pull
request.

The gate runs on the pinned `macos-15` GitHub-hosted image and prints the macOS,
Xcode, Swift, and LLVM coverage toolchain before resolving the package. It then
runs a non-mutating strict `swift-format` lint, clean Debug and Release
builds/tests, and a separate instrumented Debug test run for line coverage.

## Local validation

Run the same build and test sequence from the repository root:

```sh
swift package clean
swift package resolve
./Scripts/ci/check-swift-format.sh
swift build --configuration debug -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test --configuration debug -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

swift package clean
swift build --configuration release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test --configuration release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Run the exact coverage gate used by CI:

```sh
FORGEBASE_LINE_COVERAGE_MIN=95.0 ./Scripts/ci/check-swift-coverage.sh
```

The script owns a separate `.build/ci-coverage` scratch directory, runs all
tests with Swift code coverage, prints a per-file summary, and fails if total
production line coverage is below 95.0%.

The format script runs `swift-format lint --strict` over `Package.swift`,
`Sources`, and `Tests`; it never rewrites files and permits no diagnostics.
Debug and Release builds/tests enable complete strict-concurrency checking and
treat every compiler warning as an error.

## Coverage scope and baseline

Coverage is selected by explicit production roots under `Sources/ForgeBase`
and `Sources/ForgeBaseC`. Test sources and paths outside `Sources` are never
counted. `ForgeBaseC` currently has no executable statements, so LLVM reports
the instrumented `ForgeBase` Swift target only.

Before the boundary test expansion, canonical `main` covered 345 of 448
production lines (77.01%). Before scoped-byte work the suite covered 498 of 506
production lines (98.42%); the current 53 tests cover 546 of 554 (98.56%) with
the local Apple Swift 6.3.3 toolchain. The 95.0% gate leaves
limited toolchain-attribution headroom without admitting the old baseline.

## Scoped readable bytes and packet assembly

`FBPacketBuffer.withUnsafeReadableBytes` borrows only the logical readable window
for a synchronous closure. Pointers must not escape that closure. The default
protocol implementation uses `materialize()` for legacy conformers; Data-backed
buffers override it without materializing their readable window. This does not
promise end-to-end zero-copy or protect against externally mutated borrowed C memory.

Slice equality and hashing now inspect that window directly. Hashes remain
process-randomized, not stable digests. The IPv4 UDP builder writes headers and
payload into its final-sized Data, removing the intermediate UDP Data. It still copies
the payload into the owned result; allocator counts and throughput need benchmarks.

`ReadableBytesTests` covers existential/default dispatch, nested slices, nonzero
Data indices, empty windows, throwing closures, equality/hash, and COW isolation.
The packet boundary suite additionally checks indexed payloads through 65,507 bytes.

### Buffer payload overload (local candidate, not released)

`buildUDPIPv4(srcIP:dstIP:srcPort:dstPort:payloadBuffer:ttl:udpChecksumEnabled:)`
accepts an `FBPacketBuffer` existential. It reads `readableBytes` once, borrows
the logical window once, and copies that window into the final owned packet.
The original `payload: Data` API delegates to the same core. Data-backed windows
avoid a preliminary materialization; legacy conformers retain the default
`materialize()` fallback. This is not an end-to-end zero-copy guarantee.

Validation order is negative declared length (`invalidPayloadLength`), declared
length above 65,507 (`payloadTooLarge`), enabled UDP checksum
(`udpChecksumUnsupported`), then borrowed count mismatch
(`payloadLengthMismatch(declared:actual:)`). Invalid declarations and unsupported
checksums do not borrow storage. No length conversion or packet allocation occurs
before successful validation. Empty windows, nonzero Data indices, nested slices,
TTL 0 through 255, and the maximum payload retain their semantics. The new public
error cases require consideration by downstream exhaustive switches.

Conformers must invoke the closure exactly once with a valid pointer to stable
bytes for its duration. Count validation cannot validate arbitrary foreign
pointers or freeze externally mutated `Data(bytesNoCopy:)` memory. Such storage
requires an owner/immutability contract or an explicit copy by the caller.

`UDPIPPacketBufferTests` verifies contiguous borrow versus legacy materialization
with synchronized call counters, both mismatch directions (including empty and
oversized actual storage), Int.min/Int.max declarations, error precedence,
output/source mutation isolation, byte equality with the Data API, and an
independent end-around-carry IPv4 checksum oracle.

Local validation on Apple Swift 6.3.3 / Xcode 26.6: 53 Debug and Release tests,
complete strict concurrency and Swift warnings-as-errors; strict package format
lint; generic iOS 13 arm64 compilation. The instrumented Debug run includes
`-Xcc -fprofile-instr-generate -Xcc -fcoverage-mapping`. The shared foundation
JSON/LCOV audit against fixed parent
`d5a75c766871436619b8fb431567b7d7ebf2d839` reports 546/554 production lines
(98.56%) and 67/67 changed executable lines (100%), including prior uncommitted
scoped-byte changes. ForgeBaseC remains in scope with no executable statements.
This local evidence does not establish remote CI, device execution, performance,
or joint component acceptance.

### Local UDP assembly microbenchmark

Run `bash Scripts/benchmark-udp-builder.sh`. This builds the current release
module and the real `d5a75c7` builder in a separate optimized baseline module,
checks byte equality, warms up both implementations, alternates execution order,
and reports the median of seven samples. Results are consumed through a checksum
sink. The baseline source and binaries are retained in the printed temporary path.

On Apple Silicon / Swift 6.3.3, one local run reported (nanoseconds per packet):

| Payload bytes | Original PR baseline | Candidate |
| ---: | ---: | ---: |
| 0 | 635 | 103 |
| 64 | 805 | 105 |
| 1472 | 855 | 135 |
| 4096 | 929 | 230 |
| 65507 | 5068 | 2501 |

This compares the Data entry point, including assembly and result lifetime, not
transport throughput. It does not measure allocation counts, RSS, HEV parity or
device performance. The final owned Data is zero initialized before header writes
and the payload copy; this is not an uninitialized or zero-copy allocation claim.

## Explicitly unsupported behavior (unchanged)

UDP checksum generation is not implemented. Requesting it throws
`FBUDPIPPacketBuilderError.udpChecksumUnsupported`. Payloads above the maximum
65,507 bytes throw a structured size error. The suite covers both failures and
the maximum valid payload without relying on a process trap.

## Toolchain limitations

- The package imports Apple's `Network` framework, so the required workflow and
  coverage baseline are macOS-only; this first gate does not claim Linux support.
- The local coverage script requires SwiftPM code-coverage JSON support and
  Python 3.9 or newer. GitHub's pinned `macos-15` image supplies both.
- Swift compiler revisions can attribute a small number of lines differently.
  The required GitHub workflow is the authoritative result; its printed
  toolchain makes changes auditable.
