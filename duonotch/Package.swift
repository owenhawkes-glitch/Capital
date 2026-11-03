// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DuoNotch",
    platforms: [.macOS(.v14)],
    targets: [
        // Wire protocol + paths shared by the app and the hook helper.
        .target(name: "DuoNotchShared"),

        // The menu-bar / notch app.
        .executableTarget(
            name: "DuoNotch",
            dependencies: ["DuoNotchShared"]
        ),

        // Tiny CLI that Claude Code runs as a hook. It forwards the hook
        // payload to the running app over localhost and, for permission
        // requests, waits for the decision made in the notch.
        .executableTarget(
            name: "duonotch-hook",
            dependencies: ["DuoNotchShared"]
        ),
    ]
)
