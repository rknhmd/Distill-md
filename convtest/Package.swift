// swift-tools-version:6.0
//
// Regression harness for DistillCore: converts every fixture in
// samples/ through the public engine API and asserts the behaviors the
// converters promise. Run: cd convtest && swift run convtest samples
//
import PackageDescription
let package = Package(
    name: "convtest",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../DistillCore"),
    ],
    targets: [
        .executableTarget(
            name: "convtest",
            dependencies: [.product(name: "DistillCore", package: "DistillCore")],
            path: "Sources"
        )
    ]
)
