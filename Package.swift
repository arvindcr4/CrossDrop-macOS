// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CrossDrop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CrossDrop", targets: ["CrossDrop"])
    ],
    targets: [
        .executableTarget(
            name: "CrossDrop",
            path: "Sources/CrossDrop",
            resources: [
                .copy("../../Info.plist")
            ],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
