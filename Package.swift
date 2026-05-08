// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "appcleaner",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "appcleaner", path: "Sources/appcleaner"),
    ]
)
