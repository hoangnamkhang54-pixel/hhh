// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "AppBatchDeleter",
    platforms: [.iOS(.15)],
    products: [
        .library(name: "AppBatchDeleter", targets: ["AppBatchDeleter"])
    ],
    targets: [
        .target(
            name: "AppBatchDeleter",
            path: "."
        )
    ]
)
