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
`gma_mediation_unityads`, `gma_mediation_meta`). Add the ones for your
networks to `pubspec.yaml`; they bundle the correct native adapter on both
platforms and usually expose the network's privacy APIs as Dart calls.
Check each package's compatibility with `google_mobile_ads` 9.x first.

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
  - *Unity Ads*: explicit `MetaData` calls — `gdpr.consent` and
    `privacy.consent` (US states) — recommended before requesting ads
    (`GmaMediationUnity.setGDPRConsent` / `setCCPAConsent` in the Flutter
    adapter package).
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

- **`forwardConsent` — the fail-closed, before-initialize barrier.** Supply
  it to `AdFlow.initialize`; ad_flow runs it after consent settles and
  **before `MobileAds.initialize()`**, then blocks every mediation-capable ad
  request until it has succeeded. This ordering matters: **mediation adapters
  initialize *during* `MobileAds.initialize()`**, and AppLovin/Meta read their
  privacy flag at that point (Google's docs: set it "before you initialize the
  Google Mobile Ads SDK"). Unity reads at request time. Forwarding-before-init
  covers both. Unlike `onConsentChanged` (below) it cannot miss the initial
  flow, cannot be raced by init or the first load, and its callback is never
  invoked concurrently (serialized):

  ```dart
  await AdFlow.initialize(
    config,
    forwardConsent: () async {
      final prefs = await SharedPreferences.getInstance();
      final gdprApplies = prefs.getInt('IABTCF_gdprApplies') == 1;
      final consented = _hasPurpose1(prefs.getString('IABTCF_PurposeConsents'));
      // Set BEFORE the GMA SDK initializes:
      await GmaMediationUnity().setGDPRConsent(gdprApplies && consented);
      // AppLovin US-state / Meta LDU etc. per each partner's page.
    },
  );
  ```

  **Fail-closed by default** (`MediationConsentFailurePolicy.failClosed`): if
  the forwarder fails or times out (15s), the **GMA SDK is not initialized**
  and loads are **blocked** (`AdBlockReason.consentNotForwarded`, visible via
  `onAdBlocked`); the forwarder is retried in the background and everything
  (init + loads) recovers the moment it succeeds. It never blocks your UI:
  `AdFlow.initialize(...)` returns immediately and the app renders its first
  frame; only `whenReady`/ad requests wait. If — and only if — every network
  you use reads the IAB TCF/GPP string itself, set
  `mediationConsentPolicy: MediationConsentFailurePolicy.unsafeFailOpen` to
  initialize/serve even when forwarding fails (revenue-first, unsafe for any
  network that needs its own signal).

  It re-establishes on every consent change (`showPrivacyOptions`, a re-run) —
  best-effort for **request-time** partner reads; an already-initialized
  adapter **cannot be re-initialized**, so an init-time flag is set once,
  before the first init. On a consent change, ad_flow also drops-and-reloads
  any already-loaded warm/visible ad so it re-requests under the fresh consent
  (a full-screen ad on screen is not interrupted). Verify with the Ad
  Inspector.

  > **Removed in 5.0:** the earlier `deferMediationInit` flag. It used the
  > plugin's `disableMediationInitialization`, which is a *session-wide
  > disable* of Google mediation (an A/B-testing tool), not a defer/resume —
  > it could not achieve "set the flag, then let adapters come up." Use
  > `forwardConsent` (which runs before init) instead.

- **`AdFlow.onConsentChanged`** — a fire-and-forget hook that fires after
  every consent flow or mutation (initial gather, a retry that finally
  succeeds offline→online, a privacy-options change). Nothing waits for it, so
  use it for *observability* or for networks whose signal is only needed for
  *later* requests. Assignable only after `initialize` returns, so it may miss
  the initial flow — prefer `forwardConsent` for anything the first request
  depends on. Async rejections are contained (reported, not fatal).

  ```dart
  ads.onConsentChanged = () async {
    final prefs = await SharedPreferences.getInstance();
    // ...forward the updated state to networks needed for later requests.
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
- [ ] Per-network consent APIs wired in `forwardConsent` (awaited, ordered
      before the first request) or `onConsentChanged` (Unity, AppLovin US
      flag, Meta LDU, …) — see §4
- [ ] `forwardConsent` supplied if any partner needs its flag before init
- [ ] iOS: partner `SKAdNetworkItems` in `Info.plist`
- [ ] `app-ads.txt` updated with partner lines
- [ ] Verified with Ad Inspector on a test device
