// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pager",
    platforms: [.iOS(.v16)],
    products: [.library(name: "Pager", targets: ["Pager"])],
    targets: [
        .target(name: "Pager"),
        .testTarget(name: "PagerTests", dependencies: ["Pager"]),
    ],
    swiftLanguageModes: [.v6]
)
