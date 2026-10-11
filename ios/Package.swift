// swift-tools-version: 6.2

import PackageDescription

// A warning fails the build, so none pile up. Deprecations stay warnings: a
// new SDK shouldn't break the build before there's time to move off an API.
let strict: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
    .treatWarning("DeprecatedDeclaration", as: .warning),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

// The iOS app, built and installed with xtool (`xtool dev`). xtool packages the
// library product named in xtool.yml as the app. Logic that doesn't need the
// iOS SDK lives in the CoffeeCore package so it can be tested on Linux.
let package = Package(
    name: "CoffeeScheduler",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "CoffeeScheduler", targets: ["CoffeeScheduler"])
    ],
    dependencies: [
        .package(path: "CoffeeCore")
    ],
    targets: [
        .target(
            name: "CoffeeScheduler",
            dependencies: [
                .product(name: "CoffeeCore", package: "CoffeeCore")
            ],
            swiftSettings: strict
        ),
        // Renders each screen over sample data on an iOS Simulator; CI
        // uploads the images. Not part of the app xtool builds.
        .testTarget(
            name: "CoffeeSchedulerScreenshots",
            dependencies: [
                "CoffeeScheduler",
                .product(name: "CoffeeCore", package: "CoffeeCore"),
            ]
        ),
    ]
)
