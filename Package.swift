// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XrayGUI",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .target(
            name: "XrayGUICore",
            path: "Sources/XrayGUICore"
        ),
        .executableTarget(
            name: "XrayGUI",
            dependencies: ["XrayGUICore"],
            path: "Sources/XrayGUI",
            resources: [
                .copy("../../Resources/xray-core")
            ]
        ),
        .testTarget(
            name: "XrayGUICoreTests",
            dependencies: ["XrayGUICore"],
            path: "Tests/XrayGUICoreTests"
        )
    ]
)
