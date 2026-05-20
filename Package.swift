// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(

    name: "Life360PrebidSDK",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "Life360PrebidSDK",
            targets: ["Life360PrebidSDK", "__PrebidMobileInternal"]
        ),
        .library(
            name: "Life360PrebidSDKAdMobAdapters",
            targets: ["Life360PrebidSDKAdMobAdapters"]
        ),
        .library(
            name: "Life360PrebidSDKGAMEventHandlers",
            targets: ["Life360PrebidSDKGAMEventHandlers"]
        ),
        .library(
            name: "Life360PrebidSDKMAXAdapters",
            targets: ["Life360PrebidSDKMAXAdapters"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            "12.0.0"..<"14.0.0"
        ),
        .package(url: "https://github.com/AppLovin/AppLovin-MAX-Swift-Package.git", .upToNextMajor(from: "13.0.0")),
    ],
    targets: [
        .target(
            name: "Life360PrebidSDK",
            path: "PrebidMobile",
            sources: ["Swift"]
        ),
        .target(
            name: "__PrebidMobileInternal",
            dependencies: [
                "Life360PrebidSDK",
                "PrebidMobileOMSDK",
            ],
            path: "PrebidMobile",
            sources: ["Objc"],
            cSettings: [
                .headerSearchPath("./Objc/PrivateHeaders"),
                .define("PrebidMobile_SPM", to: "1"),
            ]
        ),
        .binaryTarget(
            name: "PrebidMobileOMSDK",
            path: "Frameworks/OMSDK_Prebidorg.xcframework"
        ),
        .target(
            name: "Life360PrebidSDKAdMobAdapters",
            dependencies: [
                "Life360PrebidSDK",
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
            path: "EventHandlers/PrebidMobileAdMobAdapters",
            sources: ["Sources"]
        ),
        .target(
            name: "Life360PrebidSDKGAMEventHandlers",
            dependencies: [
                "Life360PrebidSDK",
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
            path: "EventHandlers/PrebidMobileGAMEventHandlers",
            sources: ["Sources"]
        ),
        .target(
            name: "Life360PrebidSDKMAXAdapters",
            dependencies: [
                "Life360PrebidSDK",
                .product(name: "AppLovinSDK", package: "AppLovin-MAX-Swift-Package"),
            ],
            path: "EventHandlers/PrebidMobileMAXAdapters",
            sources: ["Sources"]
        ),
    ]
)
