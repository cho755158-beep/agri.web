// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "Agri_Web",
    platforms: [
       .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
    ],
    targets: [
        .executableTarget(
            name: "Agri_Web",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "Agri_WebTests",
            dependencies: [
                .target(name: "Agri_Web"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
] }
