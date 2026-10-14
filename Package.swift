// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SecureErase",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(
        name: "SecureErase",
        dependencies: [.product(name: "Sparkle", package: "Sparkle")],
        path: ".",
        exclude: ["Resources", "scripts", "build", "SecureErase.app", "README.md", "build.sh", "package.sh", "notarize.py", "release.py"],
        sources: ["SecureErase.swift", "Updates.swift"],
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    )]
)
