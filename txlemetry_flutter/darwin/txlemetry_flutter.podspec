#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint txlemetry_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'txlemetry_flutter'
  s.version          = '6.0.0'
  s.summary          = 'Txlemetry analytics for Flutter applications.'
  s.description      = <<-DESC
Txlemetry Flutter plugin
                       DESC
  s.homepage         = 'https://txlemetry.com/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Txlemetry' => 'engineering@txlemetry.com' }
  s.source           = { :path => '.' }

  s.source_files = 'txlemetry_flutter/Sources/txlemetry_flutter/**/*.swift'
  s.resource_bundles = { "TxlemetryFlutter" => "txlemetry_flutter/Sources/txlemetry_flutter/PrivacyInfo.xcprivacy" }
  
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  # Use the coordinated Txlemetry native SDK major version.
  s.dependency 'Txlemetry', '~> 4.0.0'

  s.ios.deployment_target = '13.0'
  # PH iOS SDK 3.0.0 requires >= 10.15
  s.osx.deployment_target = '10.15'

  # Flutter.framework does not contain a i386 slice.
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.3'
end
