# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.3.0] - 2026-08-28

### Breaking

- `FBPacketBuffer` now refines `Sendable` and requires each conformer to provide
  its own `materialize()` snapshot implementation.
- `FBUDPIPPacketBuilder.buildUDPIPv4` now throws
  `FBUDPIPPacketBuilderError` for oversized payloads and unsupported checksum
  requests instead of trapping or silently emitting an invalid contract.

### Added

- Added an explicit Apache-2.0 repository license.
- Added overflow and integer-extreme boundary coverage for packet buffers and
  packet views.
- Added `FBIPPacketView.protocolNumberRaw` so callers can preserve unknown IPv4
  protocol values.
- Added content-based `Hashable` semantics for the two concrete `Data`-backed
  packet buffers.
- Added strict concurrency, strict formatting, and 95% production coverage
  gates to CI.

### Changed

- Invalid, overflowing, and out-of-bounds public packet-buffer ranges now
  return `nil` without evaluating an overflowing sum.
- Packet-buffer ownership, snapshot, equality, hashing, and concurrency
  contracts are now explicit in the English and Chinese documentation.

### Fixed

- Restored Swift importability of the `ForgeBaseC` product by removing an unused C++ header from its public C umbrella
- Added overflow-safe invariant validation to the public `FBDataSlicePacketBuffer` initializer
- Fixed packet slice materialization for `Data` values whose `startIndex` is not zero

## [0.2.1] - 2026-02-04

### Fixed

- Preallocated `Data` capacity in `FBPacketBufferWriter` to avoid repeated
  allocation while emitting packet bytes.

## [0.2.0] - 2026-01-14
### Added
- IPv4 value type (`FBIPv4`) with explicit network-byte-order semantics
- CIDR helpers for netmask calculation, network base derivation, and containment checks
- Parsers for dotted-decimal IPv4 strings and CIDR strings
- Network.framework convenience APIs for bridging to `IPv4Address`
- Packet buffer abstractions over `Data`, plus UDP-over-IPv4 builder and views
- Fixed `FBPacketBufferWriter` endianness for emitted integers
- Improved README with usage and installation guidance
- XCTest coverage for IPv4 parsing/CIDR, packet buffers/writer, and UDP/IPv4 build-parse

## [0.1.0] - 2025-12-31
- Initial scaffolding
