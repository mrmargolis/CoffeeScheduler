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

// Platform-independent logic for the iOS app: the scheduler, the BeanConqueror
// import parser, and the SQLite store. Kept in its own package so it builds and
// tests on Linux with a plain `swift test`, without the iOS SDK.
let package = Package(
    name: "CoffeeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CoffeeCore", targets: ["CoffeeCore"])
    ],
    dependencies: [
        // Pinned exactly: a dependency upgrade should be a deliberate change.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        // Apple platforms ship an `SQLite3` module; Linux needs the system library.
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "CoffeeCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "CoffeeCoreTests",
            dependencies: [
                "CoffeeCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            swiftSettings: strict
        ),
    ]
)
