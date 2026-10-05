// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyPathObservation",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KeyPathObservation", targets: ["KeyPathObservation"]),
    ],
    targets: [
        .target(name: "KeyPathObservation"),
        .testTarget(name: "KeyPathObservationTests", dependencies: ["KeyPathObservation"]),
    ]
)
