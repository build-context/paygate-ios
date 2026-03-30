// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Paygate",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Paygate",
            targets: ["Paygate"]
        ),
    ],
    targets: [
        .target(
            name: "Paygate",
            path: "Sources/Paygate"
        ),
    ]
)
