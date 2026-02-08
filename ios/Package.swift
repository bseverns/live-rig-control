// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveRigControlApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "LiveRigControlApp", targets: ["LiveRigControlApp"]),
        .executable(name: "MappingValidator", targets: ["MappingValidator"])
    ],
    targets: [
        .executableTarget(
            name: "LiveRigControlApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MappingValidator"
        ),
        .testTarget(
            name: "MappingValidatorTests",
            dependencies: ["MappingValidator"]
        )
    ]
)
