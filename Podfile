platform :ios, '15.0'

workspace 'Life360AdsSDK'

project 'PrebidMobile.xcodeproj'
project 'EventHandlers/EventHandlers.xcodeproj'
project 'Example/PrebidDemo/PrebidDemo.xcodeproj'

def gma_pods
  pod 'Google-Mobile-Ads-SDK'
end

def applovin_pods
  pod 'AppLovinSDK'
end

def event_handlers_project
  project 'EventHandlers/EventHandlers.xcodeproj'
  use_frameworks!
end

def ima_pod
  pod 'GoogleAds-IMA-iOS-SDK'
end

def prebid_demo_pods
  use_frameworks!
  
  ima_pod
  gma_pods
  applovin_pods
end

def internalTestApp_pods
  use_frameworks!
  
  pod 'Alamofire', '4.9.1'
  pod 'Eureka'
  pod 'SVProgressHUD'
  pod 'RxSwift'
  
  ima_pod
  gma_pods
  applovin_pods
end

target 'Life360AdsSDKGAMEventHandlers' do
  event_handlers_project
  gma_pods
end

target 'Life360AdsSDKGAMEventHandlersTests' do
  event_handlers_project
  gma_pods
end

target 'Life360AdsSDKAdMobAdapters' do
  event_handlers_project
  gma_pods
end

target 'Life360AdsSDKAdMobAdaptersTests' do
  event_handlers_project
  gma_pods
end

target 'Life360AdsSDKMAXAdapters' do
  event_handlers_project
  applovin_pods
end

target 'Life360AdsSDKMAXAdaptersTests' do
  event_handlers_project
  applovin_pods
end

target 'PrebidDemoSwift' do
  project 'Example/PrebidDemo/PrebidDemo.xcodeproj'
  
  prebid_demo_pods
  
  target 'PrebidDemoTests' do
    inherit! :search_paths
  end
end

target 'PrebidDemoObjectiveC' do
  project 'Example/PrebidDemo/PrebidDemo.xcodeproj'
  
  prebid_demo_pods
end

target 'InternalTestApp' do
  project 'InternalTestApp/InternalTestApp.xcodeproj'
  internalTestApp_pods
  
  target 'InternalTestAppTests' do
    inherit! :search_paths
  end
  
  target 'InternalTestAppUITests' do
    inherit! :search_paths
  end
end

target 'InternalTestApp-Skadn' do
  project 'InternalTestApp/InternalTestApp.xcodeproj'
  internalTestApp_pods
end

target 'OpenXMockServer' do
  use_frameworks!
  project 'InternalTestApp/InternalTestApp.xcodeproj'
  
  pod 'Alamofire', '4.9.1'
  pod 'RxSwift'
  
  target 'OpenXMockServerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  # Xcode 27 refuses deployment targets below 15.0. Raise pod targets to the SDK
  # floor, but keep any pod that already declares a higher minimum.
  raise_floor = lambda do |config|
    current = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_s
    if current.empty? || Gem::Version.new(current) < Gem::Version.new('15.0')
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end

  installer.generated_projects.each do |project|
    # Project-level configs too: Xcode validates these separately from the targets.
    project.build_configurations.each(&raise_floor)
    project.targets.each { |target| target.build_configurations.each(&raise_floor) }
  end

  # GoogleMobileAds is a static archive, so linking it into a dynamic framework copies it in and
  # collides with the host app's own copy (duplicate GAD* classes). The GMA-based frameworks must
  # leave it to the host app and resolve its symbols at load time.
  %w[Life360AdsSDKGAMEventHandlers Life360AdsSDKAdMobAdapters].each do |name|
    Dir["#{installer.sandbox.root}/Target Support Files/Pods-#{name}/*.xcconfig"].each do |path|
      content = File.read(path)
      stripped = content.gsub(/ -framework "(GoogleMobileAds|Google_Mobile_Ads_SDK|UserMessagingPlatform)"/, '')
      next if stripped == content
      File.write(path, stripped.sub(/^OTHER_LDFLAGS = .*$/) { |line| "#{line} -Wl,-undefined,dynamic_lookup" })
    end
  end
end
