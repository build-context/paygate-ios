Pod::Spec.new do |s|
  s.name             = 'PaygateSDK'
  s.version          = '0.1.0'
  s.summary          = 'Paygate iOS SDK – paywalls, flows, and in-app purchases'
  s.description      = 'Present paywalls, onboarding flows, and handle StoreKit 2 in-app purchases.'
  s.homepage         = 'https://github.com/paygate/paygate-ios'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Paygate' => 'support@paygate.dev' }
  s.source           = { :http => 'https://github.com/paygate/paygate-ios' }
  s.source_files     = 'Sources/PaygateSDK/**/*.swift'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
end
