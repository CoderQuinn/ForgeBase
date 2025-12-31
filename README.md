# ForgeBase

ForgeBase is a small foundational library providing reusable low-level
utilities and algorithms shared across Forge modules.

---

## Scope

ForgeBase contains:

- Pure utilities and value types
- Deterministic algorithms
- Numeric and byte-level helpers
- Small C helpers shared by Swift / ObjC / C

## IPv4 Conventions

All IPv4-related APIs use **network byte order (big-endian)**.

Example:

```swift
FBIPv4Parse.parseCIDR("192.168.1.0/24")

