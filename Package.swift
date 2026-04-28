// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Browse",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Browse", targets: ["Browse"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "Browse",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Browse/Sources",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Browse/Sources/Resources/Info.plist",
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "BrowseTests",
            dependencies: ["Browse"],
            path: "BrowseTests"
        ),
    ]
)
