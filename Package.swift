// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LTEModemCompact",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LTEModemCompact", targets: ["LTEModemCompact"]), .executable(name: "ModemDiagnostics", targets: ["ModemDiagnostics"])],
    dependencies: [],
    targets: [
        .target(name: "NativeUSB", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "LaunchSupport"),
        .target(name: "USBLaunchEvents", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "USBLauncher", dependencies: ["LaunchSupport", "USBLaunchEvents"], linkerSettings: [.linkedFramework("AppKit")]),
        .target(name: "SystemNetworkStats"),
        .target(name: "NetworkCore", dependencies: ["NativeUSB", "SystemNetworkStats"], linkerSettings: [.linkedFramework("Security")]),
        .target(name: "ModemCore", dependencies: ["NativeUSB"]),
        .executableTarget(name: "LTEModemCompact", dependencies: ["NetworkCore", "ModemCore", "LaunchSupport"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement"), .linkedFramework("UserNotifications")]),
        .executableTarget(name: "ModemDiagnostics", dependencies: ["ModemCore"]),
        .testTarget(name: "ModemCoreTests", dependencies: ["ModemCore"]),
        .testTarget(name: "NetworkCoreTests", dependencies: ["NetworkCore"]),
        .testTarget(name: "LaunchSupportTests", dependencies: ["LaunchSupport"])
    ]
)
