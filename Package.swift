// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Modaliser",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/objecthub/swift-lispkit.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "Modaliser",
            dependencies: [
                .product(name: "LispKit", package: "swift-lispkit"),
            ],
            path: "Sources/Modaliser"
        ),
        .testTarget(
            name: "ModaliserTests",
            dependencies: ["Modaliser"],
            path: "Tests/ModaliserTests"
        ),
    ]
)
