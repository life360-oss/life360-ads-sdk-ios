# Migrating from Prebid Mobile iOS to Life360 Ads SDK iOS

The Life360 Ads SDK is a fork of [Prebid Mobile iOS](https://github.com/prebid/prebid-mobile-ios) **v3.3.1**. It keeps the Prebid Mobile public API surface intact and adds Nativo as a competing demand source. For the vast majority of integrations **migration is mechanical**: rename the dependency, rename the imports, and rebuild. The base Prebid Mobile types (`Prebid`, `Targeting`, `BannerView`, `InterstitialRenderingAdUnit`, `GAMUtils`, …) keep their original names.

This guide was validated by migrating the in-repo demo app (`InternalTestApp`, the Prebid demo app) end-to-end. It required **no Life360-specific source API changes** — only the dependency and import renames in sections 1–2.

---

## 1. Swap the dependency

The module names changed. The MoPub adapter was dropped (MoPub is discontinued).

| Prebid Mobile module / pod        | Life360 Ads SDK module / pod          |
| --------------------------------- | ------------------------------------- |
| `PrebidMobile`                    | `Life360AdsSDK`                       |
| `PrebidMobileGAMEventHandlers`    | `Life360AdsSDKGAMEventHandlers`       |
| `PrebidMobileAdMobAdapters`       | `Life360AdsSDKAdMobAdapters`          |
| `PrebidMobileMAXAdapters`         | `Life360AdsSDKMAXAdapters`            |
| `PrebidMobileMoPubAdapters`       | _removed — migrate off MoPub_         |

### CocoaPods

```diff
 platform :ios, '13.0'

 target 'MyAmazingApp' do
   use_frameworks!
-  pod 'PrebidMobile'
-  pod 'PrebidMobileGAMEventHandlers'
-  pod 'PrebidMobileAdMobAdapters'
-  pod 'PrebidMobileMAXAdapters'
+  pod 'Life360AdsSDK'
+  pod 'Life360AdsSDKGAMEventHandlers'
+  pod 'Life360AdsSDKAdMobAdapters'
+  pod 'Life360AdsSDKMAXAdapters'
 end
```

Then:

```sh
pod deintegrate
pod install --repo-update
```

> Pull only the event-handler/adapter pods you actually use; `Life360AdsSDK` (core) is the only required one. The adapter pods depend on it transitively.

### Swift Package Manager

Replace the Prebid Mobile package with `https://github.com/life360-oss/life360-ads-sdk-ios.git` and link the products you need. The SPM product names match the pod names in the table above (`Life360AdsSDK`, `Life360AdsSDKGAMEventHandlers`, `Life360AdsSDKAdMobAdapters`, `Life360AdsSDKMAXAdapters`).

---

## 2. Update your imports

A find-and-replace across your Swift/Obj-C sources covers almost the entire migration:

```diff
-import PrebidMobile
+import Life360AdsSDK

-import PrebidMobileGAMEventHandlers
+import Life360AdsSDKGAMEventHandlers

-import PrebidMobileAdMobAdapters
+import Life360AdsSDKAdMobAdapters

-import PrebidMobileMAXAdapters
+import Life360AdsSDKMAXAdapters
```

If you link the frameworks directly (not via a package manager), the built products are now `Life360AdsSDK.framework`, `Life360AdsSDKGAMEventHandlers.framework`, `Life360AdsSDKAdMobAdapters.framework`, and `Life360AdsSDKMAXAdapters.framework`. Update **Link Binary With Libraries** and any **Embed Frameworks** phase accordingly.

---

## 3. Source-level API changes

The fork does **not rename or remove** any existing Prebid Mobile public type or signature — your existing Prebid Mobile code compiles unchanged.

### New public API

Within the Prebid configuration there is a new API to allow sharing a user's location with Nativo. Use `Prebid.shared.shareGeoLocationWithNativo = true`. Continue to use `Prebid.shared.shareGeoLocation` for sharing with Prebid Server & partners.

`NativoBannerViewDelegate` extends `BannerViewDelegate` with a Nativo-specific load callback:

```swift
func bannerView(_ bannerView: BannerView, didReceiveNativoAdWithSize adSize: CGSize)
```

Conform your `BannerView` delegate to `NativoBannerViewDelegate` if you want to distinguish a Nativo win from a regular display win — when a Nativo-rendered ad loads, this callback fires *instead of* `bannerView(_:didReceiveAdWithAdSize:)`. Nativo `standardDisplay` bids go through the regular display path and keep reporting via `bannerView(_:didReceiveAdWithAdSize:)`. Delegates that stay on plain `BannerViewDelegate` need no changes: they receive `bannerView(_:didReceiveAdWithAdSize:)` for every win, Nativo or not.

For base Prebid Mobile API documentation, see the [Prebid docs](https://docs.prebid.org/prebid-mobile/pbm-api/ios/code-integration-ios.html).
