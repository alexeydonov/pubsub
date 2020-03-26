// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PubSub",
    products: [
        .library(
            name: "PubSub",
            targets: ["PubSub"]),
    ],
    targets: [
        .target(
            name: "PubSub",
            dependencies: []),
        .testTarget(
            name: "PubSubTests",
            dependencies: ["PubSub"]),
    ]
)
