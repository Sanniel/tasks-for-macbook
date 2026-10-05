// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TasksKit",
    platforms: [.macOS(.v14)],
    products: [
        // Pure Swift: models, repository protocol and business logic. No Apple-only
        // frameworks beyond Foundation, so it documents what a port must implement.
        .library(name: "TasksCore", targets: ["TasksCore"]),
        // SQLite (GRDB) implementation of TaskRepository, stored in the App Group container.
        .library(name: "TasksStore", targets: ["TasksStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "TasksCore"),
        .target(
            name: "TasksStore",
            dependencies: ["TasksCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "TasksCoreTests", dependencies: ["TasksCore"]),
        .testTarget(name: "TasksStoreTests", dependencies: ["TasksStore"]),
    ]
)
