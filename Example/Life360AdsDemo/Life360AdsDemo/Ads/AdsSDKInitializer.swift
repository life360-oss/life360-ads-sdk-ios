//
//  AdsSDKInitializer.swift
//  Life360AdsDemoiOS
//

import Foundation
import Life360AdsSDK

/// Owns Life360 Ads SDK initialization so the whole app shares one code path. Ad units capture SDK
/// state when they are built, so this has to finish before the first tab creates a slot.
enum AdsSDKInitializer {

    // MARK: - Prebid Server

    private static let accountID = "test-account"

    /// Which host the auction request goes to. Flags rather than one constant because this is a test
    /// harness: it points at a local server, a local server through Charles, or the Life360 dev server
    /// depending on what is being debugged.
    private static let useLocalHost = false
    private static let useCharles = true

    private static let localHost = "http://127.0.0.1:8001"
    private static let charlesHost = "http://localhost.charlesproxy.com:8001"
    private static let life360DevHost = "https://prebid-server.dev.life360.com"

    /// Configures and initializes the SDK against the Prebid Server selected above.
    static func initialize() {
        applySharedConfiguration()
        initializeWithPrebidServer()
    }

    // MARK: - Private

    private static func applySharedConfiguration() {
        // Verbose logging and PBS debug echo — the point of a demo app is seeing the request/response.
        Prebid.shared.pbsDebug = true
        Prebid.shared.logLevel = .debug

        Prebid.shared.prebidServerAccountId = accountID

        // Set source app for SKAdNetwork.
        Targeting.shared.sourceapp = "6444052767"
        Targeting.shared.storeURL = "https://itunes.apple.com/us/app/nativo-mraid-app/id6444052767?mt=8"
        Targeting.shared.publisherName = "Life360"
        Targeting.shared.itunesID = "6444052767"
    }

    /// Uses the no-GMA `initializeSDK` overload. The GMA-aware ones exist only to log a warning about the
    /// linked GMA version, and this app doesn't link it.
    private static func initializeWithPrebidServer() {
        let host = prebidServerHost()
        Prebid.shared.customStatusEndpoint = "\(host)/status"

        do {
            try Prebid.initializeSDK(serverURL: "\(host)/openrtb2/auction") { status, error in
                switch status {
                case .succeeded:
                    print("PrebidSDK: initialized successfully")
                case .serverStatusWarning:
                    print("PrebidSDK: init OK but PBS /status check warned – \(error?.localizedDescription ?? "unknown")")
                case .failed:
                    print("PrebidSDK: init FAILED – \(error?.localizedDescription ?? "unknown")")
                case .serverStatusSkipped:
                    print("PrebidSDK: server status skipped")
                @unknown default:
                    break
                }
            }
        } catch {
            print("PrebidSDK: init FAILED – \(error.localizedDescription)")
        }
    }

    private static func prebidServerHost() -> String {
        let local = useCharles ? charlesHost : localHost
        return useLocalHost ? local : life360DevHost
    }
}
