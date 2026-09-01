# ForgeBase

<p align="center">
  <a href="README.md">English</a> |
  <strong>简体中文</strong>
</p>

ForgeBase 为 Forge 系列模块提供轻量级基础能力，包括底层工具、确定性算法以及适合网络编程的值类型。

### 功能

- 使用明确网络字节序语义的 IPv4 值类型（`FBIPv4`）
- CIDR 辅助能力：生成掩码、计算网络地址和判断地址归属
- 点分十进制 IPv4 字符串与 CIDR 字符串解析器
- 用于桥接 `IPv4Address` 的 Network.framework 辅助接口
- 基于 `Data` 的数据包缓冲区和切片，支持网络字节序整数访问
- UDP-over-IPv4 数据包构建器，以及 IPv4/UDP 头部视图
- 用于跨语言辅助能力的最小 C shim target（`ForgeBaseC`）

### 安装（SwiftPM）

将 ForgeBase 添加到 package dependencies：

```swift
dependencies: [
    .package(url: "https://github.com/CoderQuinn/ForgeBase.git", exact: "0.3.0"),
]
```

然后将 `ForgeBase` 添加到目标的 dependencies。

### 使用方式

将点分十进制 IPv4 字符串解析为网络字节序值类型：

```swift
import ForgeBase

let ip = FBIPv4Parse.parseDottedDecimal("8.8.8.8")
let asString = ip?.dottedDecimalString // "8.8.8.8"
```

处理 CIDR：

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

桥接 Network.framework 的 `IPv4Address`，同时保持清晰的字节序语义：

```swift
import Network

let ipv4 = FBIPv4(a: 10, b: 0, c: 0, d: 1)
let nwAddress = ipv4.asNetworkIPv4Address

if let nwAddress {
    let roundTrip = FBIPv4(nwAddress)
    assert(roundTrip == ipv4)
}
```

构建 UDP/IPv4 数据包并通过视图解析：

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
    // 无需复制即可访问头部字段和负载
    _ = (udpView.srcPort, udpView.dstPort, udpView.payload.materialize())
}
```

### 字节序约定

所有公开 IPv4 API 均使用**网络字节序（大端序）**。公开接口不得暴露主机字节序；需要显示或桥接时，请使用 `dottedDecimalString` 或 Network.framework 辅助接口。

### 缓冲区所有权与并发

`FBPacketBuffer` 是一个遵循 `Sendable` 的只读值语义合同。实现必须对负数、整数溢出或越界的读取与切片返回 `nil`。`slice` 可以共享不可变的写时复制存储；`materialize()` 必须返回当前可读窗口独立持有的 `Data` 快照。自定义缓冲区需要自行实现 `materialize()`；ForgeBase 不会再根据具体实现类型进行运行时分支。

两个基于 `Data` 的具体缓冲区按照可读字节内容实现 `Hashable`。对于 slice，窗口之外的 backing 字节及窗口在 backing storage 中的偏移不会参与相等判断或哈希，哈希复杂度为 O(n)。`FBPacketBuffer` existential、packet view 和 writer 刻意不实现 `Hashable`；需要与具体实现无关的 key 时，调用方应先显式 `materialize()` 为 `Data` 快照。

`FBIPPacketView.protocolNumberRaw` 会保留 IPv4 头部中真实的协议字节，`protocolNumber` 只用于便捷分类。UDP/IPv4 构造在负载过大或请求尚未支持的 checksum 模式时，会抛出结构化的 `FBUDPIPPacketBuilderError`，不再崩溃，也不会静默生成零 checksum 来伪装成功。

当 DNS 名称不是已验证的可信输入时，数据包构建器应调用 `try writer.writeDNSName(name)`。writer 会校验每个 label 和完整 wire encoding 的长度，接受根域名与单个绝对域名尾点，并在失败时保持原状态不变。兼容入口 `name(_:)` 对相同的非法输入返回 `false`。

### 开发

- Swift 5.9+
- 测试位于 `Tests/ForgeBaseTests`，覆盖 IPv4 解析、CIDR 工具、数据包缓冲区以及 UDP/IPv4 构建与解析
- CI 和本地可复现的覆盖率门禁参见 [`docs/CI.md`](docs/CI.md)
- 1.0 前的兼容性与发布约定参见 [`docs/VERSIONING.md`](docs/VERSIONING.md)
