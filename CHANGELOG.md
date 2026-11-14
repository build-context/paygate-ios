## 0.6.0

- **Lifetime (non-consumable) purchases now count.** The SDK kept only
  subscriptions, so someone who bought a lifetime unlock was never entitled:
  the gate kept showing, and Restore found nothing. What the user owns now
  covers auto-renewable and non-renewing subscriptions **and** non-consumables.
  Consumables are left out, and so are refunded purchases and expired
  subscriptions. Gate suppression, Restore and the public getter all read the
  same set.
- **`Paygate.activeEntitlementProductIDs`** is that set. The old
  `activeSubscriptionProductIDs` is deprecated but still works, and **now
  includes lifetime purchases**. If your app reads it to decide who has paid,
  lifetime buyers start counting with no change on your side.
- **Restore is never silent.** When a paywall's Restore button finds nothing,
  or the App Store cannot be reached, the SDK tells the page: `paygate.restore()`
  now returns a Promise, and a flow can set `paygate.onRestore = fn` to receive
  `{ status: "restored" | "nothing_found" | "cancelled" | "error" }`. A flow
  with no handler gets a native alert for `nothing_found` and `error`, so
  existing flows don't need editing. Cancelling the Apple Account prompt shows
  nothing, because cancelling was the reader's choice.
- A failed `AppStore.sync()` (offline, say) still finds purchases the device
  already knows about, so a lifetime unlock restores without a connection.
- **`Paygate.restorePurchases()`** for a "Restore purchases" row in your own
  settings. It returns what the user owns afterwards, and throws
  `StoreKitError.userCancelled` if they cancel the password prompt.
- A second tap on Restore while one is running is ignored, instead of starting
  a second sync and a second password prompt.
- **Swift Package Manager is the recommended install.** A README with SPM first
  and CocoaPods second. No code changes.
- **A LICENSE file (MIT).** The podspec has always declared MIT, but
  `pod spec lint` warned that the repo had no license file.

## 0.5.0

- **A gate now shows each reader the same flow every time.** The SDK creates a
  random install id on first use, keeps it in `UserDefaults`, and sends it as
  `Paygate-Install-Id` on every request. The server hashes it with the gate id
  to pick the flow, so a reader no longer re-rolls the gate's weights on every
  cold launch — or, with `refresh_on_launch`, on every presentation. That is
  what makes a price test readable: one person, one price.
- **`Paygate.appUserId`** (optional) assigns by your own user id instead, so
  one person gets the same flow across devices and reinstalls. Sent as
  `Paygate-App-User-Id`; it wins over the install id. Setting it moves a reader
  once, from their install's flow to their user's — set it before the first
  gate launch if you can. Use an opaque id, not an email address.
- **`Paygate.installId`** exposes the install id for your own logs and support.
  It is a UUID this SDK made up, not an advertising or device identifier, and
  deleting the app discards it.
- Changing a gate's weights still moves some readers to a different flow; see
  the gate docs. Older SDKs keep the random per-fetch pick.

## 0.4.0

- **Breaking.** `DistributionChannel.testflight` is now
  `DistributionChannel.testing`, and the wire value is `testing`. TestFlight
  detection is unchanged — a `sandboxReceipt` in the bundle still identifies a
  build under test — only the name it resolves to has changed, so that iOS and
  Android can finally mean the same thing by it.
- **`Paygate.channelOverride` sets the channel explicitly, and wins over
  detection.** Rarely needed here, since this SDK can tell TestFlight from the
  App Store on its own. It exists for parity with Android, where the equivalent
  is undetectable: Play reports the same installer for every testing track as
  for production.
- Unlike `storefrontOverride`, `channelOverride` is **not** refused in
  production. It selects among your own gate settings; it cannot reprice
  anything, and it cannot reveal a paywall a gate has switched off.
- **Already-shipped builds are safe, and this was checked rather than assumed.**
  A build on 2026-09-07 looks for a `testflight` entry, does not find one, and
  falls back to `enabled ?? true` / `launchCache ?? cacheOnFirstLaunch` — it
  keeps selling and merely stops re-fetching per launch. A build pinned to
  2025-03-16 gates itself by string-matching `enabledChannels`, where a miss
  means `channelNotEnabled` and **no paywall at all**; the API therefore keeps
  serving `testflight` in that legacy field specifically. Upgrading the API
  without upgrading this SDK is safe in both directions.

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
