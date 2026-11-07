// swift-tools-version: 6.0
// PlannerCore — platform-independent domain logic for the app.
// No UIKit/SwiftUI/ActivityKit imports live here, so everything in this package
// compiles and is unit-tested on Linux as well as Apple platforms.
import PackageDescription

let package = Package(
    name: "PlannerCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PlannerCore", targets: ["PlannerCore"]),
    ],
    targets: [
        .target(
            name: "PlannerCore",
            path: "Sources/PlannerCore"
        ),
        .testTarget(
            name: "PlannerCoreTests",
            dependencies: ["PlannerCore"],
            path: "Tests/PlannerCoreTests"
        ),
    ]
)
