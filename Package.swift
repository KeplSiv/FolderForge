// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FolderForge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FolderForge", targets: ["FolderForge"])
    ],
    targets: [
        .executableTarget(
            name: "FolderForge",
            path: "Sources/FolderForge"
        ),
        .testTarget(
            name: "FolderForgeTests",
            dependencies: ["FolderForge"],
            path: "Tests/FolderForgeTests"
        )
    ]
)
