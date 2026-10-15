// swift-tools-version:6.0
import PackageDescription

// TagLib is built once by scripts/build-taglib.sh into vendor/taglib (universal static libraries).
let vendor = Context.packageDirectory + "/vendor/taglib"

let package = Package(
    name: "MetaEdit",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CTagLib", path: "Sources/CTagLib"),
        .executableTarget(
            name: "MetaEdit",
            dependencies: ["CTagLib"],
            path: "Sources/MetaEdit",
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I\(vendor)/include"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(vendor)/lib"]),
                .linkedLibrary("tag_c"),
                .linkedLibrary("tag"),
                .linkedLibrary("z"),
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "MetaEditTests",
            dependencies: ["MetaEdit"],
            path: "Tests/MetaEditTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I\(vendor)/include"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
