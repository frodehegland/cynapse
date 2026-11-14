// swift-tools-version: 6.0
//
// Cynapse: see how an AI model behaves, and check it yourself.
//
// ModelCheck is the engine: the question bank, the runner, the scoring and
// the profile. It depends only on Foundation and swift-crypto, so anyone can
// build it and re-run a check, on a Mac or on Linux.

import PackageDescription

let package = Package(
    name: "Cynapse",
    platforms: [.macOS(.v14), .iOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "ModelCheck", targets: ["ModelCheck"]),
        .library(name: "ModelCheckStubs", targets: ["ModelCheckStubs"]),
        .library(name: "ModelCheckModels", targets: ["ModelCheckModels"]),
        .executable(name: "cynapse", targets: ["cynapse"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "ModelCheck",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Deliberately simple fake models — honest ones, and ones built to
        // cheat — that the check must tell apart. Used by the tests and by
        // `cynapse demo`.
        .target(
            name: "ModelCheckStubs",
            dependencies: ["ModelCheck"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Cloud models (with the person's own key) and Apple's on-device
        // model. Local MLX models are connected in the app, which Xcode
        // builds with Metal.
        .target(
            name: "ModelCheckModels",
            dependencies: ["ModelCheck"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "cynapse",
            dependencies: ["ModelCheck", "ModelCheckStubs", "ModelCheckModels"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ModelCheckTests",
            dependencies: ["ModelCheck", "ModelCheckStubs"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
