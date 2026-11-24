// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuBento",
    platforms: [.macOS(.v14)],
    targets: [
        // Reading other apps' menu bar items (Accessibility) and moving them
        // with synthesised Cmd-drags. Shared by the app and the CLI.
        .target(name: "MenuBentoCore"),

        // The menu bar manager itself (LSUIElement accessory app).
        .executableTarget(name: "MenuBento", dependencies: ["MenuBentoCore"]),

        // Small debugging tool: list items, test moves on our own test items.
        .executableTarget(name: "menubento-cli", dependencies: ["MenuBentoCore"]),
    ]
)
