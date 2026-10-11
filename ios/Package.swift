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
        .library(name: "CoffeeScheduler", targets: ["CoffeeScheduler"]),
        // The widget extension; xtool.yml lists it under `extensions`.
        .library(name: "CoffeeWidget", targets: ["CoffeeWidget"]),
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
        .target(
            name: "CoffeeWidget",
            dependencies: [
                .product(name: "CoffeeCore", package: "CoffeeCore")
            ],
            swiftSettings: strict,
            // An extension starts at NSExtensionMain, so nothing refers to
            // the widget's own `main` and the linker would leave all of its
            // code out of the binary. Ask for the symbol to keep it in.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]
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
