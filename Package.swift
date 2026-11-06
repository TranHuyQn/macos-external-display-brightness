// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DisplayControl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DisplayCore", targets: ["DisplayCore"]),
        .executable(name: "DisplayControl", targets: ["DisplayControl"])
    ],
    targets: [
        .target(
            name: "DisplayCore",
            swiftSettings: [
                .unsafeFlags(["-Osize"], .when(configuration: .release))
            ]
        ),
        .executableTarget(
            name: "DisplayControl",
            dependencies: ["DisplayCore"],
            swiftSettings: [
                .unsafeFlags(["-Osize"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "DisplayCoreTests",
            dependencies: ["DisplayCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
