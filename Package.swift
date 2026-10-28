// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1"),
    ],
    targets: [
        .target(name: "HarborCore"),
        .target(
            name: "HarborHost",
            dependencies: ["HarborCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .executableTarget(name: "harbor-host", dependencies: ["HarborCore", "HarborHost"]),
        .executableTarget(
            name: "Harbor",
            dependencies: ["HarborCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"]),
        .testTarget(name: "HarborHostTests", dependencies: ["HarborCore", "HarborHost"]),
    ]
)
