// swift-tools-version: 5.7
import PackageDescription

let families: [SupportedDeviceFamily] = [.pad, .phone]
let orientations: [InterfaceOrientation] = [
    .portrait,
    .landscapeRight,
    .landscapeLeft,
    .portraitUpsideDown
]

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
            supportedDeviceFamilies: families,
            supportedInterfaceOrientations: orientations
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
