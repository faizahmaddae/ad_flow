# AdMob Mediation with ad_flow (v2)

AdMob **mediation** serves ads from multiple networks (bidding + waterfall)
through your existing AdMob integration, raising fill rate and eCPM. ad_flow
v2 is mediation-transparent: mediation is configured in the AdMob console and
in your app's dependencies — ad_flow's Dart API does not change, and no
ad_flow configuration is needed to enable it.

> **Migrating from ad_flow v1?** v1 shipped a `MediationHelper` with
> per-network Dart wiring. v2 deliberately does not: the plugin and each
> adapter do the work natively, and consent signalling is handled by UMP (the
> IAB TCF string), which ad_flow already drives. Delete any `MediationHelper`
> usage; the steps below are all that is required.

## 1. Console

1. AdMob console → **Mediation** → create/edit a mediation group per format.
2. Add your networks (bidding where available; waterfall otherwise).
3. **Privacy & messaging → your GDPR message → Ad partners**: register every
   mediation partner so UMP consent covers them. This is a compliance
   requirement, not an optimization.
4. Update **app-ads.txt** with each partner's lines (listed on the partner's
   AdMob mediation page) — missing lines cost fill.

## 2. Add the adapters

**Preferred:** Google publishes official Flutter mediation adapter packages
(`gma_mediation_<network>` on pub.dev — e.g. `gma_mediation_applovin`,
`gma_mediation_unityads`, `gma_mediation_meta`). Add the ones for your
networks to `pubspec.yaml`; they bundle the correct native adapter on both
platforms and are versioned against `google_mobile_ads`. Check each package's
compatibility with `google_mobile_ads` 9.x before adding.

**Fallback (no Flutter package for the network):** add the native adapter
yourself —

- Android, `android/app/build.gradle`:

  ```groovy
  dependencies {
    implementation 'com.google.ads.mediation:<network>:x.y.z'
  }
  ```

- iOS, `ios/Podfile`:

  ```ruby
  pod 'GoogleMobileAdsMediation<Network>'
  ```

Versions and compatibility per network:
[Android partners](https://developers.google.com/admob/android/mediation) ·
[iOS partners](https://developers.google.com/admob/ios/mediation).

If you experiment with the **Next-Gen SDK** build flag
(`--dart-define=USE_NEXT_GEN_SDK=true`, Android-only, experimental), verify
every adapter is Next-Gen-compatible first.

## 3. iOS: SKAdNetworkItems

Add each partner's **`SKAdNetworkItems`** to `ios/Runner/Info.plist`.
Google's own identifiers ship with the SDK, but partner identifiers do not,
and missing entries silently cost you attributed (paid) installs. Each
partner's AdMob mediation page lists theirs.

## 4. Consent signals

Nothing to do in ad_flow: UMP writes the IAB TCF consent string, and
certified adapters read it themselves. Register the partners in Privacy &
messaging (step 1.3). For a network with an extra, non-TCF consent API,
follow that partner's page — such calls are made from your app directly, not
through ad_flow.

## 5. Verifying mediation

- Open the **Ad Inspector** (`ads.openAdInspector()`) on a test device: it
  lists every mediation group, adapter status, and which network filled each
  request.
- At runtime, `controller.response` (`AdResponseSummary`) reports the winning
  ad source per loaded ad, and every `AdPaidEvent` carries `adSourceName` —
  log them (e.g. through `ads.onPaidEvent`) to see your real fill mix in
  production.

## Checklist

- [ ] Mediation group per format in the console
- [ ] Partners registered under Privacy & messaging (GDPR)
- [ ] Adapters added (`gma_mediation_*` package, or native build files)
- [ ] iOS: partner `SKAdNetworkItems` in `Info.plist`
- [ ] `app-ads.txt` updated with partner lines
- [ ] Verified with Ad Inspector on a test device
