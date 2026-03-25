// swift-tools-version: 5.7
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
            bundleVersion: "1"
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
