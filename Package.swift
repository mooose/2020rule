// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "2020Rule",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "2020Rule", targets: ["Rule2020"])
    ],
    targets: [
        .executableTarget(
            name: "Rule2020",
            path: "Sources/Rule2020",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
