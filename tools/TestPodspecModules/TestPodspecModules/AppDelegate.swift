//
//  AppDelegate.swift
//  TestPodspecModules
//
//  Created by Vadim Khohlov on 6/29/21.
//

import UIKit

// Core module: exercises the renamed Life360AdsSDK pod's public initializer so a
// missing or misnamed module fails the build here rather than at integration time.
import Life360AdsSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        try? Prebid.initializeSDK(serverURL: "https://prebid-server.example.com/openrtb2/auction")

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
