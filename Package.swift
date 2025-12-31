// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForgeBase",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "ForgeBase", targets: ["ForgeBase"]),
        .library(name: "ForgeBaseC", targets: ["ForgeBaseC"]),
    ],
    targets: [
        .target(
            name: "ForgeBase",
            dependencies: ["ForgeBaseC"],
            path: "Sources/ForgeBase"
        ),
        .target(
            name: "ForgeBaseC",
            path: "Sources/ForgeBaseC",
            publicHeadersPath: "include",
            cSettings: [
                .define("FORGEBASE", to: "1")
            ]
        ),
        .testTarget(
            name: "ForgeBaseTests",
            dependencies: ["ForgeBase"],
            path: "Tests/ForgeBaseTests"
        ),
    ]
)
