// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "CameraKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "SCSDKCameraKit", targets: ["SCSDKCameraKit"]),
        .library(name: "SCSDKCameraKitLoginKitAuth", targets: ["SCSDKCameraKitLoginKitAuth_Wrapper"]),
        .library(name: "SCSDKCameraKitPushToDeviceExtension", targets: ["SCSDKCameraKitPushToDeviceExtension_Wrapper"]),
        .library(name: "SCSDKCameraKitReferenceUI", targets: ["SCSDKCameraKitReferenceUI"]),
        .library(name: "SCSDKCameraKitReferenceSwiftUI", targets: ["SCSDKCameraKitReferenceSwiftUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/afterglow-labs/snap-kit-spm", .upToNextMajor(from: "2.6.4"))
    ],
    targets: [
        .binaryTarget(
            name: "SCSDKCameraKit",
            url: "https://github.com/afterglow-labs/camera-kit-ios-sdk/releases/download/1.50.7/SCSDKCameraKit.xcframework.zip",
            checksum: "5710cb1f77ffe9cfe7fe7b873d8c3fb3552201bbba0477e55ec13d8e25d601ac"
        ),
        .binaryTarget(
            name: "SCSDKCameraKitLoginKitAuth",
            url: "https://storage.googleapis.com/snap-kit-build/scsdk/camera-kit-ios/releases-spm/1.50.0/SCSDKCameraKitLoginKitAuth.xcframework.zip",
            checksum: "e0ff4e168c6149e46af6fd8a125165d2e1184cd33d89764ee5146007baa38096"
        ),
        .target(
            name: "SCSDKCameraKitLoginKitAuth_Wrapper",
            dependencies: [
                .target(name: "SCSDKCameraKitLoginKitAuth"),
                .target(name: "SCSDKCameraKit"),
                .product(name: "SnapSDKLoginKit", package: "snap-kit-spm")
            ],
            path: "Sources/CameraKitLoginKitAuth_Wrapper"
        ),

        .binaryTarget(
            name: "SCSDKCameraKitPushToDeviceExtension",
            url: "https://storage.googleapis.com/snap-kit-build/scsdk/camera-kit-ios/releases-spm/1.50.0/SCSDKCameraKitPushToDeviceExtension.xcframework.zip",
            checksum: "fc7e8a60a692e74161c6edd77302b4277d923ef28ce1802e9099a5199995b312"
        ),
        .target(
            name: "SCSDKCameraKitPushToDeviceExtension_Wrapper",
            dependencies: [
                .target(name: "SCSDKCameraKitPushToDeviceExtension")
            ],
            path: "Sources/CameraKitPushToDeviceExtension_Wrapper"
        ),
                
        .target(
            name: "SCSDKCameraKitReferenceUI",
            dependencies: ["SCSDKCameraKit"],
            path: "Sources/SCSDKCameraKitReferenceUI",
            resources: [
                .process("Resources/Reference.xcassets"),
                .copy("Resources/Strings")
            ]
        ),
        .target(name: "SCSDKCameraKitReferenceSwiftUI", dependencies: ["SCSDKCameraKitReferenceUI"], path: "Sources/SCSDKCameraKitReferenceSwiftUI")
    ]
)
