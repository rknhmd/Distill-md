// swift-tools-version:6.0
//
// DistillCore: the conversion engine, shared by the app, the `distill`
// CLI, and the MCP server. Owns the two approved package dependencies
// (ZIPFoundation, CoreXLSX); everything else is Apple frameworks.
//
import PackageDescription

let package = Package(
    name: "DistillCore",
    platforms: [
        // Vision's modern text-recognition API (RecognizeTextRequest)
        // needs macOS 15; the app itself targets the current SDK.
        .macOS(.v15),
    ],
    products: [
        .library(name: "DistillCore", targets: ["DistillCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.16"),
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.1"),
    ],
    targets: [
        .target(
            name: "DistillCore",
            dependencies: ["ZIPFoundation", "CoreXLSX"]
        ),
    ]
)
