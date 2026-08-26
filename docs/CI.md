# CI and coverage gate

ForgeBase uses one required macOS Swift package workflow for pull requests,
pushes to `main`, and manual runs. The workflow uses least-privilege read-only
repository permissions and cancels superseded runs for the same branch or pull
request.

The gate runs on the pinned `macos-15` GitHub-hosted image and prints the macOS,
Xcode, Swift, and LLVM coverage toolchain before resolving the package. It then
runs clean Debug and Release builds/tests and a separate instrumented Debug test
run for line coverage.

## Local validation

Run the same build and test sequence from the repository root:

```sh
swift package clean
swift package resolve
swift build --configuration debug
swift test --configuration debug

swift package clean
swift build --configuration release
swift test --configuration release
```

Run the exact coverage gate used by CI:

```sh
FORGEBASE_LINE_COVERAGE_MIN=95.0 ./Scripts/ci/check-swift-coverage.sh
```

The script owns a separate `.build/ci-coverage` scratch directory, runs all
tests with Swift code coverage, prints a per-file summary, and fails if total
production line coverage is below 95.0%.

## Coverage scope and baseline

Coverage is selected by explicit production roots under `Sources/ForgeBase`
and `Sources/ForgeBaseC`. Test sources and paths outside `Sources` are never
counted. `ForgeBaseC` currently has no executable statements, so LLVM reports
the instrumented `ForgeBase` Swift target only.

Before the boundary test expansion, canonical `main` covered 345 of 448
production lines (77.01%). The expanded suite covers 434 of 448 production
lines (96.88%) with the local Apple Swift 6.3.3 toolchain. The 95.0% gate leaves
limited toolchain-attribution headroom without admitting the old baseline.

## Deferred current-main regressions

This CI-only change intentionally does not modify production code or encode
known incorrect behavior as expected behavior:

- `import ForgeBaseC` fails because a C++ `LRUCache.h` is exposed through the C
  umbrella module.
- Materializing a slice backed by a `Data` value with a non-zero `startIndex`
  traps, and the public slice initializer does not validate its backing range.
- `udpChecksumEnabled: true` still emits a zero UDP checksum, and a payload one
  byte above the IPv4 maximum traps during `UInt16` conversion.

The first two regression tests should become active when the independent
foundation safety fix is rebased onto this gate. UDP checksum and oversize-input
behavior require a separate functional change; this suite tests disabled
checksum semantics and the maximum valid 65,507-byte UDP payload without
locking the current failures in place.

## Toolchain limitations

- The package imports Apple's `Network` framework, so the required workflow and
  coverage baseline are macOS-only; this first gate does not claim Linux support.
- The local coverage script requires SwiftPM code-coverage JSON support and
  Python 3.9 or newer. GitHub's pinned `macos-15` image supplies both.
- Swift compiler revisions can attribute a small number of lines differently.
  The required GitHub workflow is the authoritative result; its printed
  toolchain makes changes auditable.
