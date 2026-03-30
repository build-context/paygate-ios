sdk_version = File.read(File.expand_path('VERSION', __dir__)).strip

Pod::Spec.new do |s|
  s.name             = 'PaygateSDK'
  s.version          = sdk_version
  s.summary          = 'Paygate iOS SDK – paywalls, flows, and in-app purchases'
  s.description      = 'Present paywalls, onboarding flows, and handle StoreKit 2 in-app purchases.'
  s.homepage         = 'https://github.com/build-context/paygate-ios'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Paygate' => 'support@paygate.dev' }
  s.source           = { :git => 'https://github.com/build-context/paygate-ios.git', :tag => "v#{s.version}" }
  s.source_files     = 'Sources/PaygateSDK/**/*.swift'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
end
