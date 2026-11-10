// swift-tools-version:6.0
// SnackKit is everything in Snack that is not a view: the deck/1 format, the
// library the decks merge into, the scheduling, the lessons and their games, and
// the streak. It builds for macOS too, so `swift test` runs it on the Mac without
// a simulator.
import PackageDescription

let package = Package(
    name: "SnackKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SnackKit", targets: ["SnackKit"]),
    ],
    dependencies: [
        // FSRS-6 is on main only; the newest tag is still FSRS-5.
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs.git", revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9"),
    ],
    targets: [
        // swift-fsrs names its module, its class and its card type FSRS, FSRS and
        // Card, so it is wrapped here, where no other Card stands in the way.
        .target(name: "SnackFSRS", dependencies: [.product(name: "FSRS", package: "swift-fsrs")]),
        .target(name: "SnackKit", dependencies: ["SnackFSRS"]),
        .testTarget(name: "SnackKitTests", dependencies: ["SnackKit"]),
    ]
)
