# AdMob Mediation with ad_flow

AdMob **mediation** serves ads from multiple networks (bidding + waterfall)
through your existing AdMob integration, raising fill rate and eCPM. ad_flow
is mediation-transparent for *serving*: mediation groups live in the AdMob
console and adapters in your app's dependencies — no ad_flow configuration
is needed for ads to flow.

**Consent is different.** ad_flow drives UMP, which *collects* consent and
writes the standard strings to local storage. What UMP does **not** do — and
what Google's own partner pages state explicitly — is push that consent into
every partner SDK: *"You are responsible for verifying consent is propagated
to each ad source in your mediation chain. Google is unable to pass the
user's consent choice to such networks automatically."* Section 4 below
spells out exactly what is automatic and what remains your job.

> **Migrating from ad_flow v1?** v1 shipped a `MediationHelper` with
> per-network Dart wiring. Delete it; use the surfaces in §4 instead.

## 1. Console

1. AdMob console → **Mediation** → create/edit a mediation group per format.
2. Add your networks (bidding where available; waterfall otherwise).
3. **Privacy & messaging → your GDPR message → Ad partners**: select every
   mediation partner so UMP collects consent that covers them. This is a
   compliance requirement, not an optimization. Do the same in the **US
   states** message if you serve regulated US states.
4. Update **app-ads.txt** with each partner's lines (listed on the partner's
   AdMob mediation page) — missing lines cost fill.

## 2. Add the adapters

**Preferred:** Google publishes official Flutter mediation adapter packages
(`gma_mediation_<network>` on pub.dev — e.g. `gma_mediation_applovin`,
`gma_mediation_unity`, `gma_mediation_meta`). Add the ones for your
networks to `pubspec.yaml`; they bundle the correct native adapter on both
platforms and usually expose the network's privacy APIs as Dart calls.

The current adapters all require `google_mobile_ads: ^9.1.0` (checked
2026-10-24: `gma_mediation_applovin` 2.6.5, `gma_mediation_unity` 1.11.1,
`gma_mediation_meta` 1.7.1, `gma_mediation_ironsource` 2.7.0,
`gma_mediation_mintegral` 2.1.5, `gma_mediation_pangle` 4.2.1,
`gma_mediation_liftoffmonetize` 1.5.5), and ad_flow requires `^9.2.0`, so
they resolve together. Use a current adapter release: older ones pin
`google_mobile_ads` 8.x and will not resolve. (Earlier ad_flow docs said
Unity could not be combined with ad_flow 5.0 — that was true until
`gma_mediation_unity` shipped 9.x support, and is no longer.)

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

## 4. Consent signals — what is automatic, what is yours

What ad_flow + UMP give you:

- UMP collects consent for the partners you selected in Privacy & messaging
  and writes the results to the platform's default preferences per the IAB
  specs: `IABTCF_TCString` / `IABTCF_gdprApplies` / purpose flags (TCF),
  `IABTCF_AddtlConsent` (Google's Additional Consent string, for partners
  not on the IAB vendor list — Meta is one), and `IABGPP_HDR_GppString` /
  `IABGPP_GppSID` for US-state frameworks.
- **TCF-reading SDKs pick the TC string up themselves.** AppLovin does this
  automatically since its SDK 12.0.0 for GDPR consent, for example.

What remains **your** responsibility (Google's docs are explicit that it is
not propagated for you):

