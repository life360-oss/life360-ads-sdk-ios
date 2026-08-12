Pod::Spec.new do |s|

  s.name         = "Life360AdsSDK"
  s.version      = "1.4.0-geoedge"
  s.summary      = "Life360 Ads SDK is a lightweight framework that integrates directly with Nativo and Prebid Server."

  s.description  = <<-DESC
    Life360 Ads SDK is a lightweight framework that integrates directly with Prebid Server to increase yield for publishers by adding more mobile buyers."
    DESC
  s.homepage     = "https://ads.life360.com/"


  s.license      = { :type => "Apache License, Version 2.0", :text => <<-LICENSE
    Copyright 2018-2026 Life360, Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    LICENSE
    }

  s.author         = { "Life360, Inc." => "info@life360.com" }
  s.platform     	 = :ios, "13.0"
  s.swift_version  = '5.0'
  s.source         = { :git => "https://github.com/life360-oss/life360-ads-sdk-ios.git", :tag => "v#{s.version}" }
  s.xcconfig 		   = { :LIBRARY_SEARCH_PATHS => '$(inherited)',
			       :OTHER_CFLAGS => '$(inherited)',
			       :OTHER_LDFLAGS => '$(inherited)',
			       :HEADER_SEARCH_PATHS => '$(inherited)',
			       :FRAMEWORK_SEARCH_PATHS => '$(inherited)'
			     }
  s.requires_arc = true

  s.frameworks = [ 'UIKit', 
                   'Foundation', 
                   'MapKit', 
                   'SafariServices', 
                   'SystemConfiguration',
                   'AVFoundation',
                   'CoreGraphics',
                   'CoreLocation',
                   'CoreTelephony',
                   'CoreMedia',
                   'QuartzCore'
                 ]
  s.weak_frameworks  = [ 'AdSupport', 'StoreKit', 'WebKit' ]


  s.default_subspecs = ['core']
  s.subspec 'core' do |core|
    core.source_files = 'PrebidMobile/**/*.{h,m,swift}'
    core.exclude_files = [
      'PrebidMobile/Package.swift',
      'PrebidMobile/README-SPM.md'
    ]
    
    core.private_header_files = [
      'PrebidMobile/Objc/PrivateHeaders/*.h'
    ]
    core.resources = ['PrebidMobile/Resources/omsdk.js']
    core.vendored_frameworks = 'Frameworks/OMSDK_Life360.xcframework'
  end

  # Separate subspec for standalone renderer with PrebidMobile dependency
  # s.subspec 'renderer' do |renderer|
  #   renderer.source_files = 'NativoRenderer/**/*.{h,m,swift}'
  #   renderer.exclude_files = [
  #     'NativoRenderer/Package.swift'
  #   ]
  #   renderer.dependency 'PrebidMobile'
  # end

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'OTHER_LDFLAGS' => '$(inherited) -lObjC -framework OMSDK_Life360',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -no-verify-emitted-module-interface'
  }

end
