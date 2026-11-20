// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Computa",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ComputaCore", targets: ["ComputaCore"]),
        .library(name: "ComputaUI", targets: ["ComputaUI"]),
        .executable(name: "Computa", targets: ["Computa"]),
        .executable(name: "computa-probe", targets: ["computa-probe"]),
        .executable(name: "computa-snapshot", targets: ["computa-snapshot"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.4"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.13.1"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.5.0"),
    ],
    targets: [
        // The RPC client, domain models, the store and formatting: everything with no UI,
        // so it can be tested.
        .target(
            name: "ComputaCore",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ],
            plugins: [
                .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf")
            ]
        ),
        // Theme, rings, popover and windows, driven by plain values.
        .target(
            name: "ComputaUI",
            dependencies: ["ComputaCore"]
        ),
        // The menu bar app.
        .executableTarget(
            name: "Computa",
            dependencies: ["ComputaCore", "ComputaUI"]
        ),
        // Prints what a running daemon reports.
        .executableTarget(
            name: "computa-probe",
            dependencies: ["ComputaCore"]
        ),
        // Renders the UI offscreen to PNG files, for checking it without a screen.
        .executableTarget(
            name: "computa-snapshot",
            dependencies: ["ComputaCore", "ComputaUI"]
        ),
        .testTarget(
            name: "ComputaCoreTests",
            dependencies: ["ComputaCore"]
        ),
        .testTarget(
            name: "ComputaUITests",
            dependencies: ["ComputaCore", "ComputaUI"]
        ),
    ]
)
