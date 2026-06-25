// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SimplePomo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SimplePomo", targets: ["SimplePomo"])
    ],
    targets: [
        .executableTarget(
            name: "SimplePomo",
            path: "Sources/SimplePomo",
            resources: []
        )
    ]
)
