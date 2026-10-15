// swift-tools-version:5.10
import PackageDescription

// TagLib is built once by scripts/build-taglib.sh into vendor/taglib (universal static libraries).
let vendor = Context.packageDirectory + "/vendor/taglib"

let package = Package(
    name: "MeteEdit",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CTagLib", path: "Sources/CTagLib"),
        .executableTarget(
            name: "MeteEdit",
            dependencies: ["CTagLib"],
            path: "Sources/MeteEdit",
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
            name: "MeteEditTests",
            dependencies: ["MeteEdit"],
            path: "Tests/MeteEditTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I\(vendor)/include"]),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
