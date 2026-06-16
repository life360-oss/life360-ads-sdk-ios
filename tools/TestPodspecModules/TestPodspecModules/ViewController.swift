//
//  ViewController.swift
//  TestPodspecModules
//
//  Created by Vadim Khohlov on 6/29/21.
//

import UIKit

import Life360AdsSDK
import Life360AdsSDKGAMEventHandlers
import Life360AdsSDKAdMobAdapters
import Life360AdsSDKMAXAdapters

class ViewController: UIViewController {

    @IBOutlet weak var projectVersionLabel: UILabel!
    @IBOutlet weak var renderingVersionLabel: UILabel!
    @IBOutlet weak var gamVersionLabel: UILabel!
    @IBOutlet weak var mopubVersionLabel: UILabel!

    override func viewWillAppear(_ animated: Bool) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        projectVersionLabel.text = version

        // Life360AdsSDK (core)
        renderingVersionLabel.text = Prebid.shared.version

        // Life360AdsSDKGAMEventHandlers
        gamVersionLabel.text = String(describing: GAMUtils.shared)

        // Life360AdsSDKAdMobAdapters + Life360AdsSDKMAXAdapters
        mopubVersionLabel.text = "\(AdMobUtils.self) / \(MAXUtils.self)"
    }
}
