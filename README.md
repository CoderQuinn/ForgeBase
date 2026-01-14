## ForgeBase

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
    .package(url: "https://github.com/CoderQuinn/ForgeBase.git", from: "0.2.0"),
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
let packet = FBUDPIPPacketBuilder.buildUDPIPv4(
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

### Development

- Swift 5.9+
- Tests live under `Tests/ForgeBaseTests` (IPv4 parsing, CIDR utilities, packet buffers, UDP/IPv4 build/parse)
