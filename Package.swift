// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LidFold",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LidFold", targets: ["LidFold"]),
    ],
    targets: [
        .executableTarget(
            name: "LidFold",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(name: "LidFoldTests", dependencies: ["LidFold"]),
    ],
    swiftLanguageModes: [.v6]
)
