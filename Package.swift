// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "HapticNotifications",
    platforms: [.macOS("12.0")],
    products: [
        .executable(name: "HapticNotifications", targets: ["HapticNotifications"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "HapticNotifications"
        )
    ]
)
