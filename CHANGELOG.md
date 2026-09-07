## 0.3.0

- **Breaking.** `GateData.enabledChannels` and `GateData.launchCache` are gone,
  replaced by `channels` — one entry per distribution channel carrying both
  whether the gate shows there and how it caches there. Caching is per channel
  because that is where it varies: `refresh_on_launch` on debug so flow edits
  appear without a reinstall, `cache_on_first_launch` in production so the
  paywall does not wait on the network. One gate-wide value made that
  combination impossible.
- Reads `Paygate-Version: 2026-09-07`. The backend still serves the previous
  version, so already-shipped builds are unaffected — but this build requires an
  API deployed on or after 2026-09-07.
- Prices can now resolve to the reader's own store country. The SDK reports its
  storefront and the server renders `{getProduct(x).price[<key>]}` for it,
  falling back to the named key when that country is not configured. Detection
  never blocks a launch: if the store has not answered yet the fallback price
  renders rather than the paywall waiting.
- Flow and gate caches are keyed by storefront. Without that, a gate set to
  `cache_on_first_launch` would serve whichever country opened it first to
  everyone after.
- `storefrontOverride` previews another country while testing. It is refused on
  the `production` channel and the server logs that it was.
- Storefront comes from StoreKit `Storefront.current`, re-read on every launch
  because a user can change App Store country mid-session.

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
