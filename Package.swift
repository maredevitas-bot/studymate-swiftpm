// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "StudyMate",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "StudyMate",
            targets: ["StudyMate"],
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "StudyMate",
            path: "Sources"
        )
    ]
)
