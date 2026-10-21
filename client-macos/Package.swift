// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RustleTranscript",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "RustleTranscript",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/RustleTranscript",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Speech"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
