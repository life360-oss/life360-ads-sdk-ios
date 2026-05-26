// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(

    name: "Life360AdsSDK",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "Life360AdsSDK",
            targets: ["Life360AdsSDK", "__PrebidMobileInternal"]
        ),
        .library(
            name: "Life360AdsSDKAdMobAdapters",
            targets: ["Life360AdsSDKAdMobAdapters"]
        ),
        .library(
            name: "Life360AdsSDKGAMEventHandlers",
            targets: ["Life360AdsSDKGAMEventHandlers"]
        ),
        .library(
            name: "Life360AdsSDKMAXAdapters",
            targets: ["Life360AdsSDKMAXAdapters"]
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
            name: "Life360AdsSDK",
            path: "PrebidMobile",
            sources: ["Swift"]
        ),
        .target(
            name: "__PrebidMobileInternal",
            dependencies: [
                "Life360AdsSDK",
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
            name: "Life360AdsSDKAdMobAdapters",
            dependencies: [
                "Life360AdsSDK",
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
            path: "EventHandlers/PrebidMobileAdMobAdapters",
            sources: ["Sources"]
        ),
        .target(
            name: "Life360AdsSDKGAMEventHandlers",
            dependencies: [
                "Life360AdsSDK",
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            ],
            path: "EventHandlers/PrebidMobileGAMEventHandlers",
            sources: ["Sources"]
        ),
        .target(
            name: "Life360AdsSDKMAXAdapters",
            dependencies: [
                "Life360AdsSDK",
                .product(name: "AppLovinSDK", package: "AppLovin-MAX-Swift-Package"),
            ],
            path: "EventHandlers/PrebidMobileMAXAdapters",
            sources: ["Sources"]
        ),
    ]
)