- **Networks that need their own privacy API calls.** As of this writing
  (2026-07, verify against each partner's current AdMob page):
  - *Unity Ads*: explicit consent `MetaData` — `gdpr.consent` and
    `privacy.consent` (US states) — recommended before requesting ads. The
    Flutter adapter exposes these as **instance** methods
    `GmaMediationUnity().setGDPRConsent(...)` / `setCCPAConsent(...)` (note:
    Google's guide currently shows a *static* `GmaMediationUnity.setGDPRConsent`
    call, which does not match the published instance API). **Caveat, verified
    against the adapter source (1.8.x through 1.11.1, 2026-10-24):** both
    wrappers are **fire-and-forget** — the method body calls the generated
    platform API *without* `await`ing or returning its `Future`, so the
    `Future<void>` you get back completes on the next microtask **whether or not
    the native SDK has applied the value**. Awaiting the call therefore does
    **not** prove the Unity signal landed before init (see the ordering
    principle below). Do **not** work around this by importing the adapter's
    generated internal API (`UnityPrivacyApi`) or hand-rolling a bridge — both
    are unstable, unsupported internals.
  - *AppLovin*: US-state `setDoNotSell` (and `setHasUserConsent` for
    SDK < 12) — the AppLovin flags must be set **before the Google Mobile
    Ads SDK initializes**.
  - *Meta Audience Network*: GDPR consent arrives via the Additional
    Consent string, but California **Limited Data Use** requires
    `setDataProcessingOptions` on Meta's SDK, set **before the mediation
    SDK initializes** (may require platform-native code).
- **Reading the user's choices** to forward them: read the `IABTCF_*` /
  `IABGPP_*` keys from `SharedPreferences` (Android) / `NSUserDefaults`
  (iOS) — e.g. via `shared_preferences` — per Google's "How to read consent
  choices" guidance.

ad_flow's surfaces for this:

- **Before `AdFlow.initialize()`** — set the partner flags you already know.
  Mediation adapters initialize *during* `MobileAds.initialize()`, and
  AppLovin/Meta read their privacy flag at that point (Google's docs: set it
  "before you initialize the Google Mobile Ads SDK"). Flags the app decides
  itself — AppLovin's US-state `setDoNotSell`, Meta's Limited Data Use — come
  from your own stored settings, so set them first, then call `initialize`.
  GDPR consent itself is read from the TCF string by TCF-reading SDKs.

  > **Removed in 6.0:** `forwardConsent` and `MediationConsentFailurePolicy`,
  > which held `MobileAds.initialize()` back until an app callback finished.
  > No app used them. If you add a partner whose *GDPR* signal cannot come
  > from the TCF string and must be set before init, open an issue — a
  > before-init hook is easy to bring back once there is a real case.

- **`AdFlow.onConsentChanged`** — a fire-and-forget hook that fires after
  every consent flow or mutation (initial gather, a retry that finally
  succeeds offline→online, a privacy-options change). Use it to forward an
  updated choice to partners that read it at request time (Unity's `MetaData`,
  for example). Async rejections are contained (reported, not fatal).

  ```dart
  ads.onConsentChanged = () async {
    final prefs = SharedPreferencesAsync();
    // ...read the IABTCF_* / IABGPP_* keys and forward to request-time partners.
  };
  ```

- **Per-network request extras** — `AdRequestOptions.mediationExtras` on any
  slot's `request` maps to the plugin's `MediationExtras` mechanism. Each
  `MediationNetworkExtras` names the platform adapter class (from the
  `gma_mediation_<network>` package) to instantiate by reflection — keep the
  class names in sync with the adapter package (an empty/typo'd name silently
  no-ops at request time; empty names are asserted against in debug):

  ```dart
  BannerConfig(
    adUnitId: myBanner,
    request: AdRequestOptions(mediationExtras: [
      MediationNetworkExtras(
        androidClassName:
            'com.google.ads.mediation.applovin.AppLovinExtrasBundleBuilder',
        iosClassName: 'GADMAdapterAppLovinExtras',
        extras: {'mute': true},
      ),
    ]),
  );
  ```

**The honest summary:** ad_flow guarantees UMP collection, storage, and the
hooks above. It does not — and cannot — guarantee that every partner SDK
received every signal; that wiring is per-network and stays yours. Verify
with each partner's AdMob mediation page and the Ad Inspector.

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
- [ ] Partners selected under Privacy & messaging (GDPR + US states)
- [ ] Adapters added (`gma_mediation_*` package, or native build files)
- [ ] Init-time partner flags (AppLovin US flag, Meta LDU) set before
      `AdFlow.initialize()`; request-time ones (Unity) in `onConsentChanged` —
      see §4
- [ ] iOS: partner `SKAdNetworkItems` in `Info.plist`
- [ ] `app-ads.txt` updated with partner lines
- [ ] Verified with Ad Inspector on a test device
