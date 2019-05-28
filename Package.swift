// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "SwiftWebSocket",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "SwiftWebSocket",
            targets: ["SwiftWebSocket"]),
    ],
    targets: [
        .target(
            name: "SwiftWebSocket",
            path: "Source"),
        .testTarget(
            name: "Test",
            dependencies: ["SwiftWebSocket"],
            path: "Test"),
    ]
)
