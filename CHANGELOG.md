## 0.2.0

- Gates can pin a flow's colour scheme. A WebView reads `prefers-color-scheme`
  from the system night mode rather than from your app, so an app with its own
  light/dark setting could show a paywall that disagreed with the screen behind
  it. The gate's `appearance` now decides, and the app can override it per
  launch — only the app knows whether it has a theme preference of its own.
- `appearance` defaults to `system`, which is exactly what every existing gate
  already does, so nothing restyles without being asked.
- `launchGate` and `launchFlow` take an optional `appearance`. Passing nothing
  keeps current behaviour.

## 0.1.8

- Point default base URL at the paygate-prod-bc API host

## 0.1.7

- Rename from PaygateSDK to Paygate
- Automated CocoaPods publishing via CI

## 0.1.5

- Initial public release
- StoreKit integration, WebView paywall presentation
- Gate and flow launching
