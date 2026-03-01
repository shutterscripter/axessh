// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AxeSSH",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AxeSSH", targets: ["AxeSSH"])
    ],
    targets: [
        .executableTarget(
            name: "AxeSSH",
            path: "Sources/AxeSSH",
            resources: [.process("Resources")]
        )
    ]
)
