# ForgeBase

<p align="center">
  <strong>English</strong> |
  <a href="README.zh-CN.md">简体中文</a>
</p>

Lightweight foundations shared across Forge modules: low-level utilities,
deterministic algorithms, and network-friendly value types.

### Features
- IPv4 value type (`FBIPv4`) with explicit network-byte-order semantics
- CIDR helpers: mask generation, network base calculation, containment checks
- Parsers for dotted-decimal IPv4 strings and CIDR strings
- Network.framework conveniences for bridging to `IPv4Address`
- Packet buffers and slices over `Data` with network-order integer access
- UDP-over-IPv4 packet builder + views for IPv4/UDP headers
- Minimal C shim target (`ForgeBaseC`) for cross-language helpers

### Installation (SwiftPM)

Add ForgeBase to your package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/CoderQuinn/ForgeBase.git", exact: "0.3.0"),
]
```

Then add `ForgeBase` to your target dependencies.

### Usage

Parse dotted-decimal IPv4 strings into a network-order value type:

```swift
import ForgeBase

let ip = FBIPv4Parse.parseDottedDecimal("8.8.8.8")
let asString = ip?.dottedDecimalString // "8.8.8.8"
```

Work with CIDR notation:

```swift
if let (networkBE, prefix) = FBIPv4Parse.parseCIDR("192.168.1.0/24") {
    let contains = FBIPv4CIDR.contains(
        addressBE: FBIPv4(a: 192, b: 168, c: 1, d: 42).beValue,
        networkBE: networkBE,
        prefixLength: prefix
    )
    // contains == true
}
```

Bridge to Network.framework `IPv4Address` without losing byte-order clarity:

```swift
import Network

let ipv4 = FBIPv4(a: 10, b: 0, c: 0, d: 1)
let nwAddress = ipv4.asNetworkIPv4Address

if let nwAddress {
    let roundTrip = FBIPv4(nwAddress)
    assert(roundTrip == ipv4)
}
```

Build UDP/IPv4 packets and parse them back into views:

```swift
import Network

let payload = Data([0xDE, 0xAD])
let packet = try FBUDPIPPacketBuilder.buildUDPIPv4(
    srcIP: IPv4Address("10.0.0.1")!,
    dstIP: IPv4Address("10.0.0.2")!,
    srcPort: 12345,
    dstPort: 80,
    payload: payload
)

if let ipView = FBIPPacketView(buffer: FBDataPacketBuffer(packet)),
   let udpView = FBUDPView(ip: ipView) {
    // Access header fields and payload without copies
    _ = (udpView.srcPort, udpView.dstPort, udpView.payload.materialize())
}
```

### Byte-Order Convention

All public IPv4 APIs use **network byte order (big-endian)**. Host byte order
must not surface in public signatures; use `dottedDecimalString` or the
Network.framework helpers for presentation and bridging.

### Buffer Ownership and Concurrency

`FBPacketBuffer` is a `Sendable` read-only value contract. Implementations must
return `nil` for negative, overflowing, or out-of-bounds reads and slices.
`slice` may share immutable copy-on-write storage, while `materialize()` returns
an independently owned `Data` snapshot of the readable window. Custom buffer
implementations provide their own `materialize()` witness; ForgeBase never
switches on concrete conformer types.

`withUnsafeReadableBytes` borrows only the logical readable window, synchronously;
the pointer must not escape its closure. Contiguous buffers avoid preliminary
materialization; legacy conformers use the compatible `materialize()` default.
`buildUDPIPv4(..., payloadBuffer: window)` still returns owned `Data` and copies
the payload into that result. This is not an end-to-end zero-copy contract.
To roll a consumer back to the compatible copy path, pass
`payload: window.materialize()` instead. Keep the previous exact Git revision in
the consumer lockfile for a dependency rollback; these tools do not change pins
or publish a version. The older v0.3.0 lacks the borrowed API, so code using it
must also switch to the Data call when restoring that pin.

The two concrete `Data`-backed buffers are `Hashable` by readable byte content.
For a slice, backing bytes outside its readable window and its backing offset do
not participate in equality or hashing. Hashing is O(n). The
`FBPacketBuffer` existential, packet views, and writers deliberately do not
conform to `Hashable`; callers that need representation-neutral keys should
materialize a `Data` snapshot explicitly.

`FBIPPacketView.protocolNumberRaw` preserves the exact IPv4 protocol byte;
`protocolNumber` is only a convenience classification. UDP/IPv4 construction
throws a structured `FBUDPIPPacketBuilderError` for oversized payloads or a
requested checksum mode that is not yet supported, rather than trapping or
silently emitting a zero checksum.

DNS packet builders should use `try writer.writeDNSName(name)` when the name is
not already trusted. The writer validates label and full wire lengths, accepts
the root and one trailing absolute-name dot, and leaves its state unchanged on
failure. The compatibility `name(_:)` entry point returns `false` for the same
invalid inputs.

### Development

- Swift 5.9+
- Tests live under `Tests/ForgeBaseTests` (IPv4 parsing, CIDR utilities, packet buffers, UDP/IPv4 build/parse)
- CI and the locally reproducible coverage gate are documented in [`docs/CI.md`](docs/CI.md)
- The pre-1.0 compatibility and release contract is documented in [`docs/VERSIONING.md`](docs/VERSIONING.md)

### Reproducible UDP builder checks

Run correctness first (the checkout must be clean):

```sh
bash Scripts/benchmark-udp-builder.sh --self-test --output /tmp/udp-correctness.json
FORGEBASE_BENCHMARK_TEST_RESULT=/tmp/udp-correctness.json python3 Scripts/test-udp-builder-benchmark.py
python3 Scripts/test-udp-builder-consumer.py --revision "$(git rev-parse HEAD)" --output /tmp/udp-consumer.json
```

The consumer requires that exact revision to be available at the public Git URL.
The benchmark requires full history containing its exact historical baseline;
for a shallow clone, fetch history before running. See [CI documentation](docs/CI.md)
for result provenance, instrumentation and serialized native measurement.
