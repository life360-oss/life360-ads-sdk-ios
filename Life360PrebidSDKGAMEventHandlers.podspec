Pod::Spec.new do |s|

  s.name         = "Life360PrebidSDKGAMEventHandlers"
  s.version      = "3.3.0"
  s.summary      = "The bridge between Life360 Prebid SDK and GMA SDK."

  s.description  = "GAM Event Handlers manages rendering of Prebid or GAM ads respectively to the winning bid."
  s.homepage     = "https://ads.life360.com/"


  s.license      = { :type => "Apache License, Version 2.0", :text => <<-LICENSE
    Copyright 2018-2025 Life360, Inc.

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

  s.author		= { "Life360, Inc." => "info@life360.com" }
  s.platform     	= :ios, "13.0"
  s.swift_version 	= '5.0'
  s.source       	= { :git => "git@github.com:life360-oss/nativo-prebid-sdk-ios.git", :tag => "#{s.version}" }
  s.xcconfig 		= { :LIBRARY_SEARCH_PATHS => '$(inherited)',
  			    :OTHER_CFLAGS => '$(inherited)',
			    :OTHER_LDFLAGS => '$(inherited)',
			    :HEADER_SEARCH_PATHS => '$(inherited)',
			    :FRAMEWORK_SEARCH_PATHS => '$(inherited)'
			  }

  s.source_files = 'EventHandlers/PrebidMobileGAMEventHandlers/**/*.{h,m,swift}'
  s.static_framework = true

  s.dependency 'Life360PrebidSDK', '>= 3.3.0'
  s.dependency 'Google-Mobile-Ads-SDK', '>= 13.0.0'

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES'
  }
end
