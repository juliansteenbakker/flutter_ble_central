#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_ble_central.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_ble_central'
  s.version          = '0.2.0'
  s.summary          = 'A Flutter package for scanning BLE data in central mode.'
  s.description      = <<-DESC
A Flutter package for scanning BLE data in central mode.
                       DESC
  s.homepage         = 'https://github.com/juliansteenbakker/flutter_ble_central'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Julian Steenbakker' => 'juliansteenbakker@outlook.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_ble_central/Sources/flutter_ble_central/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.11'
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'flutter_ble_central_privacy' => ['flutter_ble_central/Sources/flutter_ble_central/Resources/PrivacyInfo.xcprivacy']}
end
