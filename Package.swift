// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TymelineCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TymelineCore", targets: ["TymelineCore"])
    ],
    targets: [
        .target(
            name: "TymelineCore",
            path: "Sources/TymelineCore"
        ),
        .testTarget(
            name: "TymelineCoreTests",
            dependencies: ["TymelineCore"],
            path: "Tests/TymelineCoreTests"
        )
    ]
)
