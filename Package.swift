// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Pager",
    platforms: [.iOS(.v15)],
    products: [.library(name: "Pager", targets: ["Pager"])],
    targets: [
        .target(name: "Pager"),
        .testTarget(name: "PagerTests", dependencies: ["Pager"]),
    ]
)
