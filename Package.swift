// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ApSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ApSwitcher",
            targets: ["ApSwitcher"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ApSwitcher"
        ),
        .testTarget(
            name: "ApSwitcherTests",
            dependencies: ["ApSwitcher"]
        )
    ]
)
