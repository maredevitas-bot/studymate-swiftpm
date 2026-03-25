// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudyMate",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "StudyMate",
            targets: ["StudyMate"],
            bundleIdentifier: "com.yvc.studymate",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "StudyMate",
            path: "Sources",
            resources: [.process("Info.plist")]
        )
    ]
)
