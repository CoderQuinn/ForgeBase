# Changelog

All notable changes to this project will be documented in this file.

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
