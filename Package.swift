// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InfiniteCarouselView",
    platforms: [
        .iOS(.v17),
        .macOS(.v15)   // macOS backport requires NSScrollView — iOS only for now
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "InfiniteCarouselView",
            targets: ["InfiniteCarouselView"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "InfiniteCarouselView"
        ),
        .testTarget(
            name: "InfiniteCarouselViewTests",
            dependencies: ["InfiniteCarouselView"]
        ),
    ]
)
