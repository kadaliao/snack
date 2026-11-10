// swift-tools-version:6.0
// SnackKit is everything in Snack that is not a view: the deck/1 format, the
// library the decks merge into, and later the scheduling and the games. It
// builds for macOS too, so `swift test` runs it on the Mac without a simulator.
import PackageDescription

let package = Package(
    name: "SnackKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SnackKit", targets: ["SnackKit"]),
    ],
    targets: [
        .target(name: "SnackKit"),
        .testTarget(name: "SnackKitTests", dependencies: ["SnackKit"]),
    ]
)
