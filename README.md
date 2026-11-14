# Paygate iOS SDK

Present Paygate paywalls and onboarding flows, and handle StoreKit 2 purchases.
iOS 15+, Swift 5.9.

## Install

### Swift Package Manager (recommended)

In Xcode: **File → Add Package Dependencies…**, enter
`https://github.com/build-context/paygate-ios`, and add the **Paygate** product
to your app target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/build-context/paygate-ios.git", from: "0.6.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Paygate", package: "paygate-ios")
    ])
]
```

SPM resolves releases from the `v*` tags on this repo, so a release is available
the moment its tag exists.

### CocoaPods

CocoaPods still works. In your `Podfile`:

```ruby
pod 'Paygate', '~> 0.6.0'
```

then `pod install`. CocoaPods is fed by a separate `pod trunk push`, so it can
trail SPM briefly after a release. Check what trunk has with:

```
curl -s https://trunk.cocoapods.org/api/v1/pods/Paygate | jq '[.versions[].name]'
```

## Use

```swift
import Paygate

await Paygate.initialize(apiKey: "<API_KEY>")

let result = try await Paygate.launchGate("<GATE_ID>")
switch result.status {
case .purchased, .alreadySubscribed:
    break // User has access
case .dismissed, .skipped:
    break // User declined
case .channelNotEnabled:
    break // Not shown for this build
case .planLimitReached:
    break // Monthly presentation quota exceeded
}
```

## Flutter

Use [`paygate_flutter`](https://pub.dev/packages/paygate_flutter), which wraps
this SDK and supports both Swift Package Manager and CocoaPods on iOS.
