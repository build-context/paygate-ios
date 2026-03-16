// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaygateSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PaygateSDK",
            targets: ["PaygateSDK"]
        ),
    ],
    targets: [
        .target(
            name: "PaygateSDK",
            path: "Sources/PaygateSDK"
        ),
    ]
)
