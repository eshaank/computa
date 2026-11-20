// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Computa",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ComputaCore", targets: ["ComputaCore"]),
        .executable(name: "computa-probe", targets: ["computa-probe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.4"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.13.1"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.5.0"),
    ],
    targets: [
        // The RPC client and everything else that has no UI, so it can be tested.
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
        // Phase 0 trial client: prints ticks streamed by the daemon.
        .executableTarget(
            name: "computa-probe",
            dependencies: ["ComputaCore"]
        ),
        .testTarget(
            name: "ComputaCoreTests",
            dependencies: ["ComputaCore"]
        ),
    ]
)
