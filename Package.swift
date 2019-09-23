// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "EPD",
    products: [
        .library(name: "EPD", targets: ["EPD"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-embedded/hardware", .branch("master")),
    ],
    targets: [
        .target(name: "EPD", dependencies: ["Hardware"]),
    ]
)
