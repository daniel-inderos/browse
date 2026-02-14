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
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "Browse",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            path: "Browse/Sources",
            exclude: ["Resources/Info.plist"]
        ),
        .testTarget(
            name: "BrowseTests",
            dependencies: ["Browse"],
            path: "BrowseTests"
        ),
    ]
)
