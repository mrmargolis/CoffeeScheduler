// swift-tools-version: 6.0

import PackageDescription

// The iOS app, built and installed with xtool (`xtool dev`). xtool packages the
// library product named in xtool.yml as the app. Logic that doesn't need the
// iOS SDK lives in the CoffeeCore package so it can be tested on Linux.
let package = Package(
    name: "CoffeeScheduler",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "CoffeeScheduler", targets: ["CoffeeScheduler"]),
    ],
    dependencies: [
        .package(path: "CoffeeCore"),
    ],
    targets: [
        .target(
            name: "CoffeeScheduler",
            dependencies: [
                .product(name: "CoffeeCore", package: "CoffeeCore"),
            ]
        ),
    ]
)
