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
production lines (77.01%). The current suite covers 498 of 506 production lines
(98.42%) with the local Apple Swift 6.3.3 toolchain. The 95.0% gate leaves
limited toolchain-attribution headroom without admitting the old baseline.

## Explicitly unsupported behavior

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
