// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "RunaChat",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "RunaChat", targets: ["RunaChat"]),
    ],
    targets: [
        .target(name: "RunaChat", path: "Sources/RunaChat"),
    ]
)
