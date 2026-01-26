// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveRigControlApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "LiveRigControlApp", targets: ["LiveRigControlApp"])
    ],
    targets: [
        .executableTarget(
            name: "LiveRigControlApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
