// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HoursTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HoursTracker",
            path: "Sources/HoursTracker"
        )
    ]
)
