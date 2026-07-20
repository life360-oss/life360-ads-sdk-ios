import Foundation

/// Entry point for the Life360 Ads SDK.
///
/// The SDK is a fork of Prebid Mobile, so most configuration still lives on `Prebid`/`Targeting`
/// because both the Prebid and Nativo ad paths share most of the request and render architecture.
@objcMembers
public class Life360Ads: NSObject {

    /// The singleton instance of the `Life360Ads` class.
    public static let shared = Life360Ads()

    /// The version of the Life360 Ads SDK. This is the version sent to Prebid Server.
    public var version: String {
        PrebidConstants.VERSION
    }

    /// The version of the underlying Prebid Mobile SDK.
    public var prebidVersion: String {
        PrebidConstants.PREBID_VERSION
    }

    /// The SDK identifier sent with requests and used in logging.
    public var sdkName: String {
        PrebidConstants.SDK_NAME
    }

    /// False when the SDK was initialized without a Prebid Server (see `initializeWithoutPrebid()`).
    public internal(set) var prebidServerEnabled = true

    /// Set when willing to share precise location with Nativo for better ad targeting.
    /// Will not send to Prebid Server. This is separate from `Prebid.shared.shareGeoLocation`.
    public var shareGeoLocationWithNativo = false

    /// Initializes the SDK without a Prebid Server.
    ///
    /// Use this when you only want Nativo demand plus your own ad server (event handler). The SDK
    /// skips the Prebid Server status check, and the ad load flow skips the Prebid Server bid
    /// request — only the Nativo request and the event handler request run.
    public static func initializeWithoutPrebid() {
        Life360Ads.shared.prebidServerEnabled = false
        PrebidSDKInitializer.initializeSDK()
    }

    private override init() {
        super.init()
    }
}
