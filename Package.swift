// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "AppBatchDeleter",
    platforms: [.iOS(.v15)],
    products: [
        .executableName(name: "AppBatchDeleter")
    ],
    targets: [
        .executableTarget(
            name: "AppBatchDeleter",
            path: "."
        )
    ]
)
